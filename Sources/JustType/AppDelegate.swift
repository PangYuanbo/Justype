import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController!
    private var eventTap: EventTap!
    private var hud: HUDController!
    private var session: MagicSession!
    private var sessionCancellables = Set<AnyCancellable>()

    /// True between the first trigger press and the second one — the user is
    /// composing inside the magic box.
    private var sessionActive: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install a minimal main menu so Cmd+C/V/X/A/Z work in our text fields.
        // Accessory apps (LSUIElement) don't get a default menu bar, which means
        // the standard editing keybindings have nowhere to dispatch.
        installMainMenu()

        hud = HUDController()
        session = MagicSession()
        eventTap = EventTap()
        eventTap.delegate = self
        menuBar = MenuBarController()

        // Mirror MagicSession state into the HUD.
        Publishers.CombineLatest4(
            session.$committed,
            session.$raw,
            Publishers.CombineLatest3(
                session.$candidate,
                session.$converting,
                session.$errorMessage
            ).map { ($0, $1, $2) }.eraseToAnyPublisher(),
            session.$candidate // dummy second to satisfy CombineLatest4
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] committed, raw, triple, _ in
            guard let self = self, self.sessionActive else { return }
            let (cand, conv, err) = triple
            var snap = HUDSnapshot()
            snap.committed = committed
            snap.raw = raw
            snap.candidate = cand
            snap.converting = conv
            snap.error = err
            self.hud.update(snap)
        }
        .store(in: &sessionCancellables)

        menuBar.onToggleEnabled = { [weak self] enabled in
            guard let self = self else { return }
            if enabled { self.eventTap.start() } else { self.eventTap.stop() }
        }
        menuBar.onTriggerChanged = { [weak self] _ in
            self?.eventTap.stop()
            if AppState.shared.enabled { self?.eventTap.start() }
        }

        // Prompt for accessibility on first run.
        AccessibilityHelper.requestTrust()
        if !AccessibilityHelper.isTrusted {
            AccessibilityHelper.presentGuidanceIfNeeded()
        }
        // Trigger Screen Recording permission prompt if user wants screen context.
        if AppState.shared.useScreenContext {
            Screenshotter.requestPermissionIfNeeded()
        }

        if AppState.shared.enabled {
            eventTap.start()
        }

        // Rebuild the main menu when the user switches language so Edit /
        // Window / About are also translated immediately.
        AppState.shared.$language
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.installMainMenu() }
            .store(in: &sessionCancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap?.stop()
    }

    private func installMainMenu() {
        let main = NSMenu()

        // Application menu (first item, shown as the app name).
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: L10n.mainAbout.t,
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        ))
        appMenu.addItem(NSMenuItem.separator())
        let hide = NSMenuItem(
            title: L10n.mainHide.t,
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(hide)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(
            title: L10n.mainQuit.t,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appItem.submenu = appMenu
        main.addItem(appItem)

        // Edit menu — required for Cmd+C/V/X/A/Z to work in text fields.
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.mainEdit.t)
        editMenu.addItem(NSMenuItem(title: L10n.mainUndo.t, action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: L10n.mainRedo.t, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: L10n.mainCut.t, action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: L10n.mainCopy.t, action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: L10n.mainPaste.t, action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: L10n.mainSelectAll.t, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)

        // Window menu — provides ⌘W close.
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: L10n.mainWindow.t)
        windowMenu.addItem(NSMenuItem(
            title: L10n.mainClose.t,
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    // MARK: - Session lifecycle

    private func openSession() {
        sessionActive = true
        session.startNew()
        eventTap.consumingKeys = true
        hud.show()
    }

    private func finalizeSession() {
        // Stop consuming keys immediately so the focused app starts receiving
        // input again as soon as we paste.
        eventTap.consumingKeys = false
        let wasActive = sessionActive
        sessionActive = false
        guard wasActive else { return }

        // If nothing was typed, just dismiss the HUD without injecting.
        if session.isEmpty {
            hud.dismiss()
            return
        }

        Task { [weak self] in
            guard let self = self else { return }
            let final = await self.session.finalize()
            await MainActor.run {
                if final.isEmpty {
                    self.hud.dismiss()
                    return
                }
                self.hud.showResult(final)
                HistoryStore.shared.add(input: final, output: final)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            await MainActor.run {
                TextInjector.inject(final)
                self.hud.dismiss(after: 0.05)
            }
        }
    }

    private func abortSession() {
        eventTap.consumingKeys = false
        sessionActive = false
        session.cancel()
        hud.dismiss()
    }
}

// MARK: - EventTapDelegate

extension AppDelegate: EventTapDelegate {
    func eventTapDidPressTrigger() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.sessionActive {
                self.finalizeSession()
            } else {
                self.openSession()
            }
        }
    }

    func eventTapDidReceiveCharacter(_ s: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.sessionActive else { return }
            self.session.append(s)
        }
    }

    func eventTapDidPressBackspace() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.sessionActive else { return }
            self.session.backspace()
        }
    }

    func eventTapDidPressEnter() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.sessionActive else { return }
            Task { [weak self] in
                await self?.session.commitCandidateOrConvertNow()
            }
        }
    }

    func eventTapDidPressEscape() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.sessionActive else { return }
            self.abortSession()
        }
    }
}
