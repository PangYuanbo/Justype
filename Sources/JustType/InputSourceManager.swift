import Foundation
import Carbon

enum InputSourceManager {
    private static let abcID = "com.apple.keylayout.ABC"

    /// Returns the current keyboard input source, retained.
    static func currentSource() -> TISInputSource? {
        return TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    static func sourceID(_ source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    static func isCJK(_ source: TISInputSource) -> Bool {
        guard let id = sourceID(source) else { return false }
        let lower = id.lowercased()
        let cjkHints = [
            "pinyin", "wubi", "shuangpin", "zhuyin", "cangjie", "stroke",
            "tcim", "scim", "chinese", "japanese", "kotoeri", "atok",
            "korean", "hangul", "2set", "3set", "kana", "romaji",
            "vietnamese"
        ]
        return cjkHints.contains(where: { lower.contains($0) })
    }

    /// Switch to ABC. Returns true on success.
    @discardableResult
    static func switchToABC() -> Bool {
        return selectSource(withID: abcID)
    }

    @discardableResult
    static func selectSource(withID targetID: String) -> Bool {
        let filter: [CFString: Any] = [kTISPropertyInputSourceID: targetID as CFString]
        guard let listRaw = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return false
        }
        let list = listRaw as! [TISInputSource]
        guard let target = list.first else { return false }
        let status = TISSelectInputSource(target)
        return status == noErr
    }
}
