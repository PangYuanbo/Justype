import Cocoa
import InputMethodKit

// Entry point for the JustType input-method bundle. macOS spawns this
// process via imklaunchagent the first time the user activates the IME
// from the input-source menu. We register an IMKServer keyed off the
// CFBundleIdentifier and let IMK route events to JustTypeInputController.

let connectionName: String = {
    let key = "InputMethodConnectionName"
    if let name = Bundle.main.object(forInfoDictionaryKey: key) as? String {
        return name
    }
    return "JustType_IME_Connection"
}()

let bundleId = Bundle.main.bundleIdentifier ?? "com.justype.app.ime"

let app = NSApplication.shared
_ = IMKServer(name: connectionName, bundleIdentifier: bundleId)
NSLog("JustType IME: server registered as \(connectionName) for \(bundleId)")
app.run()
