import Foundation
import Combine

final class AppState: ObservableObject {
    static let shared = AppState()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let enabled          = "jt.enabled"
        static let trigger          = "jt.trigger"
        static let baseURL          = "jt.baseURL"
        static let apiKey           = "jt.apiKey"
        static let model            = "jt.model"
        static let useScreenContext = "jt.useScreenContext"
        static let language         = "jt.language"
    }

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Keys.enabled) }
    }

    @Published var trigger: TriggerKey {
        didSet { defaults.set(trigger.rawValue, forKey: Keys.trigger) }
    }

    @Published var baseURL: String {
        didSet { defaults.set(baseURL, forKey: Keys.baseURL) }
    }

    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Keys.apiKey) }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    @Published var useScreenContext: Bool {
        didSet { defaults.set(useScreenContext, forKey: Keys.useScreenContext) }
    }

    @Published var language: Language {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    private init() {
        self.enabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        let triggerRaw = defaults.string(forKey: Keys.trigger) ?? TriggerKey.fn.rawValue
        self.trigger = TriggerKey(rawValue: triggerRaw) ?? .fn
        self.baseURL = defaults.string(forKey: Keys.baseURL) ?? "https://openrouter.ai/api/v1"
        self.apiKey  = defaults.string(forKey: Keys.apiKey) ?? ""
        self.model   = defaults.string(forKey: Keys.model) ?? "google/gemini-2.5-flash"
        self.useScreenContext = defaults.object(forKey: Keys.useScreenContext) as? Bool ?? true
        // Default to English for international users; keep an existing user
        // preference if one was saved previously.
        let langRaw = defaults.string(forKey: Keys.language) ?? Language.en.rawValue
        self.language = Language(rawValue: langRaw) ?? .en
    }
}
