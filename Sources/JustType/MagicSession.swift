import Foundation
import AppKit

/// State for an active "magic input" session — the user has tapped the
/// trigger key and is now typing into a floating box. On pause we ask the
/// LLM to convert the trailing raw segment into a candidate; ↩ commits it,
/// another tap of the trigger finalizes everything and injects.
final class MagicSession: ObservableObject {
    /// Text the user has already accepted (via ↩) — locked in.
    @Published var committed: String = ""
    /// The current raw keyboard segment being typed (not yet converted).
    @Published var raw: String = ""
    /// LLM-converted candidate of `raw`, shown below as IME-style preview.
    @Published var candidate: String? = nil
    /// True while an LLM call for the current raw is in flight.
    @Published var converting: Bool = false
    /// Most recent error message (transient).
    @Published var errorMessage: String? = nil

    /// Optional screenshot taken at session start, reused for every LLM call.
    private var contextImage: Data? = nil

    private var debounceTask: DispatchWorkItem?
    private var inFlightForRaw: String? = nil

    /// Debounce delay before auto-converting the current raw segment.
    private let debounceInterval: TimeInterval = 0.5

    /// Reset to a fresh session.
    func startNew() {
        debounceTask?.cancel()
        debounceTask = nil
        inFlightForRaw = nil
        committed = ""
        raw = ""
        candidate = nil
        converting = false
        errorMessage = nil
        contextImage = AppState.shared.useScreenContext
            ? Screenshotter.capturePrimary()
            : nil
    }

    var isEmpty: Bool { committed.isEmpty && raw.isEmpty }

    // MARK: - Edit operations

    func append(_ s: String) {
        raw += s
        candidate = nil
        errorMessage = nil
        scheduleConvert()
    }

    func backspace() {
        if !raw.isEmpty {
            raw.removeLast()
            candidate = nil
            errorMessage = nil
            if raw.isEmpty {
                debounceTask?.cancel()
                debounceTask = nil
            } else {
                scheduleConvert()
            }
        } else if !committed.isEmpty {
            // Pull last character off committed text so the user can edit it.
            committed.removeLast()
        }
    }

    /// Enter pressed: commit the current candidate. If no candidate exists yet
    /// (raw too fresh), force-convert first then commit.
    func commitCandidateOrConvertNow() async {
        if let c = candidate {
            committed += c
            raw = ""
            candidate = nil
            debounceTask?.cancel()
            debounceTask = nil
            return
        }
        guard !raw.isEmpty else { return }
        await convertNowAndCommit()
    }

    /// Trigger key pressed again: finalize. Returns the full text to inject.
    func finalize() async -> String {
        debounceTask?.cancel()
        debounceTask = nil
        if let c = candidate {
            committed += c
            raw = ""
            candidate = nil
        } else if !raw.isEmpty {
            await convertNowAndCommit()
        }
        return committed
    }

    func cancel() {
        debounceTask?.cancel()
        debounceTask = nil
        inFlightForRaw = nil
        committed = ""
        raw = ""
        candidate = nil
        converting = false
        errorMessage = nil
    }

    // MARK: - LLM

    private func scheduleConvert() {
        debounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            Task { [weak self] in await self?.convertCurrent() }
        }
        debounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: task)
    }

    private func convertCurrent() async {
        let snapshot = raw
        guard !snapshot.isEmpty else { return }
        guard inFlightForRaw != snapshot else { return }
        inFlightForRaw = snapshot
        converting = true
        defer {
            if inFlightForRaw == snapshot { inFlightForRaw = nil }
            converting = false
        }
        do {
            let result = try await LLMClient.shared.convert(
                snapshot,
                imageData: contextImage,
                prefixContext: committed
            )
            // Only apply if the raw hasn't changed underneath us.
            if raw == snapshot {
                candidate = result
                errorMessage = nil
            }
        } catch {
            if raw == snapshot {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func convertNowAndCommit() async {
        let snapshot = raw
        guard !snapshot.isEmpty else { return }
        debounceTask?.cancel()
        debounceTask = nil
        converting = true
        defer { converting = false }
        do {
            let result = try await LLMClient.shared.convert(
                snapshot,
                imageData: contextImage,
                prefixContext: committed
            )
            if raw == snapshot {
                committed += result
                raw = ""
                candidate = nil
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
