import Cocoa
import InputMethodKit

/// IMK controller for JustType. Buffers raw keystrokes as marked
/// (composing) text under the cursor; ↩ converts via the LLM and
/// inserts the result. `Esc` cancels. Backspace edits the buffer.
@objc(JustTypeInputController)
final class JustTypeInputController: IMKInputController {

    /// Current composition buffer — the un-converted raw letters the user
    /// is typing. Shown to the focused app as marked (underlined) text.
    private var buffer: String = ""
    /// True while an LLM round-trip is in flight; we lock the buffer to
    /// prevent racing edits.
    private var converting: Bool = false

    // MARK: - Event entry points

    override func inputText(_ string: String!, client sender: Any!) -> Bool {
        guard !converting, let s = string, !s.isEmpty else { return false }

        // If any character isn't acceptable for raw fuzzy input, flush the
        // current buffer (commit converted) and let the host handle the
        // event normally.
        for ch in s where !Self.isAcceptable(ch) {
            flushAndCommit()
            return false
        }

        buffer += s
        renderMarked()
        return true
    }

    override func didCommand(by aSelector: Selector!, client sender: Any!) -> Bool {
        guard !converting else { return true }
        switch aSelector {
        case #selector(NSResponder.deleteBackward(_:)):
            if !buffer.isEmpty {
                buffer.removeLast()
                renderMarked()
                return true
            }
            return false
        case #selector(NSResponder.insertNewline(_:)):
            convertAndCommit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            buffer = ""
            renderMarked()
            return true
        default:
            // For arrow keys, etc. — flush any pending composition first,
            // then let the host handle the event itself.
            if !buffer.isEmpty { flushAndCommit() }
            return false
        }
    }

    override func deactivateServer(_ sender: Any!) {
        // Switching input method or losing focus — commit whatever's
        // currently in the buffer instead of losing it silently.
        flushAndCommit()
        super.deactivateServer(sender)
    }

    // MARK: - Composition rendering

    private func renderMarked() {
        guard let cli = client() as? IMKTextInput else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.labelColor
        ]
        let attributed = NSAttributedString(string: buffer, attributes: attrs)
        cli.setMarkedText(
            attributed,
            selectionRange: NSRange(location: buffer.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    private func clearMarked() {
        guard let cli = client() as? IMKTextInput else { return }
        cli.setMarkedText(
            NSAttributedString(string: ""),
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    // MARK: - LLM round-trip

    /// Force-convert any pending buffer immediately. Used on focus loss /
    /// unrecognized keys.
    private func flushAndCommit() {
        guard !buffer.isEmpty else { return }
        convertAndCommit()
    }

    private func convertAndCommit() {
        let snapshot = buffer
        guard !snapshot.isEmpty else { return }
        guard let cli = client() as? IMKTextInput else { return }

        // Optimistically render a "…" to signal we're working.
        let pending = NSAttributedString(
            string: snapshot + " …",
            attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        cli.setMarkedText(
            pending,
            selectionRange: NSRange(location: snapshot.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        converting = true
        Task { [weak self] in
            do {
                let result = try await IMELLMClient.convert(snapshot)
                await MainActor.run { [weak self] in
                    self?.commit(text: result)
                }
            } catch {
                NSLog("JustType IME: LLM error \(error.localizedDescription)")
                // On error, commit the raw buffer so the user doesn't lose
                // what they typed.
                await MainActor.run { [weak self] in
                    self?.commit(text: snapshot)
                }
            }
        }
    }

    private func commit(text: String) {
        guard let cli = client() as? IMKTextInput else { return }
        clearMarked()
        cli.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        buffer = ""
        converting = false
    }

    // MARK: - Helpers

    private static func isAcceptable(_ c: Character) -> Bool {
        if c.isLetter && c.isASCII { return true }
        if c.isNumber && c.isASCII { return true }
        let allowed: Set<Character> = [",", ".", "?", "!", "'", "-", " "]
        return allowed.contains(c)
    }
}
