import Foundation
import Combine

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let input: String
    let output: String
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    private let key = "jt.history"
    private let maxCount = 10

    @Published private(set) var entries: [HistoryEntry] = []

    private init() {
        load()
    }

    func add(input: String, output: String) {
        let entry = HistoryEntry(id: UUID(), date: Date(), input: input, output: output)
        entries.insert(entry, at: 0)
        if entries.count > maxCount {
            entries = Array(entries.prefix(maxCount))
        }
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data)
        else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
