import Foundation

private enum GemmaDownloadTuning {
    /// Size of each parallel chunk. Smaller chunks give finer resume granularity;
    /// the number of parallel connections is what actually speeds up the transfer.
    static let chunkSize: Int64 = 64 * 1024 * 1024
    /// Maximum number of simultaneous chunk connections.
    static let maxConcurrentChunks = 8
}

enum GemmaDownloadError: LocalizedError {
    case invalidResponse
    case missingContentLength
    case rangeNotSupported

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The model server returned an unexpected response."
        case .missingContentLength:
            return "The model server did not report the file size."
        case .rangeNotSupported:
            return "The model server does not support resumable downloads."
        }
    }
}

final class GemmaModelManager: NSObject, ObservableObject {
    enum DownloadState: Equatable {
        case notDownloaded
        case downloading(Double)
        case paused(Double)
        case downloaded
        case failed(String)

        var fractionCompleted: Double {
            switch self {
            case .downloading(let fraction), .paused(let fraction): return fraction
            default: return 0
            }
        }

        var isPaused: Bool {
            if case .paused = self { return true }
            return false
        }
    }

    /// Single shared manager so the settings UI and the recognition view models all
    /// observe the same state and download.
    static let shared = GemmaModelManager()

    static let localDirectoryName = "GemmaModels"

    @Published private(set) var states: [GemmaModelKind: DownloadState] = [:]

    private struct Chunk {
        let index: Int
        let start: Int64
        let end: Int64
        var received: Int64
        var isComplete: Bool

        var length: Int64 { max(0, end - start + 1) }
    }

    private final class Download {
        let kind: GemmaModelKind
        let destination: URL
        let directory: URL
        let baseURL: URL
        let totalBytes: Int64
        let supportsRange: Bool
        var chunks: [Chunk]
        var pending: [Int]
        var inFlight: Set<Int> = []
        var handles: [Int: FileHandle] = [:]
        var tasks: [Int: URLSessionDataTask] = [:]
        var isPaused = false
        var isFinalizing = false
        var lastPublish = Date.distantPast

        init(
            kind: GemmaModelKind,
            destination: URL,
            directory: URL,
            baseURL: URL,
            totalBytes: Int64,
            supportsRange: Bool,
            chunks: [Chunk],
            pending: [Int]
        ) {
            self.kind = kind
            self.destination = destination
            self.directory = directory
            self.baseURL = baseURL
            self.totalBytes = totalBytes
            self.supportsRange = supportsRange
            self.chunks = chunks
            self.pending = pending
        }

        var receivedBytes: Int64 { chunks.reduce(0) { $0 + $1.received } }
        var isComplete: Bool { chunks.allSatisfy { $0.isComplete } }

        func partURL(_ index: Int) -> URL {
            directory.appendingPathComponent("part-\(index).bin")
        }

        var metaURL: URL { directory.appendingPathComponent("download.meta") }
    }

