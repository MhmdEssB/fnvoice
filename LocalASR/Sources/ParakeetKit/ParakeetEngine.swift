import Foundation
internal import FluidAudio

/// Fully on-device transcription with Parakeet TDT 0.6B v3 (25 European languages).
/// The model (~470 MB) is downloaded once, then stays loaded in memory:
/// the voice never leaves the Mac.
public actor ParakeetEngine {
    public static let shared = ParakeetEngine()

    private var models: AsrModels?
    private var manager: AsrManager?
    private var loading: Task<(AsrModels, AsrManager), Error>?

    private init() {}

    /// True when the model is already on disk (no download needed).
    public nonisolated static var isDownloaded: Bool {
        AsrModels.modelsExist(at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
    }

    /// Folder where the model is stored.
    public nonisolated static var modelDirectory: URL {
        AsrModels.defaultCacheDirectory(for: .v3)
    }

    /// True when the model is loaded and ready to transcribe without delay.
    public var isReady: Bool { models != nil && manager != nil }

    /// Downloads the model if needed and loads it on the Neural Engine.
    /// `progress` receives a fraction between 0 and 1 during the download.
    public func prepare(progress: (@Sendable (Double) -> Void)? = nil) async throws {
        if isReady { return }
        if let loading {
            _ = try await loading.value
            return
        }
        let task = Task<(AsrModels, AsrManager), Error> {
            let loaded = try await AsrModels.downloadAndLoad(version: .v3) { update in
                progress?(update.fractionCompleted)
            }
            let asr = AsrManager(config: .default)
            try await asr.loadModels(loaded)
            return (loaded, asr)
        }
        loading = task
        do {
            let (loaded, asr) = try await task.value
            models = loaded
            manager = asr
            loading = nil
        } catch {
            loading = nil
            throw error
        }
    }

    /// Last queued transcription: one at a time, in arrival order.
    private var queueTail: Task<Void, Never>?

    /// Transcribes an audio file (WAV, M4A…), whatever its length.
    /// Long recordings are split and stitched back by FluidAudio.
    /// Simultaneous calls (meeting chunks, a dictation during a meeting) run one after the other:
    /// FluidAudio's manager does not support two transcriptions at once.
    public func transcribe(fileURL: URL) async throws -> String {
        let previous = queueTail
        let job = Task { () async throws -> String in
            _ = await previous?.value
            return try await self.run(fileURL)
        }
        queueTail = Task { _ = try? await job.value }
        return try await withTaskCancellationHandler {
            try await job.value
        } onCancel: {
            job.cancel()
        }
    }

    private func run(_ fileURL: URL) async throws -> String {
        try Task.checkCancellation()
        try await prepare()
        guard let models, let manager else { throw ParakeetError.notReady }
        // The manager drops its models after each transcription: hand them back
        // (a plain reference, the model stays in memory).
        try await manager.loadModels(models)
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(fileURL, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum ParakeetError: LocalizedError {
    case notReady

    public var errorDescription: String? {
        switch self {
        case .notReady: return "The local model is not ready"
        }
    }
}
