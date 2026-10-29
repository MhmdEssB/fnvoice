import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var lastError: String?
    @Published var hasAPIKey: Bool
    /// True when the last transcription failed and the audio is still available.
    @Published var canRetry = false
    /// True when macOS does not let FnVoice paste the text for you.
    @Published var needsAccessibility = false

    let audioRecorder = AudioRecorder()
    let keyboardService = KeyboardService()

    private var pendingAudioURL: URL?

    init() {
        hasAPIKey = KeychainHelper.shared.hasAPIKey

        // Push-to-talk: Fn pressed = record, Fn released = transcribe
        keyboardService.onFnPressed = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }

        keyboardService.onFnReleased = { [weak self] in
            Task { @MainActor in
                self?.stopRecordingAndTranscribe()
            }
        }

        // Start monitoring the keyboard
        keyboardService.startMonitoring()

        // Check the accessibility permissions
        if !TextInjector.hasAccessibilityPermission() {
            needsAccessibility = true
            TextInjector.requestAccessibilityPermission()
        }

        // Refresh the list of available models
        Task { await ModelCatalog.shared.refresh() }
    }

    private func startRecording() {
        guard hasAPIKey else {
            lastError = tr("Add your OpenRouter key in Settings", "Configure ta clé OpenRouter dans les préférences")
            SoundService.shared.playErrorSound()
            return
        }

        guard !isTranscribing else { return }
        guard !isRecording else { return }

        // Start recording FIRST so the first words are captured
        do {
            try audioRecorder.startRecording()
            isRecording = true
            lastError = nil
            needsAccessibility = !TextInjector.hasAccessibilityPermission()
            canRetry = false
            pendingAudioURL = nil
            SoundService.shared.playStartSound()
        } catch {
            lastError = error.localizedDescription
            SoundService.shared.playErrorSound()
            return
        }

        // Capture the focused app AFTER (in parallel with the recording)
        TextInjector.shared.captureTargetApp()
    }

    private func stopRecordingAndTranscribe() {
        guard isRecording else { return }
        isRecording = false

        guard let recording = audioRecorder.stopRecording() else {
            lastError = tr("No recording found", "Aucun enregistrement trouvé")
            SoundService.shared.playErrorSound()
            return
        }

        // Accidental Fn press: send nothing
        guard recording.duration >= Constants.minimumRecordingDuration else {
            audioRecorder.cleanup()
            return
        }

        SoundService.shared.playStopSound()
        transcribe(recording.url)
    }

    /// Retries the transcription of the last recording after an error.
    func retryLastRecording() {
        guard canRetry, !isTranscribing, !isRecording, let url = pendingAudioURL else { return }
        TextInjector.shared.captureTargetApp()
        transcribe(url)
    }

    private func transcribe(_ audioURL: URL) {
        isTranscribing = true
        lastError = nil
        canRetry = false
        pendingAudioURL = audioURL

        Task {
            do {
                let raw = try await TranscriptionService.shared.transcribe(audioURL: audioURL)
                let vocabulary = VocabularyService.shared
                let text = vocabulary.applyReplacements(to: raw)

                if !text.isEmpty {
                    HistoryService.shared.add(text)
                    if !TextInjector.shared.inject(text: text) {
                        lastError = tr("Text copied. Paste it with Cmd+V. To paste automatically, allow FnVoice under Accessibility.", "Texte copié : colle-le avec Cmd+V. Pour le collage automatique, autorise FnVoice dans Accessibilité.")
                        needsAccessibility = true
                    }
                    if AppSettings.shared.autoLearn {
                        vocabulary.learn(from: text)
                    }
                }
                isTranscribing = false
                pendingAudioURL = nil
                audioRecorder.cleanup()
            } catch {
                // The audio is kept until the next recording so a retry is possible
                lastError = error.localizedDescription
                isTranscribing = false
                canRetry = true
                SoundService.shared.playErrorSound()
            }
        }
    }

    func updateAPIKey(_ key: String) async -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = await TranscriptionService.shared.validateAPIKey(trimmed)
        if isValid {
            _ = KeychainHelper.shared.save(apiKey: trimmed)
            hasAPIKey = true
            lastError = nil
        }
        return isValid
    }

    func clearAPIKey() {
        KeychainHelper.shared.delete()
        hasAPIKey = false
    }
}
