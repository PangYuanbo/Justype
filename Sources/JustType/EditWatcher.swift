import AppKit
import ApplicationServices

/// Watches the focused text field for a short time after JustType pastes,
/// and records any post-paste edit as a `Correction` — the model will then
/// see those corrections in future system prompts as user-specific examples.
///
/// Detection is best-effort. Apps that don't expose AXValue for their text
/// fields (some Electron apps, some web fields) silently skip recording.
final class EditWatcher {
    static let shared = EditWatcher()

    /// How long after a paste we wait before sampling the field again. If the
    /// user pastes again sooner, we sample immediately and reset.
    private let delay: TimeInterval = 8.0

    private var pending: Pending?
    private var timer: DispatchSourceTimer?

    private struct Pending {
        let raw: String
        let injected: String
        let baseline: String
        let injectedRange: Range<String.Index>
        let element: AXUIElement
    }

    /// Called right after `TextInjector.inject(...)` completes.
    func observe(raw: String, injected: String) {
        // Finalize any prior pending observation now — if the user is starting
        // another session, they're done editing the previous one.
        flushNow()

        // Allow a moment for the paste to settle in the focused app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.startObservation(raw: raw, injected: injected)
        }
    }

    private func startObservation(raw: String, injected: String) {
        guard let (element, baseline) = readFocusedTextElement() else { return }
        // Find where our pasted text lives. `.backwards` because if the user
        // already had text containing similar substrings, the most recent
        // paste is at the tail.
        guard let range = baseline.range(of: injected, options: .backwards) else { return }

        pending = Pending(
            raw: raw,
            injected: injected,
            baseline: baseline,
            injectedRange: range,
            element: element
        )
        scheduleCheck(after: delay)
    }

    /// If a pending observation exists, sample now and clear.
    private func flushNow() {
        timer?.cancel()
        timer = nil
        guard let p = pending else { return }
        pending = nil
        runDiff(against: p)
    }

    private func scheduleCheck(after seconds: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + seconds)
        t.setEventHandler { [weak self] in
            guard let self = self, let p = self.pending else { return }
            self.pending = nil
            self.runDiff(against: p)
        }
        t.resume()
        timer = t
    }

    private func runDiff(against p: Pending) {
        guard let current = readValue(of: p.element) else { return }
        // Use the prefix/suffix from baseline as anchors and look at what's
        // between them in `current`. If the anchors moved (user inserted
        // before/after our paste), bail rather than misattributing.
        let prefix = String(p.baseline[..<p.injectedRange.lowerBound])
        let suffix = String(p.baseline[p.injectedRange.upperBound...])
        guard current.hasPrefix(prefix) else { return }
        let afterPrefix = String(current.dropFirst(prefix.count))
        let corrected: String
        if suffix.isEmpty {
            corrected = afterPrefix
        } else if let suffixRange = afterPrefix.range(of: suffix, options: .backwards) {
            corrected = String(afterPrefix[..<suffixRange.lowerBound])
        } else {
            return
        }
        guard !corrected.isEmpty, corrected != p.injected else { return }

        // Some sanity caps — if the user nuked our paste entirely or replaced
        // it with something massively different, it's probably not a useful
        // signal (they may have just wanted something completely else).
        if corrected.count < max(2, p.injected.count / 4) { return }
        if corrected.count > p.injected.count * 4 { return }

        CorrectionStore.shared.add(
            raw: p.raw,
            badOutput: p.injected,
            goodOutput: corrected
        )
    }

    // MARK: - AX helpers

    private func readFocusedTextElement() -> (AXUIElement, String)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success else { return nil }
        // The runtime type is AXUIElement; we have to bridge through CFTypeRef.
        guard CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement
        guard let value = readValue(of: element) else { return nil }
        return (element, value)
    }

    private func readValue(of element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success else {
            return nil
        }
        return valueRef as? String
    }
}
