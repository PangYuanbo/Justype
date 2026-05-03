import AppKit
import Carbon
import Foundation

/// Handles installing / uninstalling the bundled `JustType IME.app`
/// input-method bundle into `~/Library/Input Methods/`.
///
/// The IME bundle ships embedded inside the main app's `Contents/Resources/`
/// (created at build time by `make ime-bundle`). When the user toggles
/// "Beta: Native Input Method" in Settings, we copy it into the standard
/// per-user input-methods directory and ask Text Input Services to enable
/// the resulting source. The user still has to add it once from
/// System Settings → Keyboard → Input Sources.
enum IMEInstaller {
    static let imeBundleID = "com.justype.app.ime"
    static let imeBundleName = "JustType IME.app"

    /// Where the IME bundle ends up at runtime.
    static var installedURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library/Input Methods", isDirectory: true)
            .appendingPathComponent(imeBundleName, isDirectory: true)
    }

    /// Where the bundle lives inside the main app at distribution time.
    private static var sourceURL: URL? {
        Bundle.main.url(forResource: "JustType IME", withExtension: "app")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installedURL.path)
    }

    /// Copy the IME into ~/Library/Input Methods/ (creating the folder if
    /// missing) and register it with Text Input Services. Returns the
    /// freshly-installed bundle's URL on success.
    @discardableResult
    static func install() throws -> URL {
        let fm = FileManager.default
        guard let source = sourceURL else { throw InstallError.bundleMissing }

        let parent = installedURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        // Replace any existing copy.
        if fm.fileExists(atPath: installedURL.path) {
            try fm.removeItem(at: installedURL)
        }
        try fm.copyItem(at: source, to: installedURL)

        // Tell Launch Services and TIS the new bundle is there.
        registerWithTIS(at: installedURL)
        return installedURL
    }

    /// Remove the IME bundle. The user is responsible for first removing
    /// the input source from System Settings → Keyboard → Input Sources.
    static func uninstall() throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: installedURL.path) {
            try fm.removeItem(at: installedURL)
        }
    }

    /// Open the System Settings input-sources pane so the user can add /
    /// remove JustType from their active input methods.
    static func openInputSourcesPreferences() {
        // macOS 13+ deep-link.
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Input_Sources") {
            NSWorkspace.shared.open(url)
            return
        }
    }

    // MARK: - TIS registration

    private static func registerWithTIS(at bundleURL: URL) {
        // First make sure Launch Services notices the new bundle.
        // Then ask TIS to enable our input source if it can find it.
        let url = bundleURL as CFURL
        TISRegisterInputSource(url)

        guard let allSources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }
        for src in allSources {
            guard
                let idPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID),
                let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String?,
                id == imeBundleID
            else { continue }
            TISEnableInputSource(src)
            return
        }
    }

    enum InstallError: LocalizedError {
        case bundleMissing
        var errorDescription: String? {
            switch self {
            case .bundleMissing:
                return "Couldn't find the bundled IME (JustType IME.app missing from app Resources)."
            }
        }
    }
}
