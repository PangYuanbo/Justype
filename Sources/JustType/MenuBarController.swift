import AppKit
import Combine

final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private var cancellables = Set<AnyCancellable>()

    var onToggleEnabled: ((Bool) -> Void)?
    var onTriggerChanged: ((TriggerKey) -> Void)?

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureButton()
        rebuild()
        AppState.shared.$enabled
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        AppState.shared.$trigger
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        AppState.shared.$useScreenContext
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        HistoryStore.shared.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
    }

    private func configureButton() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "keyboard.badge.ellipsis", accessibilityDescription: "JustType")
            button.image?.isTemplate = true
            button.toolTip = "JustType"
        }
    }

    private func rebuild() {
        let menu = NSMenu()
        menu.delegate = self

        // Enable toggle
        let toggleTitle = AppState.shared.enabled ? "停用 模糊输入" : "启用 模糊输入"
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Trigger submenu
        let triggerItem = NSMenuItem(title: "触发键", action: nil, keyEquivalent: "")
        let triggerMenu = NSMenu()
        for key in TriggerKey.allCases {
            let mi = NSMenuItem(title: key.displayName, action: #selector(setTrigger(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = key.rawValue
            mi.state = (AppState.shared.trigger == key) ? .on : .off
            triggerMenu.addItem(mi)
        }
        triggerItem.submenu = triggerMenu
        menu.addItem(triggerItem)

        // Screen context toggle
        let sc = NSMenuItem(title: "使用屏幕截图作为上下文", action: #selector(toggleScreenContext), keyEquivalent: "")
        sc.target = self
        sc.state = AppState.shared.useScreenContext ? .on : .off
        menu.addItem(sc)

        // LLM settings
        let settings = NSMenuItem(title: "LLM 设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        // History
        let historyItem = NSMenuItem(title: "历史记录", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        let entries = HistoryStore.shared.entries
        if entries.isEmpty {
            let empty = NSMenuItem(title: "（暂无）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
        } else {
            for e in entries {
                let title = "\(truncate(e.input, 24)) → \(truncate(e.output, 24))"
                let mi = NSMenuItem(title: title, action: #selector(copyHistory(_:)), keyEquivalent: "")
                mi.target = self
                mi.toolTip = "\(e.input)\n→ \(e.output)"
                mi.representedObject = e.output
                historyMenu.addItem(mi)
            }
            historyMenu.addItem(.separator())
            let clear = NSMenuItem(title: "清空历史", action: #selector(clearHistory), keyEquivalent: "")
            clear.target = self
            historyMenu.addItem(clear)
        }
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 JustType", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func truncate(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n)) + "…"
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        AppState.shared.enabled.toggle()
        onToggleEnabled?(AppState.shared.enabled)
    }

    @objc private func setTrigger(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let key = TriggerKey(rawValue: raw) else { return }
        AppState.shared.trigger = key
        onTriggerChanged?(key)
    }

    @objc private func toggleScreenContext() {
        AppState.shared.useScreenContext.toggle()
        if AppState.shared.useScreenContext {
            Screenshotter.requestPermissionIfNeeded()
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func copyHistory(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    @objc private func clearHistory() {
        HistoryStore.shared.clear()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
