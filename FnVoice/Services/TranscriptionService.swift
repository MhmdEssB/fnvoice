import AVFoundation
import Foundation

/// Transcription through OpenRouter, with the model chosen in Settings.
final class TranscriptionService {
    static let shared = TranscriptionService()
    private init() {}

    private struct TranscriptionResponse: Decodable {
        let text: String
    }

    private struct ErrorResponse: Decodable {
        let error: ErrorDetail

        struct ErrorDetail: Decodable {
            let message: String
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let apiKey = KeychainHelper.shared.getAPIKey() else {
            throw TranscriptionError.noAPIKey
        }

        let (model, language, strictPrivacy) = await MainActor.run {
            (AppSettings.shared.modelID, AppSettings.shared.language, AppSettings.shared.strictPrivacy)
        }

        let chunks = try await splitIfNeeded(audioURL, model: model)
        defer {
            for chunk in chunks where chunk != audioURL {
                try? FileManager.default.removeItem(at: chunk)
            }
        }

        var parts: [String] = []
        for chunk in chunks {
            let audio = try Data(contentsOf: chunk)
            let text = try await transcribe(
                audio: audio,
                model: model,
                language: language,
                strictPrivacy: strictPrivacy,
                apiKey: apiKey
            )
            parts.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    // MARK: - Request

    /// Sends a piece of audio. If the model rejects the vocabulary, retries with fewer terms.
    private func transcribe(audio: Data, model: String, language: String, strictPrivacy: Bool, apiKey: String) async throws -> String {
        let known = AppSettings.shared.keytermCap(for: model)
        let caps = Constants.keytermCaps.filter { known == nil || $0 <= known! }

        var lastError: Error = TranscriptionError.invalidResponse
        for cap in caps {
            let keyterms = await MainActor.run { VocabularyService.shared.keyterms(limit: cap) }
            do {
                let text = try await send(
                    audio: audio,
                    model: model,
                    language: language,
                    keyterms: keyterms,
                    strictPrivacy: strictPrivacy,
                    apiKey: apiKey
                )
                if known != cap { AppSettings.shared.setKeytermCap(cap, for: model) }
                return text
            } catch TranscriptionError.badRequest(let message) where !keyterms.isEmpty {
                // Probably the vocabulary: retry with a shorter list
                lastError = TranscriptionError.badRequest(message)
                continue
            }
        }
        throw lastError
    }

    private func send(audio: Data, model: String, language: String, keyterms: [String], strictPrivacy: Bool, apiKey: String) async throws -> String {
        guard let url = URL(string: Constants.openRouterTranscriptionURL) else {
            throw TranscriptionError.invalidResponse
        }

        var payload: [String: Any] = [
            "model": model,
            "input_audio": [
                "data": audio.base64EncodedString(),
                "format": "wav"
            ]
        ]
        if language != "auto" { payload["language"] = language }
        if !keyterms.isEmpty { payload["keyterms"] = keyterms }
        if strictPrivacy { payload["provider"] = ["data_collection": "deny"] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("FnVoice for macOS", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        if httpResponse.statusCode == 200 {
            return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
        }

        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message
        switch httpResponse.statusCode {
        case 400: throw TranscriptionError.badRequest(message ?? tr("request rejected", "requête refusée"))
        case 401: throw TranscriptionError.invalidAPIKey
        case 402: throw TranscriptionError.noCredit
        case 404: throw TranscriptionError.modelUnavailable(message)
        case 413: throw TranscriptionError.tooLarge
        case 429: throw TranscriptionError.rateLimited
        default: throw TranscriptionError.httpError(httpResponse.statusCode, message)
        }
    }

    // MARK: - Splitting long dictations

    /// Some models limit the duration per request: the audio is then split into chunks.
    func splitIfNeeded(_ audioURL: URL, model: String) async throws -> [URL] {
        guard let limit = Constants.modelMaxSeconds[model] else { return [audioURL] }

        let file = try AVAudioFile(forReading: audioURL)
        let format = file.processingFormat
        let duration = Double(file.length) / format.sampleRate
        guard duration > limit - 5 else { return [audioURL] }

        let chunkFrames = AVAudioFrameCount((limit - 20) * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw TranscriptionError.splitFailed
        }

        var chunks: [URL] = []
        do {
            while file.framePosition < file.length {
                try file.read(into: buffer, frameCount: chunkFrames)
                guard buffer.frameLength > 0 else { break }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("whisper_chunk_\(UUID().uuidString).wav")
                let output = try AVAudioFile(forWriting: url, settings: file.fileFormat.settings)
                chunks.append(url)
                try output.write(from: buffer)
            }
        } catch {
            chunks.forEach { try? FileManager.default.removeItem(at: $0) }
            throw TranscriptionError.splitFailed
        }
        return chunks
    }

    // MARK: - API key

    /// Checks the key with OpenRouter, without saving it.
    func validateAPIKey(_ apiKey: String) async -> Bool {
        guard let url = URL(string: Constants.openRouterKeyCheckURL) else { return false }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    enum TranscriptionError: LocalizedError {
        case noAPIKey
        case invalidAPIKey
        case noCredit
        case modelUnavailable(String?)
        case tooLarge
        case rateLimited
        case splitFailed
        case invalidResponse
        case badRequest(String)
        case httpError(Int, String?)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return tr("OpenRouter key not set", "Clé OpenRouter non configurée")
            case .invalidAPIKey:
                return tr("OpenRouter rejected the key. Check it in Settings.", "Clé OpenRouter refusée : vérifie-la dans les préférences")
            case .noCredit:
                return tr("OpenRouter credit used up. Top up your account at openrouter.ai.", "Crédit OpenRouter épuisé : recharge ton compte sur openrouter.ai")
            case .modelUnavailable(let message):
                return tr("Model unavailable. Pick another one in Settings.", "Modèle indisponible : choisis-en un autre dans les préférences") + (message.map { " (\($0))" } ?? "")
            case .tooLarge:
                return tr("Recording too long for this model", "Enregistrement trop long pour ce modèle")
            case .rateLimited:
                return tr("Too many requests. Try again in a moment.", "Trop de demandes à la suite : réessaie dans un instant")
            case .splitFailed:
                return tr("Could not split this recording", "Impossible de découper cet enregistrement")
            case .invalidResponse:
                return tr("Invalid response from the server", "Réponse invalide du serveur")
            case .badRequest(let message):
                return tr("Request rejected: \(message)", "Demande refusée : \(message)")
            case .httpError(let code, let message):
                return "Erreur \(code)" + (message.map { " : \($0)" } ?? "")
            }
        }
    }
}
