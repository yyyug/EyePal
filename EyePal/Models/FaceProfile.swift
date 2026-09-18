import Foundation

struct FaceProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var sampleEmbeddings: [[Float]]
    var sampleImageFilename: String?
    var voiceNoteFilename: String?

    var embedding: [Float] {
        sampleEmbeddings.first ?? []
    }

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sampleEmbeddings: [[Float]],
        sampleImageFilename: String? = nil,
        voiceNoteFilename: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sampleEmbeddings = sampleEmbeddings
        self.sampleImageFilename = sampleImageFilename
        self.voiceNoteFilename = voiceNoteFilename
    }

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        embedding: [Float],
        sampleImageFilename: String? = nil,
        voiceNoteFilename: String? = nil
    ) {
        self.init(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sampleEmbeddings: [embedding],
            sampleImageFilename: sampleImageFilename,
            voiceNoteFilename: voiceNoteFilename
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case updatedAt
        case sampleEmbeddings
        case embedding
        case sampleImageFilename
        case voiceNoteFilename
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        sampleImageFilename = try container.decodeIfPresent(String.self, forKey: .sampleImageFilename)
        voiceNoteFilename = try container.decodeIfPresent(String.self, forKey: .voiceNoteFilename)

        if let sampleEmbeddings = try container.decodeIfPresent([[Float]].self, forKey: .sampleEmbeddings),
           !sampleEmbeddings.isEmpty {
            self.sampleEmbeddings = sampleEmbeddings
        } else if let embedding = try container.decodeIfPresent([Float].self, forKey: .embedding),
                  !embedding.isEmpty {
            sampleEmbeddings = [embedding]
        } else {
            sampleEmbeddings = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(sampleEmbeddings, forKey: .sampleEmbeddings)
        try container.encodeIfPresent(sampleImageFilename, forKey: .sampleImageFilename)
        try container.encodeIfPresent(voiceNoteFilename, forKey: .voiceNoteFilename)
    }
}