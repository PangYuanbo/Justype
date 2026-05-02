import AppKit
import SwiftUI
import Combine

// MARK: - View model

/// One snapshot of the magic-input HUD's display state.
struct HUDSnapshot: Equatable {
    var committed: String = ""
    var raw: String = ""
    var candidate: String? = nil
    var converting: Bool = false
    var error: String? = nil
    /// True after the user releases the trigger to finalize — we briefly show
    /// the final text in a "result" style before injecting and dismissing.
    var finalizing: Bool = false
    /// The final text shown during finalizing/result phase.
    var resultText: String = ""
}

final class HUDViewModel: ObservableObject {
    @Published var snapshot: HUDSnapshot = HUDSnapshot()
    @Published var visible: Bool = false
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
        panel.ignoresMouseEvents = true

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
                if viewModel.snapshot.committed.isEmpty && viewModel.snapshot.raw.isEmpty {
                    Text("等待输入…")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.black.opacity(0.42))
                } else {
                    if !viewModel.snapshot.committed.isEmpty {
                        Text(viewModel.snapshot.committed)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.black.opacity(0.92))
                    }
                    if !viewModel.snapshot.raw.isEmpty {
                        Text(viewModel.snapshot.raw)
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundColor(.black.opacity(0.55))
                            .underline(true, color: accent.opacity(0.65))
                    }
                    BlinkingCaret(color: accent)
                        .padding(.leading, 2)
                }
                Spacer(minLength: 0)
            }
        }
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
                Text("正在转换…")
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
                hintBadge(text: "↩ 接受", color: accent)
            }
        } else if viewModel.snapshot.raw.isEmpty {
            HStack(spacing: 10) {
                Text("打字 → 停顿 → 候选会出现在这里。再按一次触发键完成输入。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.45))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        } else {
            HStack(spacing: 10) {
                Text("继续输入…")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.40))
                Spacer(minLength: 0)
            }
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
