import AppKit
import SwiftUI
import Combine

// MARK: - View model

/// One snapshot of the magic-input HUD's display state.
struct HUDSnapshot: Equatable {
    /// The full editable buffer (committed prefix + trailing raw run).
    var text: String = ""
    /// Caret position inside `text`, in characters from the start.
    var cursor: Int = 0
    /// Trailing run of un-converted ASCII characters, used to style the
    /// raw portion differently and drive the candidate row.
    var rawRange: NSRange = NSRange(location: 0, length: 0)
    var candidate: String? = nil
    var converting: Bool = false
    var error: String? = nil
    /// True after the user releases the trigger to finalize — we briefly show
    /// the final text in a "result" style before injecting and dismissing.
    var finalizing: Bool = false
    /// The final text shown during finalizing/result phase.
    var resultText: String = ""
    /// When set, overrides the HUD with a "paste failed — kept on clipboard"
    /// banner. Cleared on dismiss.
    var clipboardFallback: ClipboardFallback? = nil
    /// True when the user has explicitly selected the entire box. The HUD
    /// renders the text with a highlight and the next typed character (or
    /// Backspace) clears everything.
    var allSelected: Bool = false

    struct ClipboardFallback: Equatable {
        var title: String
        var hint: String
    }
}

final class HUDViewModel: ObservableObject {
    @Published var snapshot: HUDSnapshot = HUDSnapshot()
    @Published var visible: Bool = false
    /// Invoked when the user clicks inside the raw text region — the
    /// payload is the character index within `snapshot.raw` where the
    /// caret should land.
    var onSetRawCursor: ((Int) -> Void)?
}

// MARK: - Controller

final class HUDController {
    private let panel: NSPanel
    private let viewModel = HUDViewModel()

    private let panelWidth: CGFloat = 720
    private let panelHeight: CGFloat = 220

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // Accept mouse events so the user can click to select-all, but the
        // panel is non-activating: clicks won't steal focus from whichever
        // app the user was typing into.
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true

        let host = NSHostingView(rootView: HUDView(viewModel: viewModel))
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = host

        self.panel = panel
    }

    // MARK: lifecycle

    func show() {
        viewModel.snapshot = HUDSnapshot()
        positionPanel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        viewModel.visible = true
    }

    func update(_ snapshot: HUDSnapshot) {
        viewModel.snapshot = snapshot
    }

    /// Set a closure invoked when the user clicks inside the raw text —
    /// the int payload is the character index where the caret should go.
    func setRawCursorHandler(_ handler: @escaping (Int) -> Void) {
        viewModel.onSetRawCursor = handler
    }

    func showResult(_ text: String) {
        var s = viewModel.snapshot
        s.finalizing = true
        s.resultText = text
        s.candidate = nil
        s.converting = false
        s.error = nil
        viewModel.snapshot = s
    }

    func showError(_ message: String) {
        var s = viewModel.snapshot
        s.error = message
        s.converting = false
        viewModel.snapshot = s
    }

    /// Show a "paste failed, content kept on clipboard" message. Useful when
    /// `TextInjector` detects that Cmd+V didn't actually land in the focused
    /// app (sandboxed app, no text field focused, etc.). Brings the panel
    /// back up if it was already dismissed.
    func showClipboardFallback(title: String, hint: String) {
        var s = HUDSnapshot()
        s.clipboardFallback = .init(title: title, hint: hint)
        viewModel.snapshot = s
        positionPanel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        viewModel.visible = true
    }

    func dismiss(after seconds: TimeInterval = 0.0) {
        let work = DispatchWorkItem { [weak self] in self?.performDismiss() }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func performDismiss() {
        viewModel.visible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
            guard let self = self else { return }
            if self.viewModel.visible == false {
                self.panel.orderOut(nil)
            }
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.midX - panelWidth / 2,
            y: visible.minY + 96,
            width: panelWidth,
            height: panelHeight
        )
        panel.setFrame(frame, display: true)
    }
}

// MARK: - SwiftUI HUD

struct HUDView: View {
    @ObservedObject var viewModel: HUDViewModel

    private var accent: Color {
        if viewModel.snapshot.clipboardFallback != nil {
            return Color(red: 1.00, green: 0.72, blue: 0.30)  // amber
        }
        if viewModel.snapshot.error != nil {
            return Color(red: 1.00, green: 0.55, blue: 0.43)
        }
        if viewModel.snapshot.finalizing {
            return Color(red: 0.34, green: 0.86, blue: 0.55)
        }
        if viewModel.snapshot.converting {
            return Color(red: 0.66, green: 0.50, blue: 1.00)
        }
        return Color(red: 0.42, green: 0.69, blue: 1.00)
    }

