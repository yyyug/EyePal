import Foundation

struct FaceRecognitionLogEntry: Identifiable, Codable {
    let id: UUID
    let message: String
    let timestamp: Date

    init(id: UUID = UUID(), message: String, timestamp: Date = Date()) {
        self.id = id
        self.message = message
        self.timestamp = timestamp
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

class FaceRecognitionLogStore {
    static let shared = FaceRecognitionLogStore()
    private let fileName = "face_recognition_log.json"
    private var entries: [FaceRecognitionLogEntry] = []

    var allEntries: [FaceRecognitionLogEntry] { entries }

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([FaceRecognitionLogEntry].self, from: data) else { return }
        entries = decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func append(message: String) {
        let entry = FaceRecognitionLogEntry(message: message)
        entries.insert(entry, at: 0)
        if entries.count > 50 {
            entries = Array(entries.prefix(50))
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }
}
