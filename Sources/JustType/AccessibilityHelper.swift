import AppKit
import ApplicationServices

enum AccessibilityHelper {
    static var isTrusted: Bool {
        return AXIsProcessTrusted()
    }

    /// Triggers the system permission prompt and shows guidance if not yet granted.
    @discardableResult
    static func requestTrust() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func presentGuidanceIfNeeded() {
        guard !isTrusted else { return }
        let alert = NSAlert()
        alert.messageText = L10n.axAlertTitle.t
        alert.informativeText = L10n.axAlertBody.t
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.axAlertOpen.t)
        alert.addButton(withTitle: L10n.axAlertLater.t)
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
