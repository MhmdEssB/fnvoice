import Foundation

struct TranscriptionEntry: Codable, Identifiable {
    let id: UUID
    let text: String
    let date: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.date = Date()
    }

    init(id: UUID, text: String, date: Date) {
        self.id = id
        self.text = text
        self.date = date
    }
}

final class HistoryService: ObservableObject {
    static let shared = HistoryService()

    @Published private(set) var entries: [TranscriptionEntry] = []

    private let fileURL: URL
    private let maxAge: TimeInterval = 24 * 60 * 60 // 24 hours

    private init() {
        fileURL = AppFolder.url.appendingPathComponent("history.json")
        load()
        cleanup()
    }

    func add(_ text: String) {
        let entry = TranscriptionEntry(text: text)
        entries.insert(entry, at: 0)
        cleanup()
    }

    /// Replaces the text of an entry (user correction).
    func update(_ entry: TranscriptionEntry, text: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = TranscriptionEntry(id: entry.id, text: text, date: entry.date)
        save()
    }

    func delete(_ entry: TranscriptionEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    private func cleanup() {
        let now = Date()
        entries.removeAll { now.timeIntervalSince($0.date) > maxAge }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TranscriptionEntry].self, from: data) else {
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL)
    }
}