    var body: some View {
        ZStack {
            Color.clear
            card
                .frame(maxWidth: 660)
                .scaleEffect(viewModel.visible ? 1.0 : 0.92)
                .opacity(viewModel.visible ? 1.0 : 0.0)
                .animation(
                    viewModel.visible
                        ? .spring(response: 0.42, dampingFraction: 0.78)
                        : .easeIn(duration: 0.20),
                    value: viewModel.visible
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let fb = viewModel.snapshot.clipboardFallback {
                clipboardFallbackBanner(fb)
            } else {
                inputRow
                divider
                candidateRow
                if let err = viewModel.snapshot.error, !err.isEmpty {
                    Text(err)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.85, green: 0.30, blue: 0.20))
                        .lineLimit(2)
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(background)
        .overlay(border)
        .compositingGroup()
        .shadow(color: accent.opacity(0.30), radius: 22, x: 0, y: 10)
        .shadow(color: .black.opacity(0.28), radius: 14, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.25), value: viewModel.snapshot.candidate)
        .animation(.easeInOut(duration: 0.25), value: viewModel.snapshot.converting)
        .animation(.easeInOut(duration: 0.25), value: viewModel.snapshot.finalizing)
    }

    @ViewBuilder
    private var inputRow: some View {
        if viewModel.snapshot.finalizing {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accent)
                Text(viewModel.snapshot.resultText)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.92))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 2) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(accent)
                    .padding(.trailing, 6)
                if viewModel.snapshot.text.isEmpty {
                    Text(L10n.hudWaiting.t)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.black.opacity(0.42))
                } else if viewModel.snapshot.allSelected {
                    Text(viewModel.snapshot.text)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.black.opacity(0.92))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(accent.opacity(0.30))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(accent.opacity(0.55), lineWidth: 1)
                        )
                } else {
                    editableTextRow
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// One unified row that:
    ///   - renders the buffer with proportional styling for the
    ///     converted prefix and monospaced+underlined styling for the
    ///     trailing raw run,
    ///   - draws a blinking caret at the cursor's x-offset (computed
    ///     via CTLine for accuracy across mixed scripts),
    ///   - accepts mouse clicks anywhere on the line and reports the
    ///     hit character index back to the controller.
    private var editableTextRow: some View {
        let snap = viewModel.snapshot
        let attrString = HUDTextLayout.attributedString(
            text: snap.text,
            rawRange: snap.rawRange,
            rawUnderline: NSColor(accent.opacity(0.65))
        )
        let layout = HUDTextLayout(attributed: attrString)
        let safeCursor = max(0, min(snap.cursor, attrString.length))
        let caretX = layout.xOffset(forCharIndex: safeCursor)
        let totalWidth = ceil(layout.size.width) + 4

        return ZStack(alignment: .topLeading) {
            EditableTextLineView(layout: layout) { idx in
                viewModel.onSetRawCursor?(idx)
            }
            .frame(width: max(totalWidth, 6), height: 24, alignment: .topLeading)

            BlinkingCaret(color: accent)
                .offset(x: caretX)
        }
        .frame(minHeight: 24, idealHeight: 24, maxHeight: 24, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.black.opacity(0.10))
            .frame(height: 1)
            .opacity(viewModel.snapshot.finalizing ? 0 : 1)
    }

    @ViewBuilder
    private var candidateRow: some View {
        if viewModel.snapshot.finalizing {
            EmptyView()
        } else if viewModel.snapshot.converting {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
                Text(L10n.hudConverting.t)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.55))
                ConvertingDots(color: accent)
                Spacer(minLength: 0)
            }
        } else if let cand = viewModel.snapshot.candidate, !cand.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent.opacity(0.8))
                Text(cand)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.85))
                    .lineLimit(2)
                Spacer(minLength: 8)
                hintBadge(text: L10n.hudAcceptHint.t, color: accent)
            }
        } else if viewModel.snapshot.rawRange.length == 0 && !viewModel.snapshot.text.isEmpty {
            // Everything is converted — ↩ now submits.
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
                Text(L10n.hudReadyToSubmit.t)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.55))
                Spacer(minLength: 8)
                hintBadge(text: L10n.hudSubmitHint.t, color: accent)
            }
        } else if viewModel.snapshot.rawRange.length == 0 {
            HStack(spacing: 10) {
                Text(L10n.hudHelp.t)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.45))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 10) {
                Text(L10n.hudKeepTyping.t)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.40))
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func clipboardFallbackBanner(_ fb: HUDSnapshot.ClipboardFallback) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accent)
                Text(fb.title)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.black.opacity(0.92))
                Spacer()
            }
            Text(fb.hint)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.black.opacity(0.55))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hintBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundColor(color.opacity(0.95))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.18))
            )
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.35), lineWidth: 0.8)
            )
    }

    // MARK: background / border

    private var background: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.55))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.55)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(accent.opacity(0.10))
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.10),
                            .clear
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.55)
                    )
                )
                .blendMode(.plusLighter)
        }
        .animation(.easeInOut(duration: 0.30), value: viewModel.snapshot.converting)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color.white.opacity(0.35),
                        accent.opacity(0.30),
                        Color.white.opacity(0.55)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.0
            )
    }
}

