import Foundation

enum Constants {
    static let keychainService = "com.mhmdessb.fnvoice"
    static let keychainAPIKeyAccount = "openrouter-api-key"

    static let openRouterTranscriptionURL = "https://openrouter.ai/api/v1/audio/transcriptions"
    static let openRouterModelsURL = "https://openrouter.ai/api/v1/models?output_modalities=transcription"
    static let openRouterChatURL = "https://openrouter.ai/api/v1/chat/completions"
    /// Public list of the models served with zero data retention (ZDR).
    static let openRouterZDRURL = "https://openrouter.ai/api/v1/endpoints/zdr"
    static let openRouterKeyCheckURL = "https://openrouter.ai/api/v1/key"
    static let openRouterKeysPage = "https://openrouter.ai/keys"

    static let defaultModel = "assemblyai/universal-3-5-pro"
    static let appVersion = "2.1"

    /// Maximum duration (in seconds) accepted per request by some models.
    /// Beyond that, the audio is split into chunks.
    static let modelMaxSeconds: [String: Double] = [
        "assemblyai/universal-3-5-pro": 120
    ]

    /// Below this duration, an Fn press is treated as accidental.
    static let minimumRecordingDuration: TimeInterval = 0.35

    /// Number of vocabulary terms sent to the model, from the largest to the safest.
    static let keytermCaps = [300, 100, 0]

    /// Models that review each transcription against the glossary (the second one if the first is unavailable).
    /// Claude Haiku 5.5 corrects well without ever rewriting or obeying the dictated text.
    static let correctionModels = ["anthropic/claude-haiku-5.5", "openai/gpt-4.1-mini"]
    static let correctionGlossaryLimit = 1500

    /// Models that write the summary of a meeting.
    static let summaryModels = ["anthropic/claude-haiku-5.5", "openai/gpt-4.1-mini"]

    /// Target duration of each meeting chunk sent for transcription (cut during a silence).
    static let meetingChunkSeconds: Double = 90
    static let meetingChunkMaxSeconds: Double = 110
    /// Number of meeting chunks transcribed at the same time.
    static let meetingConcurrency = 4
}

/// English by default; French when the system language is French.
let prefersFrench = Locale.preferredLanguages.first?.hasPrefix("fr") == true
func tr(_ en: String, _ fr: String) -> String { prefersFrench ? fr : en }
