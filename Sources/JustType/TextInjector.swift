import AppKit
import Carbon.HIToolbox

enum TextInjector {
    /// Paste `text` into the currently focused input field via Cmd+V.
    /// Temporarily switches to ABC if a CJK input method is active, then restores.
    /// Saves and restores the pasteboard.
    static func inject(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        // Snapshot pasteboard items.
        let savedItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []

        // Snapshot input source.
        let originalSource = InputSourceManager.currentSource()
        var didSwitchInputSource = false
        if let src = originalSource, InputSourceManager.isCJK(src) {
            didSwitchInputSource = InputSourceManager.switchToABC()
        }

        // Replace pasteboard with our text.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Allow input-source switch / pasteboard write to settle.
        let initialDelay: useconds_t = didSwitchInputSource ? 60_000 : 20_000
        usleep(initialDelay)

        postCmdV()

        // Restore on background queue so we don't block main.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.18) {
            // Restore input source.
            if didSwitchInputSource, let src = originalSource,
               let id = InputSourceManager.sourceID(src) {
                _ = InputSourceManager.selectSource(withID: id)
            }
            // Restore pasteboard.
            DispatchQueue.main.async {
                pasteboard.clearContents()
                if !savedItems.isEmpty {
                    pasteboard.writeObjects(savedItems)
                }
            }
        }
    }

    private static func postCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard
            let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true),
            let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        let loc: CGEventTapLocation = .cgAnnotatedSessionEventTap
        down.post(tap: loc)
        up.post(tap: loc)
    }
}
