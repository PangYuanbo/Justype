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
        AppState.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        HistoryStore.shared.$entries
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
        CorrectionStore.shared.$entries
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
        let toggleTitle = AppState.shared.enabled ? L10n.menuDisableFuzzy.t : L10n.menuEnableFuzzy.t
        let toggle = NSMenuItem(title: toggleTitle, action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        menu.addItem(.separator())

        // Trigger submenu
        let triggerItem = NSMenuItem(title: L10n.menuTriggerKey.t, action: nil, keyEquivalent: "")
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

        // Language submenu
        let langItem = NSMenuItem(title: L10n.menuLanguage.t, action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in Language.allCases {
            let mi = NSMenuItem(title: lang.displayName, action: #selector(setLanguage(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = lang.rawValue
            mi.state = (AppState.shared.language == lang) ? .on : .off
            langMenu.addItem(mi)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // Screen context toggle
        let sc = NSMenuItem(title: L10n.menuUseScreenContext.t, action: #selector(toggleScreenContext), keyEquivalent: "")
        sc.target = self
        sc.state = AppState.shared.useScreenContext ? .on : .off
        menu.addItem(sc)

        // LLM settings
        let settings = NSMenuItem(title: L10n.menuLLMSettings.t, action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        // History
        let historyItem = NSMenuItem(title: L10n.menuHistory.t, action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        let entries = HistoryStore.shared.entries
        if entries.isEmpty {
            let empty = NSMenuItem(title: L10n.menuHistoryEmpty.t, action: nil, keyEquivalent: "")
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
            let clear = NSMenuItem(title: L10n.menuClearHistory.t, action: #selector(clearHistory), keyEquivalent: "")
            clear.target = self
            historyMenu.addItem(clear)
        }
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        // Corrections submenu — shows the learned corrections that get
        // appended to future prompts, with a "Clear" option.
        let correctionItem = NSMenuItem(title: L10n.menuCorrections.t, action: nil, keyEquivalent: "")
        let correctionMenu = NSMenu()
        let correctionEntries = CorrectionStore.shared.entries
        if correctionEntries.isEmpty {
            let empty = NSMenuItem(title: L10n.menuHistoryEmpty.t, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            correctionMenu.addItem(empty)
        } else {
            let count = NSMenuItem(
                title: "\(L10n.menuCorrectionsCount.t): \(correctionEntries.count)",
                action: nil,
                keyEquivalent: ""
            )
            count.isEnabled = false
            correctionMenu.addItem(count)
            correctionMenu.addItem(.separator())
            for c in correctionEntries.suffix(20) {
                let title = "\(truncate(c.badOutput, 20)) → \(truncate(c.goodOutput, 20))"
                let mi = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                mi.isEnabled = false
                mi.toolTip = "raw: \(c.raw)\nbad:  \(c.badOutput)\ngood: \(c.goodOutput)"
                correctionMenu.addItem(mi)
            }
            correctionMenu.addItem(.separator())
            let clear = NSMenuItem(title: L10n.menuClearCorrections.t, action: #selector(clearCorrections), keyEquivalent: "")
            clear.target = self
            correctionMenu.addItem(clear)
        }
        correctionItem.submenu = correctionMenu
        menu.addItem(correctionItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: L10n.menuQuit.t, action: #selector(quit), keyEquivalent: "q")
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

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = Language(rawValue: raw) else { return }
        AppState.shared.language = lang
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

    @objc private func clearCorrections() {
        CorrectionStore.shared.clear()
        rebuild()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
