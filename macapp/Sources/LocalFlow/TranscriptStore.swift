import Foundation

struct TranscriptEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    let targetApplication: String?
    let pasteMethod: String?
    let pasteSucceeded: Bool?

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = Date(),
        targetApplication: String? = nil,
        pasteMethod: String? = nil,
        pasteSucceeded: Bool? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.targetApplication = targetApplication
        self.pasteMethod = pasteMethod
        self.pasteSucceeded = pasteSucceeded
    }
}

@MainActor
@Observable
final class TranscriptStore {
    private(set) var entries: [TranscriptEntry] = []

    private let fileURL: URL
    private let maxEntries = 200

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LocalFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("transcripts.json")
        load()
    }

    func add(
        _ text: String,
        targetApplication: String? = nil,
        pasteMethod: String? = nil,
        pasteSucceeded: Bool? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        entries.insert(
            TranscriptEntry(
                text: trimmed,
                targetApplication: targetApplication,
                pasteMethod: pasteMethod,
                pasteSucceeded: pasteSucceeded
            ),
            at: 0
        )
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    func delete(_ id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([TranscriptEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
