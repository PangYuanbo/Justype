import Foundation
import AppKit

/// State for an active "magic input" session — the user has tapped the
/// trigger key and is now typing into a floating box. On pause we ask the
/// LLM to convert the trailing raw segment into a candidate; ↩ commits it,
/// another tap of the trigger finalizes everything and injects.
final class MagicSession: ObservableObject {
    /// Text the user has already accepted (via ↩) — locked in.
    @Published var committed: String = ""
    /// The current raw keyboard segment being typed (not yet converted).
    @Published var raw: String = ""
    /// Insertion point inside `raw`, in characters from the start. Lets the
    /// user move the caret with arrow keys and edit mid-segment.
    @Published var rawCursor: Int = 0
    /// LLM-converted candidate of `raw`, shown below as IME-style preview.
    @Published var candidate: String? = nil
    /// True while an LLM call for the current raw is in flight.
    @Published var converting: Bool = false
    /// Most recent error message (transient).
    @Published var errorMessage: String? = nil
    /// True when the user has explicitly selected the entire box
    /// (click on the HUD or ⌘A). The next typed character replaces
    /// everything, or Backspace clears it.
    @Published var allSelected: Bool = false

    /// Optional screenshot taken at session start, reused for every LLM call.
    private var contextImage: Data? = nil

    /// Per-session log of every (raw → committed) pair. Used by the
    /// post-paste edit watcher to attribute corrections.
    private(set) var rawHistory: [String] = []

    /// All raw segments concatenated with single spaces — useful as a single
    /// "what the user originally typed" payload for correction attribution.
    var combinedRaw: String {
        rawHistory.joined(separator: " ")
    }

    private var debounceTask: DispatchWorkItem?
    private var inFlightForRaw: String? = nil

    /// Debounce delay before auto-converting the current raw segment.
    private let debounceInterval: TimeInterval = 0.5

    /// Reset to a fresh session.
    func startNew() {
        debounceTask?.cancel()
        debounceTask = nil
        inFlightForRaw = nil
        committed = ""
        raw = ""
        rawCursor = 0
        candidate = nil
        converting = false
        errorMessage = nil
        allSelected = false
        rawHistory = []
        contextImage = AppState.shared.useScreenContext
            ? Screenshotter.capturePrimary()
            : nil
    }

    var isEmpty: Bool { committed.isEmpty && raw.isEmpty }

    // MARK: - Edit operations

    func append(_ s: String) {
        // If everything is currently "selected", treat the next character as
        // a replacement: blow away committed + raw, then insert.
        if allSelected {
            committed = ""
            raw = ""
            rawCursor = 0
            allSelected = false
        }
        // Insert at the caret rather than always appending, so the user can
        // edit mid-segment after moving with arrow keys.
        let insertIdx = clampedCursorIndex()
        raw.insert(contentsOf: s, at: insertIdx)
        rawCursor = min(rawCursor + s.count, raw.count)
        candidate = nil
        errorMessage = nil
        scheduleConvert()
    }

    /// Backspace: delete the character to the left of the caret. When
    /// `allSelected` is on, clears the entire box instead.
    func backspace() {
        if allSelected {
            committed = ""
            raw = ""
            rawCursor = 0
            candidate = nil
            errorMessage = nil
            allSelected = false
            debounceTask?.cancel()
            debounceTask = nil
            return
        }
        if rawCursor > 0 && !raw.isEmpty {
            let target = raw.index(raw.startIndex, offsetBy: rawCursor - 1)
            raw.remove(at: target)
            rawCursor -= 1
            candidate = nil
            errorMessage = nil
            if raw.isEmpty {
                debounceTask?.cancel()
                debounceTask = nil
            } else {
                scheduleConvert()
            }
        } else if rawCursor == 0 && raw.isEmpty && !committed.isEmpty {
            // Pull last character off committed text so the user can edit it.
            committed.removeLast()
        }
    }

    /// Select everything currently displayed in the box. Triggered by ⌘A or
    /// a click on the HUD.
    func selectAll() {
        if committed.isEmpty && raw.isEmpty {
            allSelected = false
            return
        }
        allSelected = true
    }

    /// Drop the "all selected" highlight without modifying the buffer. Used
    /// when a non-mutating action (arrow key, Esc) happens after select-all.
    func deselect() {
        if allSelected { allSelected = false }
    }

    /// Forward delete (Fn+Delete on Mac): delete the character to the right
    /// of the caret. When `allSelected` is on, behaves like Backspace and
    /// clears everything.
    func forwardDelete() {
        if allSelected {
            backspace()
            return
        }
        guard rawCursor < raw.count else { return }
        let target = raw.index(raw.startIndex, offsetBy: rawCursor)
        raw.remove(at: target)
        candidate = nil
        errorMessage = nil
        if raw.isEmpty {
            debounceTask?.cancel()
            debounceTask = nil
        } else {
            scheduleConvert()
        }
    }

    func moveCursorLeft() {
        deselect()
        if rawCursor > 0 { rawCursor -= 1 }
    }

    func moveCursorRight() {
        deselect()
        if rawCursor < raw.count { rawCursor += 1 }
    }

    func moveCursorHome() {
        deselect()
        rawCursor = 0
    }

    func moveCursorEnd() {
        deselect()
        rawCursor = raw.count
    }

    private func clampedCursorIndex() -> String.Index {
        let safe = max(0, min(rawCursor, raw.count))
        return raw.index(raw.startIndex, offsetBy: safe)
    }

    /// Enter pressed: commit the current candidate. If no candidate exists yet
    /// (raw too fresh), force-convert first then commit.
    func commitCandidateOrConvertNow() async {
        if let c = candidate {
            rawHistory.append(raw)
            committed += c
            raw = ""
            rawCursor = 0
            candidate = nil
            debounceTask?.cancel()
            debounceTask = nil
            return
        }
        guard !raw.isEmpty else { return }
        await convertNowAndCommit()
    }

    /// Trigger key pressed again: finalize. Returns the full text to inject.
    func finalize() async -> String {
        debounceTask?.cancel()
        debounceTask = nil
        if let c = candidate {
            committed += c
            raw = ""
            candidate = nil
        } else if !raw.isEmpty {
            await convertNowAndCommit()
        }
        return committed
    }

    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
        inFlightForRaw = nil
        committed = ""
        raw = ""
        candidate = nil
        converting = false
        errorMessage = nil
    }

    // MARK: - LLM

    private func scheduleConvert() {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            Task { [weak self] in await self?.convertCurrent() }
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: task)
    }

    private func convertCurrent() async {
        let snapshot = raw
        guard !snapshot.isEmpty else { return }
        guard inFlightForRaw != snapshot else { return }
        inFlightForRaw = snapshot
        converting = true
        defer {
            if inFlightForRaw == snapshot { inFlightForRaw = nil }
            converting = false
        }
        do {
            let result = try await LLMClient.shared.convert(
                snapshot,
                imageData: contextImage,
                prefixContext: committed
            )
            // Only apply if the raw hasn't changed underneath us.
            if raw == snapshot {
                candidate = result
                errorMessage = nil
            }
        } catch {
            if raw == snapshot {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func convertNowAndCommit() async {
        let snapshot = raw
        guard !snapshot.isEmpty else { return }
        debounceTask?.cancel()
        debounceTask = nil
        converting = true
        defer { converting = false }
        do {
            let result = try await LLMClient.shared.convert(
                snapshot,
                imageData: contextImage,
                prefixContext: committed
            )
            if raw == snapshot {
                rawHistory.append(snapshot)
                committed += result
                raw = ""
                rawCursor = 0
                candidate = nil
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
