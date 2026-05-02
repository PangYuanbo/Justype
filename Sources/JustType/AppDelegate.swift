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
    }

    func applicationWillTerminate(_ notification: Notification) {
        eventTap?.stop()
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