// MARK: - Caret

private struct BlinkingCaret: View {
    let color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let visible = t.truncatingRemainder(dividingBy: 1.0) < 0.55
            RoundedRectangle(cornerRadius: 1.2)
                .fill(color.opacity(0.95))
                .frame(width: 2.5, height: 18)
                .opacity(visible ? 1 : 0)
                .shadow(color: color.opacity(0.6), radius: 4)
        }
        .frame(width: 2.5, height: 18)
        .padding(.leading, 1)
    }
}

// MARK: - Converting dots

private struct ConvertingDots: View {
    let color: Color
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    let phase = (t * 1.6 - Double(i) * 0.22)
                        .truncatingRemainder(dividingBy: 1.4) / 1.4
                    let v = max(0.0, sin(phase * .pi))
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                        .opacity(0.30 + v * 0.70)
                        .scaleEffect(0.7 + v * 0.55)
                        .shadow(color: color.opacity(0.8), radius: 3 * v)
                }
            }
        }
        .frame(width: 26, height: 16)
    }
}

// MARK: - HUD text layout

/// Computes character offsets and hit-tests for the magic box's
/// editable line. Built around a single `NSAttributedString` + `CTLine`
/// so it correctly handles mixed scripts (Chinese committed prefix +
/// monospaced raw suffix) without us approximating widths.
struct HUDTextLayout {
    let attributed: NSAttributedString
    let line: CTLine
    let size: CGSize

    init(attributed: NSAttributedString) {
        self.attributed = attributed
        let line = CTLineCreateWithAttributedString(attributed)
        self.line = line
        let typo = CTLineGetTypographicBounds(line, nil, nil, nil)
        let bounds = CTLineGetBoundsWithOptions(line, CTLineBoundsOptions.useGlyphPathBounds)
        self.size = CGSize(width: max(CGFloat(typo), bounds.width), height: bounds.height)
    }

    /// X offset (in points, from the start of the line) to draw a caret
    /// for `index` characters into the buffer.
    func xOffset(forCharIndex index: Int) -> CGFloat {
        let clamped = max(0, min(index, attributed.length))
        return CTLineGetOffsetForStringIndex(line, clamped, nil)
    }

    /// Inverse of `xOffset(forCharIndex:)`. Used to convert a click
    /// inside the line into a buffer character index.
    func charIndex(forX x: CGFloat) -> Int {
        let raw = CTLineGetStringIndexForPosition(line, CGPoint(x: x, y: 0))
        return max(0, min(Int(raw), attributed.length))
    }

    /// Build the styled `NSAttributedString` shown in the magic box —
    /// the converted prefix in proportional semibold, the trailing raw
    /// run in monospaced + underlined.
    static func attributedString(text: String, rawRange: NSRange, rawUnderline: NSColor) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: text)
        let full = NSRange(location: 0, length: (text as NSString).length)
        attr.addAttributes([
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor(white: 0, alpha: 0.92)
        ], range: full)
        if rawRange.length > 0,
           rawRange.location >= 0,
           NSMaxRange(rawRange) <= attr.length {
            attr.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .medium),
                .foregroundColor: NSColor(white: 0, alpha: 0.55),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: rawUnderline
            ], range: rawRange)
        }
        return attr
    }
}

// MARK: - Editable line view

/// Renders a single attributed line and forwards mouse-down clicks +
/// the I-beam cursor. Backed by an `NSView` (not SwiftUI) because the
/// magic box lives in a non-activating `NSPanel`; SwiftUI gestures and
/// the `.cursor()` modifier are unreliable there, but `acceptsFirstMouse`
/// + `addCursorRect` always work.
struct EditableTextLineView: NSViewRepresentable {
    let layout: HUDTextLayout
    let onClick: (Int) -> Void

    func makeNSView(context: Context) -> EditableTextLineNSView {
        let v = EditableTextLineNSView()
        v.layout = layout
        v.onClick = onClick
        return v
    }
    func updateNSView(_ v: EditableTextLineNSView, context: Context) {
        v.layout = layout
        v.onClick = onClick
        v.needsDisplay = true
        v.window?.invalidateCursorRects(for: v)
    }
}

final class EditableTextLineNSView: NSView {
    var layout: HUDTextLayout? { didSet { needsDisplay = true } }
    var onClick: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
    }

    override func mouseDown(with event: NSEvent) {
        guard let layout = layout else { return }
        let local = convert(event.locationInWindow, from: nil)
        let idx = layout.charIndex(forX: max(0, local.x))
        onClick?(idx)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let layout = layout, let ctx = NSGraphicsContext.current?.cgContext else { return }
        // CoreText draws with origin at the baseline; place it about 4pt
        // above the bottom of the view so the line is roughly centered
        // within our 24pt-tall row.
        let baselineY: CGFloat = 5
        ctx.textPosition = CGPoint(x: 0, y: baselineY)
        CTLineDraw(layout.line, ctx)
    }
}
