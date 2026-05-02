import AppKit
import Carbon.HIToolbox

enum TriggerKey: String, CaseIterable, Codable {
    case fn
    case rightOption
    case capsLock

    var displayName: String {
        switch self {
        case .fn:          return L10n.triggerFn.t
        case .rightOption: return L10n.triggerRightOption.t
        case .capsLock:    return L10n.triggerCapsLock.t
        }
    }

    /// Detect whether the trigger is currently engaged based on a flagsChanged
    /// event. Returns nil if the event isn't for this trigger key — that way
    /// pressing Shift, Caps Lock, etc. while the trigger is held won't be
    /// misread as the trigger toggling.
    func isEngaged(event: CGEvent) -> Bool? {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch self {
        case .fn:
            // Only react when the Fn key itself (keyCode 63 / kVK_Function)
            // generated this flagsChanged event.
            guard keyCode == kVK_Function else { return nil }
            return flags.contains(.maskSecondaryFn)
        case .rightOption:
            guard keyCode == kVK_RightOption else { return nil }
            return flags.contains(.maskAlternate)
        case .capsLock:
            guard keyCode == kVK_CapsLock else { return nil }
            return flags.contains(.maskAlphaShift)
        }
    }
}
