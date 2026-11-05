import Foundation

struct TranscriptionModel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    /// Price in dollars per hour of audio, when the model is billed by duration.
    let pricePerHour: Double?

    var priceLabel: String {
        guard let price = pricePerHour else { return tr("Pay per use", "Facturé à l'usage") }
        return tr(String(format: "$%.2f / hour", price), String(format: "%.2f $ / heure", price))
    }
}

/// List of transcription models offered by OpenRouter.
@MainActor
final class ModelCatalog: ObservableObject {
    static let shared = ModelCatalog()

    @Published private(set) var models: [TranscriptionModel] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    /// Models that OpenRouter serves with zero data retention (empty until the list has been loaded once).
    @Published private(set) var zdrModelIDs: Set<String> = []

    private let cacheURL: URL
    private let zdrCacheURL: URL

    private init() {
        cacheURL = AppFolder.url.appendingPathComponent("models.json")
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([TranscriptionModel].self, from: data),
           !cached.isEmpty {
            models = cached
        } else {
            models = Self.fallback
        }
        zdrCacheURL = AppFolder.url.appendingPathComponent("zdr-models.json")
        if let data = try? Data(contentsOf: zdrCacheURL),
           let cached = try? JSONDecoder().decode(Set<String>.self, from: data) {
            zdrModelIDs = cached
        }
    }

    /// True / false when the zero-data-retention compatibility is known, nil otherwise.
    func isZDRCompatible(_ id: String) -> Bool? {
        zdrModelIDs.isEmpty ? nil : zdrModelIDs.contains(id)
    }

    /// Compatible models first, then the others (unusable while zero data retention is enforced).
    var compatibleModels: [TranscriptionModel] { models.filter { isZDRCompatible($0.id) != false } }
    var incompatibleModels: [TranscriptionModel] { models.filter { isZDRCompatible($0.id) == false } }

    private func refreshZDR() async {
        guard let url = URL(string: Constants.openRouterZDRURL) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ZDRResponse.self, from: data) else { return }
        let ids = Set(decoded.data.compactMap(\.model_id))
        guard !ids.isEmpty else { return }
        zdrModelIDs = ids
        if let encoded = try? JSONEncoder().encode(ids) {
            try? encoded.write(to: zdrCacheURL)
        }
    }

    private struct ZDRResponse: Decodable {
        struct Endpoint: Decodable { let model_id: String? }
        let data: [Endpoint]
    }

    func model(for id: String) -> TranscriptionModel? {
        models.first { $0.id == id }
    }

    func refresh() async {
        guard !isLoading, let url = URL(string: Constants.openRouterModelsURL) else { return }
        isLoading = true
        defer { isLoading = false }
        await refreshZDR()

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                loadFailed = true
                return
            }
            let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
            let fetched = decoded.data
                .map { $0.model }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            guard !fetched.isEmpty else {
                loadFailed = true
                return
            }
            models = fetched
            loadFailed = false
            if let encoded = try? JSONEncoder().encode(fetched) {
                try? encoded.write(to: cacheURL)
            }
        } catch {
            loadFailed = true
        }
    }

    // MARK: - Decoding the OpenRouter response

    private struct APIResponse: Decodable {
        let data: [APIModel]
    }

    private struct APIModel: Decodable {
        let id: String
        let name: String?
        let description: String?
        let pricing: Pricing?

        struct Pricing: Decodable {
            let prompt: String?
            let completion: String?
        }

        var model: TranscriptionModel {
            // Models billed per second have a zero output price.
            var hourly: Double?
            if let prompt = Double(pricing?.prompt ?? ""),
               (Double(pricing?.completion ?? "0") ?? 0) == 0 {
                let perHour = prompt * 3600
                if perHour >= 0.005 && perHour <= 10 { hourly = perHour }
            }
            let text = (description ?? "").replacingOccurrences(of: "\n", with: " ")
            return TranscriptionModel(id: id, name: name ?? id, summary: text, pricePerHour: hourly)
        }
    }

    /// Used as long as the list could never be downloaded.
    private static let fallback: [TranscriptionModel] = [
        TranscriptionModel(id: "assemblyai/universal-3-5-pro", name: "AssemblyAI: Universal-3.5 Pro", summary: "", pricePerHour: 0.45),
        TranscriptionModel(id: "elevenlabs/scribe-v2", name: "ElevenLabs: Scribe v2", summary: "", pricePerHour: nil),
        TranscriptionModel(id: "openai/gpt-4o-transcribe", name: "OpenAI: GPT-4o Transcribe", summary: "", pricePerHour: nil),
        TranscriptionModel(id: "openai/gpt-4o-mini-transcribe", name: "OpenAI: GPT-4o Mini Transcribe", summary: "", pricePerHour: nil),
        TranscriptionModel(id: "openai/whisper-large-v3", name: "OpenAI: Whisper Large v3", summary: "", pricePerHour: nil)
    ]
}

/// App data folder (~/Library/Application Support/FnVoice).
enum AppFolder {
    static let url: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("FnVoice", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()
}