    private let lock = NSLock()
    private var downloads: [GemmaModelKind: Download] = [:]
    private var taskMap: [Int: (kind: GemmaModelKind, chunk: Int)] = [:]
    private var session: URLSession!
    private let probeSession: URLSession
    private let finalizeQueue = DispatchQueue(label: "com.eyepal.gemma.finalize", qos: .utility)
    private let delegateQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        return queue
    }()

    override init() {
        probeSession = URLSession(configuration: .ephemeral)
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60 * 24
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = GemmaDownloadTuning.maxConcurrentChunks
        session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        refreshStates()
    }

    /// Kept for the app delegate. Downloads now run in a regular session, so there
    /// is no background session to adopt.
    static func handleEventsForBackgroundURLSession(_ identifier: String, completion: @escaping () -> Void) {
        completion()
    }

    static var modelsDirectoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(localDirectoryName, isDirectory: true)
    }

    var isAnyModelDownloaded: Bool {
        GemmaModelKind.allCases.contains { fileURL(for: $0).exists() }
    }

    func downloadedModelURL() -> URL? {
        let order: [GemmaModelKind] = [.e2b, .e4b]
        for kind in order where fileURL(for: kind).exists() {
            return fileURL(for: kind)
        }
        return nil
    }

    func modelURL(for kind: GemmaModelKind? = nil) -> URL? {
        if let kind {
            let url = fileURL(for: kind)
            if url.exists() { return url }
        }
        return downloadedModelURL()
    }

    func fileURL(for kind: GemmaModelKind) -> URL {
        Self.modelsDirectoryURL
            .appendingPathComponent(kind.directoryName, isDirectory: true)
            .appendingPathComponent(kind.fileName)
    }

    func refreshStates() {
        for kind in GemmaModelKind.allCases {
            if fileURL(for: kind).exists() {
                states[kind] = .downloaded
                continue
            }
            if let current = states[kind], case .downloading = current { continue }
            if let current = states[kind], case .paused = current { continue }
            states[kind] = .notDownloaded
        }
    }

    // MARK: - Public actions

    /// Starts (or continues) a download. Part files on disk are reused, so this
    /// doubles as "resume".
    func download(_ kind: GemmaModelKind) {
        guard !fileURL(for: kind).exists() else {
            setState(kind, .downloaded)
            return
        }

        lock.lock()
        if let existing = downloads[kind], !existing.isPaused, !existing.inFlight.isEmpty {
            lock.unlock()
            return
        }
        lock.unlock()

        Task { [weak self] in
            guard let self else { return }
            do {
                let download = try await self.prepareDownload(kind)
                self.lock.lock()
                self.downloads[kind] = download
                self.lock.unlock()
                self.setState(kind, .downloading(self.fraction(for: download)))
                self.pump(kind)
            } catch {
                self.setState(kind, .failed(error.localizedDescription))
            }
        }
    }

    func pause(_ kind: GemmaModelKind) {
        lock.lock()
        guard let download = downloads[kind] else {
            lock.unlock()
            return
        }
        download.isPaused = true
        let tasks = Array(download.tasks.values)
        let fraction = fraction(for: download)
        download.inFlight.removeAll()
        download.tasks.removeAll()
        for handle in download.handles.values { try? handle.close() }
        download.handles.removeAll()
        for task in tasks { taskMap[task.taskIdentifier] = nil }
        lock.unlock()

        for task in tasks { task.cancel() }
        setState(kind, .paused(fraction))
    }

    func delete(_ kind: GemmaModelKind) {
        stop(kind)
        let directory = fileURL(for: kind).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: directory)
        setState(kind, .notDownloaded)
    }

    func isDownloading(_ kind: GemmaModelKind) -> Bool {
        if case .downloading = states[kind] { return true }
        return false
    }

    private func stop(_ kind: GemmaModelKind) {
        lock.lock()
        let download = downloads.removeValue(forKey: kind)
        if let download {
            for task in download.tasks.values {
                taskMap[task.taskIdentifier] = nil
                task.cancel()
            }
            for handle in download.handles.values { try? handle.close() }
        }
        lock.unlock()
    }

    // MARK: - Preparation

    private struct Probe {
        let totalBytes: Int64
        let supportsRange: Bool
        let etag: String?
    }

    private func prepareDownload(_ kind: GemmaModelKind) async throws -> Download {
        let destination = fileURL(for: kind)
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var lastError: Error = GemmaDownloadError.invalidResponse
        for candidate in kind.downloadURLs {
            do {
                let probe = try await probe(candidate)
                return try makeDownload(
                    kind: kind,
                    destination: destination,
                    directory: directory,
                    baseURL: candidate,
                    probe: probe
                )
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func probe(_ url: URL) async throws -> Probe {
        var request = URLRequest(url: url)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.timeoutInterval = 30
        let (_, response) = try await probeSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GemmaDownloadError.invalidResponse }

        let etag = http.value(forHTTPHeaderField: "ETag")
        let acceptRanges = http.value(forHTTPHeaderField: "Accept-Ranges")

        if http.statusCode == 206,
           let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
           let totalPart = contentRange.split(separator: "/").last,
           let total = Int64(totalPart.trimmingCharacters(in: .whitespaces)) {
            return Probe(totalBytes: total, supportsRange: true, etag: etag)
        }

        if http.statusCode == 200,
           let length = http.value(forHTTPHeaderField: "Content-Length"),
           let total = Int64(length), total > 0 {
            return Probe(
                totalBytes: total,
                supportsRange: acceptRanges?.lowercased().contains("bytes") ?? false,
                etag: etag
            )
        }

        throw GemmaDownloadError.missingContentLength
    }

    private func makeDownload(
        kind: GemmaModelKind,
        destination: URL,
        directory: URL,
        baseURL: URL,
        probe: Probe
    ) throws -> Download {
        let metaURL = directory.appendingPathComponent("download.meta")
        let previousMeta = (try? String(contentsOf: metaURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // If the remote file changed, any partial parts are unusable.
        if let previousMeta,
           let previousEtag = previousMeta.split(separator: "|").first.map(String.init),
           let probeEtag = probe.etag,
           previousEtag != probeEtag {
            removeParts(directory: directory)
        }
        if let probeEtag = probe.etag {
            try? "\(probeEtag)|\(probe.totalBytes)".write(to: metaURL, atomically: true, encoding: .utf8)
        }

        var chunks: [Chunk] = []
        if probe.supportsRange {
            var start: Int64 = 0
            var index = 0
            while start < probe.totalBytes {
                let end = min(start + GemmaDownloadTuning.chunkSize, probe.totalBytes) - 1
                chunks.append(makeChunk(index: index, start: start, end: end, directory: directory))
                start = end + 1
                index += 1
            }
        } else {
            chunks.append(makeChunk(index: 0, start: 0, end: probe.totalBytes - 1, directory: directory))
        }

        let pending = chunks.filter { !$0.isComplete }.map(\.index)
        return Download(
            kind: kind,
            destination: destination,
            directory: directory,
            baseURL: baseURL,
            totalBytes: probe.totalBytes,
            supportsRange: probe.supportsRange,
            chunks: chunks,
            pending: pending
        )
    }

    private func makeChunk(index: Int, start: Int64, end: Int64, directory: URL) -> Chunk {
        let length = end - start + 1
        let partURL = directory.appendingPathComponent("part-\(index).bin")
        let existing = fileSize(partURL)
        let received = min(existing, length)
        return Chunk(index: index, start: start, end: end, received: received, isComplete: received >= length)
    }

    // MARK: - Transfer

    private func pump(_ kind: GemmaModelKind) {
        lock.lock()
        guard let download = downloads[kind], !download.isPaused, !download.isFinalizing else {
            lock.unlock()
            return
        }

        var started: [URLSessionDataTask] = []
        while download.inFlight.count < GemmaDownloadTuning.maxConcurrentChunks, !download.pending.isEmpty {
            let index = download.pending.removeFirst()
            if download.chunks[index].isComplete { continue }

            let chunk = download.chunks[index]
            var request = URLRequest(url: download.baseURL)
            request.timeoutInterval = 60
            if download.supportsRange {
                request.setValue("bytes=\(chunk.start + chunk.received)-\(chunk.end)", forHTTPHeaderField: "Range")
            }

            let partURL = download.partURL(index)
            if !FileManager.default.fileExists(atPath: partURL.path) {
                _ = FileManager.default.createFile(atPath: partURL.path, contents: nil)
            }
            guard let handle = try? FileHandle(forWritingTo: partURL) else {
                download.pending.insert(index, at: 0)
                break
            }
            try? handle.seekToEnd()

            let task = session.dataTask(with: request)
            download.handles[index] = handle
            download.tasks[index] = task
            download.inFlight.insert(index)
            taskMap[task.taskIdentifier] = (kind, index)
            started.append(task)
        }
        lock.unlock()

        for task in started { task.resume() }
    }

    private func completeChunk(kind: GemmaModelKind, chunkIndex: Int) {
        lock.lock()
        guard let download = downloads[kind] else {
            lock.unlock()
            return
        }
        download.inFlight.remove(chunkIndex)
        download.tasks[chunkIndex] = nil
        if let handle = download.handles[chunkIndex] {
            try? handle.close()
            download.handles[chunkIndex] = nil
        }
        let size = fileSize(download.partURL(chunkIndex))
        download.chunks[chunkIndex].received = size
        download.chunks[chunkIndex].isComplete = size >= download.chunks[chunkIndex].length
        let allComplete = download.isComplete
        if allComplete { download.isFinalizing = true }
        let paused = download.isPaused
        lock.unlock()

        if allComplete {
            finalize(kind)
        } else if !paused {
            pump(kind)
        }
    }

    private func failChunk(kind: GemmaModelKind, chunkIndex: Int, error: Error?) {
        lock.lock()
        guard let download = downloads[kind] else {
            lock.unlock()
            return
        }
        download.inFlight.remove(chunkIndex)
        download.tasks[chunkIndex] = nil
        if let handle = download.handles[chunkIndex] {
            try? handle.close()
            download.handles[chunkIndex] = nil
        }
        lock.unlock()

        if let error, (error as NSError).code == NSURLErrorCancelled {
            // Paused or cancelled — keep the part file and stay quiet.
            return
        }
        let message = error?.localizedDescription
            ?? GemmaDownloadError.invalidResponse.localizedDescription
        setState(kind, .failed(message))
    }

    private func finalize(_ kind: GemmaModelKind) {
        lock.lock()
        guard let download = downloads[kind] else {
            lock.unlock()
            return
        }
        lock.unlock()

        finalizeQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.mergeParts(download)
                self.lock.lock()
                self.downloads[kind] = nil
                self.lock.unlock()
                self.setState(kind, .downloaded)
            } catch {
                self.lock.lock()
                self.downloads[kind]?.isFinalizing = false
                self.lock.unlock()
                self.setState(kind, .failed(error.localizedDescription))
            }
        }
    }

    private func mergeParts(_ download: Download) throws {
        let tempURL = download.directory
            .appendingPathComponent(download.destination.lastPathComponent + ".merged")
        if FileManager.default.fileExists(atPath: tempURL.path) {
            try FileManager.default.removeItem(at: tempURL)
        }
        _ = FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: tempURL)
        do {
            for chunk in download.chunks.sorted(by: { $0.index < $1.index }) {
                let input = try FileHandle(forReadingFrom: download.partURL(chunk.index))
                defer { try? input.close() }
                while true {
                    let data = try input.read(upToCount: 4 * 1024 * 1024) ?? Data()
                    if data.isEmpty { break }
                    try output.write(contentsOf: data)
                }
            }
            try output.close()
        } catch {
            try? output.close()
            throw error
        }

        if FileManager.default.fileExists(atPath: download.destination.path) {
            try FileManager.default.removeItem(at: download.destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: download.destination)

        for chunk in download.chunks {
            try? FileManager.default.removeItem(at: download.partURL(chunk.index))
        }
        try? FileManager.default.removeItem(at: download.metaURL)
    }

    // MARK: - Progress

    private func fraction(for download: Download) -> Double {
        guard download.totalBytes > 0 else { return 0 }
        return min(max(Double(download.receivedBytes) / Double(download.totalBytes), 0), 1)
    }

    private func publishProgress(_ kind: GemmaModelKind, force: Bool) {
        lock.lock()
        guard let download = downloads[kind], !download.isPaused else {
            lock.unlock()
            return
        }
        let now = Date()
        if !force, now.timeIntervalSince(download.lastPublish) < 0.25 {
            lock.unlock()
            return
        }
        download.lastPublish = now
        let fraction = fraction(for: download)
        lock.unlock()
        setState(kind, .downloading(fraction))
    }

    private func setState(_ kind: GemmaModelKind, _ state: DownloadState) {
        DispatchQueue.main.async { [weak self] in
            self?.states[kind] = state
        }
    }

    // MARK: - Helpers

    private func fileSize(_ url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.int64Value
    }

    private func removeParts(directory: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("part-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

extension GemmaModelKind {
    func displayState(_ state: GemmaModelManager.DownloadState) -> String {
        switch state {
        case .notDownloaded:
            return NSLocalizedString("gemma.status.notDownloaded", comment: "")
        case .downloaded:
            return NSLocalizedString("gemma.status.downloaded", comment: "")
        case .downloading(let fraction):
            let percent = Int((fraction * 100).rounded())
            return String(format: NSLocalizedString("gemma.status.downloading", comment: ""), percent)
        case .paused(let fraction):
            let percent = Int((fraction * 100).rounded())
            return String(format: NSLocalizedString("gemma.status.paused", comment: ""), percent)
        case .failed(let message):
            return message
        }
    }
}

extension GemmaModelManager: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard let entry = taskMap[dataTask.taskIdentifier],
              let download = downloads[entry.kind],
              let handle = download.handles[entry.chunk] else {
            lock.unlock()
            return
        }
        download.chunks[entry.chunk].received += Int64(data.count)
        try? handle.write(contentsOf: data)
        lock.unlock()

        publishProgress(entry.kind, force: false)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        let entry = taskMap[dataTask.taskIdentifier]
        let ranged = entry.flatMap { downloads[$0.kind]?.supportsRange } ?? false
        lock.unlock()

        if let entry, ranged, let http = response as? HTTPURLResponse, http.statusCode != 206 {
            // The server ignored our Range request; continuing would corrupt the
            // part file, so abort this attempt.
            completionHandler(.cancel)
            setState(entry.kind, .failed(GemmaDownloadError.rangeNotSupported.localizedDescription))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let entry = taskMap.removeValue(forKey: task.taskIdentifier)
        let paused = entry.flatMap { downloads[$0.kind]?.isPaused } ?? false
        lock.unlock()

        guard let entry else { return }
        if paused { return }

        lock.lock()
        let partSize = downloads[entry.kind].map { fileSize($0.partURL(entry.chunk)) } ?? 0
        let expected = downloads[entry.kind]?.chunks[entry.chunk].length ?? 0
        lock.unlock()

        if partSize >= expected {
            completeChunk(kind: entry.kind, chunkIndex: entry.chunk)
        } else {
            failChunk(kind: entry.kind, chunkIndex: entry.chunk, error: error)
        }
    }
}

private extension URL {
    func exists() -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
