import Foundation

/// Thread-safe mapping from `URLSessionTask.taskIdentifier` to a model kind so
/// the nonisolated download delegate can route progress/result callbacks.
final class GemmaTaskRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tags: [Int: GemmaModelKind] = [:]

    func set(_ kind: GemmaModelKind, for identifier: Int) {
        lock.lock()
        tags[identifier] = kind
        lock.unlock()
    }

    func remove(for identifier: Int) {
        lock.lock()
        tags[identifier] = nil
        lock.unlock()
    }

    func kind(for identifier: Int) -> GemmaModelKind? {
        lock.lock()
        defer { lock.unlock() }
        return tags[identifier]
    }
}

final class GemmaModelManager: NSObject, ObservableObject {
    enum DownloadState: Equatable {
        case notDownloaded
        case downloading(Double)
        case downloaded
        case failed(String)

        var fractionCompleted: Double {
            switch self {
            case .downloading(let fraction): return fraction
            default: return 0
            }
        }
    }

    static let localDirectoryName = "GemmaModels"

    @Published private(set) var states: [GemmaModelKind: DownloadState] = [:]

    private var activeTasks: [GemmaModelKind: URLSessionDownloadTask] = [:]
    private let registry = GemmaTaskRegistry()
    private var bytesReceived: [GemmaModelKind: Int64] = [:]
    private var session: URLSession!

    override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        super.init()
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        refreshStates()
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

    func fileURL(for kind: GemmaModelKind) -> URL {
        Self.modelsDirectoryURL
            .appendingPathComponent(kind.directoryName, isDirectory: true)
            .appendingPathComponent(kind.fileName)
    }

    func refreshStates() {
        for kind in GemmaModelKind.allCases {
            if fileURL(for: kind).exists() {
                states[kind] = .downloaded
            } else if case .downloading = states[kind] {
                // keep current download progress
            } else {
                states[kind] = .notDownloaded
            }
        }
    }

    func download(_ kind: GemmaModelKind) {
        guard !fileURL(for: kind).exists() else {
            states[kind] = .downloaded
            return
        }
        guard activeTasks[kind] == nil else { return }

        states[kind] = .downloading(0)
        bytesReceived[kind] = 0

        var request = URLRequest(url: kind.downloadURL)
        request.timeoutInterval = 300
        let task = session.downloadTask(with: request)
        activeTasks[kind] = task
        registry.set(kind, for: task.taskIdentifier)
        task.resume()
    }

    func delete(_ kind: GemmaModelKind) {
        cancel(kind)
        let dir = fileURL(for: kind).deletingLastPathComponent()
        try? FileManager.default.removeItem(at: dir)
        states[kind] = .notDownloaded
    }

    func cancel(_ kind: GemmaModelKind) {
        if let task = activeTasks[kind] {
            registry.remove(for: task.taskIdentifier)
            task.cancel()
        }
        activeTasks[kind] = nil
        states[kind] = .notDownloaded
    }

    func isDownloading(_ kind: GemmaModelKind) -> Bool {
        if case .downloading = states[kind] { return true }
        return false
    }

    private func registerFinish(kind: GemmaModelKind, task: URLSessionTask) {
        activeTasks[kind] = nil
        registry.remove(for: task.taskIdentifier)
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
        case .failed(let message):
            return message
        }
    }
}

extension GemmaModelManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let kind = registry.kind(for: downloadTask.taskIdentifier) else { return }
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : totalBytesWritten
        Task { @MainActor in
            self.bytesReceived[kind] = totalBytesWritten
            let fraction = expected > 0 ? Double(totalBytesWritten) / Double(expected) : 1
            self.states[kind] = .downloading(min(max(fraction, 0), 1))
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let kind = registry.kind(for: downloadTask.taskIdentifier) else { return }
        let destination = fileURL(for: kind)
        Task { @MainActor in
            do {
                let directory = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: location, to: destination)
                self.registerFinish(kind: kind, task: downloadTask)
                self.states[kind] = .downloaded
            } catch {
                self.registerFinish(kind: kind, task: downloadTask)
                self.states[kind] = .failed(error.localizedDescription)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let kind = registry.kind(for: task.taskIdentifier) else { return }
        guard let error else { return }
        Task { @MainActor in
            if self.fileURL(for: kind).exists() {
                self.states[kind] = .downloaded
            } else {
                self.states[kind] = .failed(error.localizedDescription)
            }
            self.registerFinish(kind: kind, task: task)
        }
    }
}

private extension URL {
    func exists() -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
