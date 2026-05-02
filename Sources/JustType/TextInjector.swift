import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum InjectionResult {
    /// We confirmed (via AX) that our text landed in the focused field.
    case verified
    /// We couldn't read the focused field (AX unsupported in this app, etc.)
    /// — assume the paste worked. The clipboard is restored to its previous
    /// contents.
    case unverifiable
    /// We confirmed our text did NOT land. The converted text has been left
    /// in the clipboard so the user can paste it manually.
    case failedKeptInClipboard
}

enum TextInjector {
    /// Paste `text` into the currently focused input field via Cmd+V, then
    /// verify (best-effort) whether it landed. Calls `completion` on the
    /// main queue with the outcome.
    static func inject(_ text: String, completion: ((InjectionResult) -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?(.unverifiable)
            return
        }

        let pasteboard = NSPasteboard.general
        // Snapshot pasteboard items so we can restore on success.
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

        // Snapshot focused element so verify can check the same one even if
        // focus drifts after paste.
        let focusedSnapshot = readFocusedElement()
        let baselineValue = focusedSnapshot.flatMap { readValue(of: $0) }

        // Replace pasteboard with our text.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Allow input-source switch / pasteboard write to settle.
        let initialDelay: useconds_t = didSwitchInputSource ? 60_000 : 20_000
        usleep(initialDelay)

        postCmdV()

        // Verify after a short delay. We can't reliably tell synchronously
        // whether Cmd+V landed, so wait a beat and check the AX value.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let result = self.verifyPaste(
                injected: text,
                element: focusedSnapshot,
                baseline: baselineValue
            )

            // Restore input source on a background queue.
            DispatchQueue.global(qos: .userInitiated).async {
                if didSwitchInputSource, let src = originalSource,
                   let id = InputSourceManager.sourceID(src) {
                    _ = InputSourceManager.selectSource(withID: id)
                }
                DispatchQueue.main.async {
                    switch result {
                    case .verified, .unverifiable:
                        // Paste landed (or we can't tell) — give back the
                        // user's clipboard.
                        pasteboard.clearContents()
                        if !savedItems.isEmpty {
                            pasteboard.writeObjects(savedItems)
                        }
                    case .failedKeptInClipboard:
                        // Leave our text on the clipboard so the user can
                        // paste it manually.
                        break
                    }
                    completion?(result)
                }
            }
        }
    }

    private static func verifyPaste(
        injected: String,
        element: AXUIElement?,
        baseline: String?
    ) -> InjectionResult {
        guard let element = element else { return .unverifiable }
        guard let current = readValue(of: element) else { return .unverifiable }
        // If `injected` is now somewhere in the field's value (and wasn't
        // already in baseline at the same density), call it verified.
        let countInBaseline = baseline.map { occurrences(of: injected, in: $0) } ?? 0
        let countInCurrent  = occurrences(of: injected, in: current)
        if countInCurrent > countInBaseline {
            return .verified
        }
        // Some apps replace the field value entirely on paste. As a
        // safety net, if the field's content has clearly grown, treat
        // that as a likely success.
        if let baseline = baseline, current.count > baseline.count + injected.count / 2 {
            return .verified
        }
        return .failedKeptInClipboard
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var idx = haystack.startIndex
        while let r = haystack.range(of: needle, range: idx..<haystack.endIndex) {
            count += 1
            idx = r.upperBound
        }
        return count
    }

    // MARK: - AX helpers

    private static func readFocusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success,
        let focused = focusedRef,
        CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return (focused as! AXUIElement)
    }

    private static func readValue(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
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
