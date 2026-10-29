import AVFoundation
import Foundation

final class AudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?

    override init() {
        super.init()
        // Triggers the permission request at launch
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
    }

    /// Re-read for every recording: the permission can be granted after launch.
    private var hasPermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func getRecordingURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("whisper_recording_\(UUID().uuidString).wav")
    }

    func startRecording() throws {
        guard hasPermission else {
            throw RecordingError.noPermission
        }

        // Delete the previous recording if it was kept for a retry
        cleanup()

        let url = getRecordingURL()
        recordingURL = url

        // WAV: the only format accepted by all transcription models
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000, // 16 kHz is enough for voice
            AVNumberOfChannelsKey: 1, // Mono
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        guard recorder.record() else {
            throw RecordingError.recordingFailed
        }
        audioRecorder = recorder
        isRecording = true
    }

    /// Stops the recording and returns the file with its duration.
    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        let duration = audioRecorder?.currentTime ?? 0
        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false
        guard let url = recordingURL else { return nil }
        return (url, duration)
    }

    func cleanup() {
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
    }

    enum RecordingError: LocalizedError {
        case noPermission
        case recordingFailed

        var errorDescription: String? {
            switch self {
            case .noPermission:
                return tr("Microphone access denied. Allow it in System Settings > Privacy & Security > Microphone.", "Accès au microphone refusé (Réglages Système > Confidentialité > Microphone)")
            case .recordingFailed:
                return tr("Recording failed", "Échec de l'enregistrement")
            }
        }
    }
}

extension AudioRecorder: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print(tr("Recording finished with an error", "Enregistrement terminé avec erreur"))
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("Erreur d'encodage: \(error.localizedDescription)")
        }
    }
}
