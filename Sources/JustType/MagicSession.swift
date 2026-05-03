import Foundation
import AppKit

/// State for an active "magic input" session. The user types ASCII into
/// a single editable buffer; one *raw window* tracks whatever they're
/// currently typing — it auto-converts on pause and is replaced in-place
/// when a candidate is accepted. Clicking or arrow-keying outside the
/// raw window freezes it (the typed text stays in the buffer as-is, no
/// longer auto-convertible). Typing again — anywhere — opens a new raw
/// window at that location, so editing already-converted text naturally
/// triggers a fresh conversion of just that edit.
final class MagicSession: ObservableObject {
    /// The full buffer shown in the magic box.
    @Published var text: String = ""
    /// Caret position, in characters from the start of `text`.
    @Published var cursor: Int = 0
    /// The currently-active raw window — what the user is typing right
    /// now. `nil` when there is no live typing, in which case no
    /// auto-conversion fires and ↩ submits.
    @Published var rawWindow: NSRange? = nil
    @Published var candidate: String? = nil
    @Published var converting: Bool = false
    @Published var errorMessage: String? = nil
    @Published var allSelected: Bool = false

    /// Per-session log of accepted (raw → committed) pairs, fed to
    /// EditWatcher after submit.
    private(set) var rawHistory: [String] = []
    var combinedRaw: String { rawHistory.joined(separator: " ") }

    private var contextImage: Data? = nil
    private var debounceTask: DispatchWorkItem?
    private var inFlightForRaw: String? = nil
    private let debounceInterval: TimeInterval = 0.5

    var isEmpty: Bool { text.isEmpty }
    /// HUD-friendly view of the raw window — empty range when nil.
    var rawRange: NSRange { rawWindow ?? NSRange(location: 0, length: 0) }

    var rawText: String {
        guard let r = rawWindow, r.length > 0,
              NSMaxRange(r) <= (text as NSString).length else { return "" }
        return (text as NSString).substring(with: r)
    }

    private var prefixText: String {
        guard let r = rawWindow else { return text }
        return (text as NSString).substring(to: r.location)
    }

    private var suffixText: String {
        guard let r = rawWindow else { return "" }
        let ns = text as NSString
        guard NSMaxRange(r) <= ns.length else { return "" }
        return ns.substring(from: NSMaxRange(r))
    }

    // MARK: - Lifecycle

