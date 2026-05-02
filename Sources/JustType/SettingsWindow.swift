import AppKit
import SwiftUI
import Combine

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private convenience init() {
        let view = SettingsView()
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "JustType 设置"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 360))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var testStatus: String = ""
    @State private var testing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LLM 配置")
                .font(.headline)

            Form {
                LabeledField(label: "Base URL") {
                    TextField("https://openrouter.ai/api/v1", text: $state.baseURL)
                        .textFieldStyle(.roundedBorder)
                }
                LabeledField(label: "API Key") {
                    HStack(spacing: 8) {
                        SecureField("sk-or-…", text: $state.apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("清空") { state.apiKey = "" }
                    }
                }
                LabeledField(label: "Model") {
                    TextField("google/gemini-2.5-flash", text: $state.model)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            HStack {
                Button(testing ? "测试中…" : "Test") {
                    runTest()
                }
                .disabled(testing)

                Button("Save") {
                    // @Published already persists on change; show confirmation.
                    testStatus = "已保存。"
                }

                Spacer()
                if !testStatus.isEmpty {
                    Text(testStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 480, height: 360, alignment: .topLeading)
    }

    private func runTest() {
        testing = true
        testStatus = "测试中…"
        Task {
            do {
                let result = try await LLMClient.shared.convert("ni hao")
                await MainActor.run {
                    testStatus = "✅ 测试成功：\(result)"
                    testing = false
                }
            } catch {
                await MainActor.run {
                    testStatus = "❌ \(error.localizedDescription)"
                    testing = false
                }
            }
        }
    }
}

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 80, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
        }
    }
}
