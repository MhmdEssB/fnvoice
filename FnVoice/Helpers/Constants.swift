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

    /// On-device transcription (NVIDIA Parakeet TDT 0.6B v3, through FluidAudio): free, instant,
    /// and the voice never leaves the Mac. Default model since FnVoice 2.3.
    static let localModelID = "local/parakeet-tdt-0.6b-v3"
    static var localModelName: String { tr("Parakeet v3 (on this Mac)", "Parakeet v3 (sur ce Mac)") }
    /// Online model suggested when the local model is not used.
    static let defaultCloudModel = "assemblyai/universal-3-5-pro"
    static let defaultModel = localModelID
    static let appVersion = "2.3"

    static func isLocal(_ modelID: String) -> Bool { modelID == localModelID }

    /// Maximum duration (in seconds) accepted per request by some models.
    /// Beyond that, the audio is split into chunks.
    static let modelMaxSeconds: [String: Double] = [
        "assemblyai/universal-3-5-pro": 120
    ]

    /// Below this duration, an Fn press is treated as accidental.
    static let minimumRecordingDuration: TimeInterval = 0.35

    /// Number of vocabulary terms sent to the model, from the largest to the safest.
    static let keytermCaps = [300, 100, 0]

    /// Models offered to review each transcription against the glossary, all served with zero data retention.
    /// Picked after a benchmark (trick dictations, misheard acronyms, questions and orders inside the dictation,
    /// reasoning off). Smaller models (Llama 8B, Mistral Nemo, Nova Micro) answered the dictated content
    /// instead of correcting it, so they are not offered.
    /// Cost measured with a vocabulary of about 770 terms (it grows with the vocabulary).
    static let correctionChoices: [CorrectionModel] = [
        CorrectionModel(id: "deepseek/deepseek-v4-flash-0731", name: "DeepSeek V4 Flash",
                        summary: tr("The fastest, no mistakes in the benchmark.", "Le plus rapide, sans faute au banc d'essai."),
                        costPer1000: 0.25, seconds: 1.0),
        CorrectionModel(id: "inclusionai/ling-3.1-flash", name: "Ling 3.1 Flash",
                        summary: tr("The cheapest, no mistakes in the benchmark, a bit slower.", "Le moins cher, sans faute au banc d'essai, un peu plus lent."),
                        costPer1000: 0.04, seconds: 1.8),
        CorrectionModel(id: "mistralai/mistral-small-24b-instruct-2501", name: "Mistral Small 3",
                        summary: tr("Cheap and accurate, but sometimes misses an acronym split into pieces.", "Bon marché et juste, mais rate parfois un sigle mal découpé."),
                        costPer1000: 0.19, seconds: 1.5),
        CorrectionModel(id: "anthropic/claude-haiku-5.5", name: "Claude Haiku 5.5",
                        summary: tr("Very accurate but the most expensive, and sometimes slow (up to 7 s).", "Très juste mais le plus cher, et parfois lent (jusqu'à 7 s)."),
                        costPer1000: 0.68, seconds: 2.2)
    ]
    static let defaultCorrectionModel = "deepseek/deepseek-v4-flash-0731"

    /// Order tried: the chosen model, then DeepSeek V4 Flash, Ling 3.1 Flash and Haiku if the previous one is unavailable.
    static var correctionModels: [String] {
        var order = [AppSettings.shared.correctionModelID]
        for id in ["deepseek/deepseek-v4-flash-0731", "inclusionai/ling-3.1-flash", "anthropic/claude-haiku-5.5"] where !order.contains(id) {
            order.append(id)
        }
        return order
    }
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

/// A model offered for reviewing dictations.
struct CorrectionModel: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    /// Measured cost, in dollars, for 1,000 dictations.
    let costPer1000: Double
    /// Usual response time, in seconds.
    let seconds: Double

    var costLabel: String {
        prefersFrench
            ? String(format: "%.2f $ / 1 000 dictées", costPer1000).replacingOccurrences(of: ".", with: ",")
            : String(format: "$%.2f / 1,000 dictations", costPer1000)
    }

    var speedLabel: String {
        let text = String(format: "≈ %.1f s", seconds)
        return prefersFrench ? text.replacingOccurrences(of: ".", with: ",") : text
    }
}
