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
        window.setContentSize(NSSize(width: 540, height: 480))
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

// MARK: - Settings view

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared

    @State private var models: [ModelCatalog.Model] = []
    @State private var loading: Bool = false
    @State private var loadError: String? = nil
    @State private var search: String = ""
    @State private var visionOnly: Bool = false

    @State private var testStatus: String = ""
    @State private var testing: Bool = false

    /// Debounce auto-fetch on key/baseURL change.
    @State private var refreshTask: Task<Void, Never>? = nil

    var filteredModels: [ModelCatalog.Model] {
        let s = search.trimmingCharacters(in: .whitespaces).lowercased()
        return models.filter { m in
            (visionOnly ? m.supportsImage : true) &&
            (s.isEmpty || m.id.lowercased().contains(s) || (m.name?.lowercased().contains(s) ?? false))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Endpoint section
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("Endpoint")

                LabeledField("Base URL") {
                    TextField("https://openrouter.ai/api/v1", text: $state.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: state.baseURL) { _, _ in scheduleRefresh() }
                }
                LabeledField("API Key") {
                    HStack(spacing: 8) {
                        SecureField("sk-or-…", text: $state.apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: state.apiKey) { _, _ in scheduleRefresh() }
                        Button("清空") { state.apiKey = "" }
                            .buttonStyle(.bordered)
                    }
                }
                Text("免费注册 OpenRouter 拿 key：openrouter.ai/keys")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Model picker
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    sectionTitle("Model")
                    Spacer()
                    if loading {
                        ProgressView().controlSize(.small)
                        Text("加载中…").font(.caption).foregroundColor(.secondary)
                    } else {
                        Text("可用：\(models.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button {
                            Task { await fetchModels() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(state.apiKey.isEmpty)
                        .help("刷新模型列表")
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索模型…", text: $search)
                        .textFieldStyle(.plain)
                    Toggle("仅看支持图片", isOn: $visionOnly)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.3))
                )

                modelListView

                LabeledField("当前") {
                    HStack(spacing: 6) {
                        Text(state.model.isEmpty ? "（未选择）" : state.model)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                }

                if let err = loadError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(3)
                }
            }

            Divider()

            // Test row
            HStack {
                Button(testing ? "测试中…" : "测试当前配置") { runTest() }
                    .disabled(testing || state.apiKey.isEmpty || state.model.isEmpty)
                Spacer()
                if !testStatus.isEmpty {
                    Text(testStatus)
                        .font(.caption)
                        .foregroundColor(testStatus.hasPrefix("✅") ? .green : .red)
                        .lineLimit(2)
                }
            }
        }
        .padding(20)
        .frame(width: 540, height: 480, alignment: .topLeading)
        .onAppear {
            if !state.apiKey.isEmpty && models.isEmpty {
                Task { await fetchModels() }
            }
        }
    }

    // MARK: components

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.headline)
    }

    @ViewBuilder
    private var modelListView: some View {
        ScrollViewReader { proxy in
            List(filteredModels, id: \.id, selection: Binding(
                get: { state.model },
                set: { newValue in
                    if let v = newValue { state.model = v }
                }
            )) { model in
                modelRow(model)
                    .id(model.id)
                    .tag(model.id)
            }
            .listStyle(.bordered)
            .frame(minHeight: 180, maxHeight: 220)
            .onAppear {
                if !state.model.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo(state.model, anchor: .center)
                    }
                }
            }
        }
    }

    private func modelRow(_ m: ModelCatalog.Model) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.id)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                if let name = m.name, name != m.id {
                    Text(name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if m.supportsImage {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .help("支持图片输入")
            }
            if let ctx = m.contextLength {
                Text(formatContext(ctx))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.model = m.id }
    }

    private func formatContext(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000     { return "\(n / 1_000)K" }
        return "\(n)"
    }

    // MARK: - Actions

    private func scheduleRefresh() {
        refreshTask?.cancel()
        let task = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s debounce
            if Task.isCancelled { return }
            await fetchModels()
        }
        refreshTask = task
    }

    @MainActor
    private func fetchModels() async {
        guard !state.apiKey.isEmpty else {
            models = []
            loadError = "请先填写 API Key"
            return
        }
        loading = true
        loadError = nil
        defer { loading = false }
        do {
            let result = try await ModelCatalog.shared.fetch(
                baseURL: state.baseURL,
                apiKey: state.apiKey
            )
            self.models = result
            // Auto-pick a default if current model isn't in the list.
            if !state.model.isEmpty, !result.contains(where: { $0.id == state.model }) {
                // Keep user's typed model; just don't highlight in list.
            } else if state.model.isEmpty, let first = result.first(where: { $0.supportsImage }) ?? result.first {
                state.model = first.id
            }
        } catch {
            models = []
            loadError = error.localizedDescription
        }
    }

    private func runTest() {
        testing = true
        testStatus = "测试中…"
        Task {
            do {
                let result = try await LLMClient.shared.convert("ni hao")
                await MainActor.run {
                    testStatus = "✅ \(result)"
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

// MARK: - LabeledField

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .frame(width: 80, alignment: .trailing)
                .foregroundColor(.secondary)
            content()
        }
    }
}