    func startNew() {
        debounceTask?.cancel()
        debounceTask = nil
        inFlightForRaw = nil
        text = ""
        cursor = 0
        rawWindow = nil
        candidate = nil
        converting = false
        errorMessage = nil
        allSelected = false
        rawHistory = []
        contextImage = AppState.shared.useScreenContext
            ? Screenshotter.capturePrimary()
            : nil
    }

    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
        inFlightForRaw = nil
        text = ""
        cursor = 0
        rawWindow = nil
        candidate = nil
        converting = false
        errorMessage = nil
        allSelected = false
    }

    // MARK: - Acceptable raw chars

    private static let allowedPunct: Set<Character> = [",", ".", "?", "!", "'", "-", " "]

    static func isAcceptableRawChar(_ c: Character) -> Bool {
        if c.isLetter && c.isASCII { return true }
        if c.isNumber && c.isASCII { return true }
        if allowedPunct.contains(c) { return true }
        return false
    }

    // MARK: - Edits

    func append(_ s: String) {
        if allSelected {
            text = ""
            cursor = 0
            rawWindow = nil
            allSelected = false
            candidate = nil
        }
        let ns = text as NSString
        let safeCursor = max(0, min(cursor, ns.length))
        text = ns.replacingCharacters(in: NSRange(location: safeCursor, length: 0), with: s)
        let inserted = (s as NSString).length

        if let r = rawWindow, safeCursor >= r.location, safeCursor <= NSMaxRange(r) {
            // Cursor sits inside or at the boundary of the active raw
            // window — extend it.
            rawWindow = NSRange(location: r.location, length: r.length + inserted)
        } else {
            // Anywhere else (incl. middle of converted text or fresh start
            // after a click): begin a brand-new raw window where the
            // characters were just inserted.
            rawWindow = NSRange(location: safeCursor, length: inserted)
        }
        cursor = safeCursor + inserted
        candidate = nil
        errorMessage = nil
        scheduleConvert()
    }

    func backspace() {
        if allSelected {
            text = ""
            cursor = 0
            rawWindow = nil
            allSelected = false
            candidate = nil
            debounceTask?.cancel()
            debounceTask = nil
            return
        }
        guard cursor > 0 else { return }
        let ns = text as NSString
        let removeAt = cursor - 1
        guard removeAt < ns.length else { return }
        text = ns.replacingCharacters(in: NSRange(location: removeAt, length: 1), with: "")

        if var r = rawWindow {
            if removeAt >= r.location && removeAt < NSMaxRange(r) {
                // Deleted a char inside the raw window.
                r.length -= 1
                rawWindow = r.length > 0 ? r : nil
            } else if removeAt < r.location {
                // Deleted a char in the converted prefix — shift window
                // back to track its new position.
                r.location -= 1
                rawWindow = r
            }
        }
        cursor = removeAt
        candidate = nil
        errorMessage = nil
        if rawWindow != nil {
            scheduleConvert()
        } else {
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

    func forwardDelete() {
        if allSelected { backspace(); return }
        let ns = text as NSString
        guard cursor < ns.length else { return }
        text = ns.replacingCharacters(in: NSRange(location: cursor, length: 1), with: "")

        if var r = rawWindow {
            if cursor >= r.location && cursor < NSMaxRange(r) {
                r.length -= 1
                rawWindow = r.length > 0 ? r : nil
            } else if cursor < r.location {
                r.location -= 1
                rawWindow = r
            }
        }
        candidate = nil
        errorMessage = nil
        if rawWindow != nil {
            scheduleConvert()
        } else {
            debounceTask?.cancel()
            debounceTask = nil
        }
    }

    func moveCursorLeft()  { setCursor(cursor - 1) }
    func moveCursorRight() { setCursor(cursor + 1) }
    func moveCursorHome()  { setCursor(0) }
    func moveCursorEnd()   { setCursor((text as NSString).length) }

    /// Move the caret. If the new position falls outside the active raw
    /// window, freeze that window (the typed text stays in `text` but
    /// stops being treated as un-converted).
    func setCursor(_ idx: Int) {
        deselect()
        let clamped = max(0, min(idx, (text as NSString).length))
        cursor = clamped
        if let r = rawWindow {
            if clamped < r.location || clamped > NSMaxRange(r) {
                rawWindow = nil
                candidate = nil
                debounceTask?.cancel()
                debounceTask = nil
            }
        }
    }

    func selectAll() {
        if text.isEmpty { allSelected = false; return }
        allSelected = true
    }

    func deselect() {
        if allSelected { allSelected = false }
    }

    // MARK: - Convert

    private func scheduleConvert() {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            Task { [weak self] in await self?.convertCurrent() }
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: task)
    }

    private func convertCurrent() async {
        let snapshot = rawText
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
                prefixContext: prefixText
            )
            if rawText == snapshot {
                candidate = result
                errorMessage = nil
            }
        } catch {
            if rawText == snapshot {
                errorMessage = error.localizedDescription
            }
        }
    }

    enum ReturnIntent { case accepted, converting, submit }

    func handleReturn() -> ReturnIntent {
        if let c = candidate {
            applyCandidate(c)
            return .accepted
        }
        if !rawText.isEmpty {
            Task { [weak self] in await self?.convertNowAndApply() }
            return .converting
        }
        return .submit
    }

    private func applyCandidate(_ c: String) {
        guard let r = rawWindow else { return }
        let raw = (text as NSString).substring(with: r)
        let ns = text as NSString
        text = ns.replacingCharacters(in: r, with: c)
        rawHistory.append(raw)
        cursor = r.location + (c as NSString).length
        rawWindow = nil
        candidate = nil
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func convertNowAndApply() async {
        let snapshot = rawText
        guard !snapshot.isEmpty else { return }
        debounceTask?.cancel()
        debounceTask = nil
        converting = true
        defer { converting = false }
        do {
            let result = try await LLMClient.shared.convert(
                snapshot,
                imageData: contextImage,
                prefixContext: prefixText
            )
            if rawText == snapshot {
                applyCandidate(result)
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finalize() async -> String {
        debounceTask?.cancel()
        debounceTask = nil
        if let c = candidate {
            applyCandidate(c)
        } else if !rawText.isEmpty {
            await convertNowAndApply()
        }
        return text
    }
}
