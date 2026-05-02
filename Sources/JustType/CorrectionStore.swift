import Foundation

/// Lightweight on-disk store of `(raw → bad → good)` triples — every time
/// JustType detects that the user manually edited a chunk of text after we
/// pasted it, we record it here. Recent entries are added to the system
/// prompt so the model can learn this user's preferences over time.
final class CorrectionStore: ObservableObject {
    struct Correction: Codable, Hashable {
        let raw: String         // user's original keystrokes
        let badOutput: String   // what JustType produced
        let goodOutput: String  // what the user changed it to
        let date: Date
    }

    static let shared = CorrectionStore()

    private let queue = DispatchQueue(label: "justype.corrections", qos: .utility)
    private let url: URL
    /// Hard cap on how many corrections we keep on disk. The oldest are
    /// dropped first.
    private let maxEntries = 50

    @Published private(set) var entries: [Correction] = []

    private init() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = appSupport.appendingPathComponent("JustType", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("corrections.json")
        load()
    }

    /// Returns the most recent `n` corrections. Used to seed the system
    /// prompt as few-shot examples.
    func recent(_ n: Int) -> [Correction] {
        Array(entries.suffix(n))
    }

    /// Append a new correction. Empty/identical edits are dropped, and
    /// duplicates of the most recent entry are coalesced so a flurry of
    /// keystrokes doesn't fill the file.
    func add(raw: String, badOutput: String, goodOutput: String) {
        let raw = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let bad = badOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let good = goodOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !bad.isEmpty, !good.isEmpty else { return }
        guard bad != good else { return }
        // Cap individual fields to keep the file small.
        let entry = Correction(
            raw: String(raw.prefix(400)),
            badOutput: String(bad.prefix(400)),
            goodOutput: String(good.prefix(400)),
            date: Date()
        )
        if let last = entries.last,
           last.raw == entry.raw, last.badOutput == entry.badOutput, last.goodOutput == entry.goodOutput {
            return
        }
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        persist()
    }

    func clear() {
        entries = []
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([Correction].self, from: data) {
            self.entries = decoded
        }
    }

    private func persist() {
        let snapshot = entries
        let dst = url
        queue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: dst, options: .atomic)
            }
        }
    }
}
