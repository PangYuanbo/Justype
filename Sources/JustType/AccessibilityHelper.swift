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
        alert.messageText = "需要「辅助功能」权限"
        alert.informativeText = """
        JustType 需要「辅助功能 (Accessibility)」权限来监听触发键并捕获按键。

        请到 系统设置 → 隐私与安全性 → 辅助功能,把 JustType 加入并打开开关,然后重新启动 App。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "稍后")
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
