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

    func load(context: Context) {
        let file = File(context.filesDir, fileName)
        guard file.exists() else { return }
        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode([FaceRecognitionLogEntry].self, from: data) {
            entries = decoded
        }
    }

    func save(context: Context) {
        let file = File(context.filesDir, fileName)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: file, options: .atomic)
        }
    }

    func append(message: String, context: Context) {
        let entry = FaceRecognitionLogEntry(message: message)
        entries.insert(entry, at: 0)
        if entries.count > 50 {
            entries = Array(entries.prefix(50))
        }
        save(context)
    }

    func clear(context: Context) {
        entries.removeAll()
        save(context)
    }
}
