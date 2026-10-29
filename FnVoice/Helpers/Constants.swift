import Foundation

enum Constants {
    static let keychainService = "com.mhmdessb.fnvoice"
    static let keychainAPIKeyAccount = "openrouter-api-key"

    static let openRouterTranscriptionURL = "https://openrouter.ai/api/v1/audio/transcriptions"
    static let openRouterModelsURL = "https://openrouter.ai/api/v1/models?output_modalities=transcription"
    static let openRouterKeyCheckURL = "https://openrouter.ai/api/v1/key"
    static let openRouterKeysPage = "https://openrouter.ai/keys"

    static let defaultModel = "assemblyai/universal-3-5-pro"
    static let appVersion = "2.0"

    /// Maximum duration (in seconds) accepted per request by some models.
    /// Beyond that, the audio is split into chunks.
    static let modelMaxSeconds: [String: Double] = [
        "assemblyai/universal-3-5-pro": 120
    ]

    /// Below this duration, an Fn press is treated as accidental.
    static let minimumRecordingDuration: TimeInterval = 0.35

    /// Number of vocabulary terms sent to the model, from the largest to the safest.
    static let keytermCaps = [300, 100, 0]
}

/// English by default; French when the system language is French.
let prefersFrench = Locale.preferredLanguages.first?.hasPrefix("fr") == true
func tr(_ en: String, _ fr: String) -> String { prefersFrench ? fr : en }
