import Foundation
import ParakeetKit

/// Transcription on this Mac with Parakeet v3: tracks the model state for the UI
/// (download, loading, ready) and passes files to the engine.
@MainActor
final class LocalTranscriber: ObservableObject {
    static let shared = LocalTranscriber()

    enum Status: Equatable {
        case notDownloaded
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var status: Status

    private var preparing: Task<Void, Error>?

    private init() {
        status = ParakeetEngine.isDownloaded ? .loading : .notDownloaded
    }

    var isReady: Bool { status == .ready }

    /// Approximate download size of the model, for display.
    static var downloadSizeLabel: String { tr("≈ 470 MB", "≈ 470 Mo") }

    /// Downloads (once) then loads the model. Does nothing if it is already ready.
    func prepare() async throws {
        if status == .ready { return }
        if let preparing {
            do { return try await preparing.value } catch { throw LocalError.unavailable(error.localizedDescription) }
        }

        let task = Task<Void, Error> { @MainActor in
            status = ParakeetEngine.isDownloaded ? .loading : .downloading(0)
            try await ParakeetEngine.shared.prepare { fraction in
                Task { @MainActor in
                    let shared = LocalTranscriber.shared
                    // Once downloaded, FluidAudio compiles the model: show it as loading
                    if case .downloading = shared.status {
                        shared.status = fraction >= 1 ? .loading : .downloading(fraction)
                    }
                }
            }
            status = .ready
        }
        preparing = task
        defer { preparing = nil }
        do {
            try await task.value
        } catch {
            status = .failed(error.localizedDescription)
            throw LocalError.unavailable(error.localizedDescription)
        }
    }

    /// Prepares the model in the background (at launch, or when it is selected).
    func warmUp() {
        Task { try? await prepare() }
    }

    func transcribe(_ url: URL) async throws -> String {
        try await prepare()
        return try await ParakeetEngine.shared.transcribe(fileURL: url)
    }

    enum LocalError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let reason):
                return tr("Local model unavailable (\(reason)). Check your connection for the first download, or pick an online model in Settings.", "Modèle local indisponible (\(reason)). Vérifie ta connexion pour le premier téléchargement, ou choisis un modèle en ligne dans les préférences.")
            }
        }
    }
}
