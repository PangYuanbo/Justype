import AppKit
import Carbon.HIToolbox
import CoreGraphics

protocol EventTapDelegate: AnyObject {
    /// User pressed the trigger key once. The controller decides whether this
    /// starts a new magic session or finalizes the active one.
    func eventTapDidPressTrigger()
    /// A printable character was typed while the session was active.
    func eventTapDidReceiveCharacter(_ s: String)
    /// Backspace pressed while session is active.
    func eventTapDidPressBackspace()
    /// Enter pressed while session is active (commit candidate / force convert).
    func eventTapDidPressEnter()
    /// Escape pressed while session is active (abort).
    func eventTapDidPressEscape()
}

final class EventTap {
    weak var delegate: EventTapDelegate?

    /// Set by the controller. When true, key events are routed to the delegate
    /// and swallowed (don't reach the focused app). When false, keys pass
    /// through normally; only the trigger key is observed.
    var consumingKeys: Bool = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trigger: TriggerKey { AppState.shared.trigger }

    /// Last known engaged-state of the trigger key, so we only fire on the
    /// false→true transition (= the user *pressed* the key, as opposed to
    /// releasing it or holding it).
    private var lastTriggerEngaged: Bool = false

    func start() {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let opaqueSelf = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
                return me.handle(type: type, event: event)
            },
            userInfo: opaqueSelf
        ) else {
            NSLog("JustType: failed to create event tap. Accessibility permission required.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        consumingKeys = false
        lastTriggerEngaged = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Auto-restart tap if disabled by system (timeout / user input).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        guard AppState.shared.enabled else { return Unmanaged.passUnretained(event) }

        if type == .flagsChanged {
            if let engaged = trigger.isEngaged(event: event) {
                // Fire only on the false→true transition: that's the "press".
                if engaged && !lastTriggerEngaged {
                    DispatchQueue.main.async { [weak self] in
                        self?.delegate?.eventTapDidPressTrigger()
                    }
                }
                lastTriggerEngaged = engaged
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown && consumingKeys {
            return handleKeyDown(event: event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleKeyDown(event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))

        switch keyCode {
        case kVK_Escape:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.eventTapDidPressEscape()
            }
            return nil
        case kVK_Delete:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.eventTapDidPressBackspace()
            }
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.eventTapDidPressEnter()
            }
            return nil
        default:
            break
        }

        // Read up to 4 unicode characters from this event.
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return nil } // Modifier keys etc. — swallow while capturing.

        let str = String(utf16CodeUnits: chars, count: length)
        if isAcceptable(str) {
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.eventTapDidReceiveCharacter(str)
            }
            return nil // consume
        }
        // Unknown key while capturing — swallow to avoid leaking into focused app.
        return nil
    }

    private func isAcceptable(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        let allowedPunct: Set<Character> = [",", ".", "?", "!", "'", "-", " "]
        for ch in s {
            if ch.isLetter && ch.isASCII { continue }
            if ch.isNumber && ch.isASCII { continue }
            if allowedPunct.contains(ch) { continue }
            return false
        }
        return true
    }
}
