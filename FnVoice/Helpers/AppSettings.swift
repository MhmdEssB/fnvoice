import Foundation

/// User settings, stored in the app preferences.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var modelID: String {
        didSet { defaults.set(modelID, forKey: "modelID") }
    }

    /// ISO 639-1 code, or "auto" for automatic detection.
    @Published var language: String {
        didSet { defaults.set(language, forKey: "language") }
    }

    @Published var autoLearn: Bool {
        didSet { defaults.set(autoLearn, forKey: "autoLearn") }
    }

    /// Only use providers that do not retain data.
    @Published var strictPrivacy: Bool {
        didSet { defaults.set(strictPrivacy, forKey: "strictPrivacy") }
    }

    static let languages: [(code: String, name: String)] = [
        ("auto", tr("Auto-detect", "Détection automatique")),
        ("en", tr("English", "Anglais")),
        ("fr", tr("French", "Français")),
        ("es", tr("Spanish", "Espagnol")),
        ("de", tr("German", "Allemand")),
        ("it", tr("Italian", "Italien")),
        ("pt", tr("Portuguese", "Portugais")),
        ("ar", tr("Arabic", "Arabe")),
        ("tr", tr("Turkish", "Turc")),
        ("zh", tr("Chinese", "Chinois"))
    ]

    /// The system language when FnVoice supports it, otherwise automatic detection.
    static var systemLanguage: String {
        let code = Locale.current.language.languageCode?.identifier ?? "auto"
        return languages.contains { $0.code == code } ? code : "auto"
    }

    private init() {
        modelID = defaults.string(forKey: "modelID") ?? Constants.defaultModel
        language = defaults.string(forKey: "language") ?? AppSettings.systemLanguage
        autoLearn = defaults.object(forKey: "autoLearn") as? Bool ?? true
        strictPrivacy = defaults.bool(forKey: "strictPrivacy")
    }

    // MARK: - Vocabulary limit accepted by each model

    /// Number of terms the model accepted last time (nil = never tried).
    func keytermCap(for model: String) -> Int? {
        (defaults.dictionary(forKey: "keytermCaps") as? [String: Int])?[model]
    }

    func setKeytermCap(_ cap: Int, for model: String) {
        var caps = defaults.dictionary(forKey: "keytermCaps") as? [String: Int] ?? [:]
        caps[model] = cap
        defaults.set(caps, forKey: "keytermCaps")
    }
}
