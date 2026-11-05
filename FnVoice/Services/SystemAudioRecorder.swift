import AVFoundation
import CoreAudio
import Foundation

/// Captures all the audio output of the Mac (the voices of the other participants) through a Core Audio tap.
/// Writes a 16 kHz mono 16-bit file. If the audio output changes (AirPods connected during a call),
/// the tap and the aggregate device are rebuilt together and the file continues.
@available(macOS 14.2, *)
final class SystemAudioRecorder {
    enum CaptureError: LocalizedError {
        case tapCreation(OSStatus)
        case noOutputDevice
        case aggregateCreation(OSStatus)
        case unsupportedFormat
        case file(Error)
        case ioProc(OSStatus)

        var errorDescription: String? {
            switch self {
            case .tapCreation(let status):
                return tr(
                    "System audio capture failed (code \(status)). Allow FnVoice in System Settings > Privacy & Security > System Audio Recording.",
                    "Capture audio système impossible (code \(status)). Autorise FnVoice dans Réglages Système > Confidentialité et sécurité > Enregistrement audio du système."
                )
            case .noOutputDevice:
                return tr("No default audio output found", "Aucune sortie audio par défaut trouvée")
            case .aggregateCreation(let status):
                return tr("Could not create the aggregate audio device (code \(status))", "Impossible de créer le périphérique audio agrégé (code \(status))")
            case .unsupportedFormat:
                return tr("Unsupported system audio format", "Format audio système non pris en charge")
            case .file(let error):
                return tr("Could not write the audio file: \(error.localizedDescription)", "Écriture du fichier audio impossible : \(error.localizedDescription)")
            case .ioProc(let status):
                return tr("Could not start audio capture (code \(status))", "Démarrage de la capture audio impossible (code \(status))")
            }
        }
    }

    /// Peak amplitude written so far (close to 0 = silence, often a permission refused).
    var peak: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _peak
        }
    }

    private let queue = DispatchQueue(label: "fnvoice.system-audio", qos: .userInitiated)
    private let lock = NSLock()
    private var _peak: Float = 0

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?

    /// Accessed only from `queue`.
    private var pipeline: Pipeline?

    private struct Pipeline {
        let file: AVAudioFile
        let converter: AVAudioConverter
        let tapFormat: AVAudioFormat
        let outFormat: AVAudioFormat
    }

    private var file: AVAudioFile?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var currentOutputUID: String?
    private var rebuildPending = false
    private var startDate = Date()

    init() {}

    deinit {
        stop()
    }

    /// To be called from the main thread (like `stop`).
    func start(writingTo url: URL) throws {
        stop()
        lock.lock()
        _peak = 0
        lock.unlock()

        do {
            file = try Self.makeFile(url)
            startDate = Date()
            try setUpCapture()
            listenForOutputChanges()
        } catch {
            // Cleans up everything that has already been created
            stop()
            throw error
        }
    }

    /// Idempotent: stops the capture and closes the file.
    func stop() {
        removeOutputListener()
        tearDownCapture()
        file = nil
    }

    /// Destroys the IOProc, the aggregate device and the tap (always together).
    private func tearDownCapture() {
        if let proc = ioProcID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
            ioProcID = nil
        }
        // Synchronous: waits for any block in progress
        queue.sync { pipeline = nil }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    private func setUpCapture() throws {
        guard let file else { throw CaptureError.unsupportedFormat }
        // 1. Tap on the whole output, excluding no process
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        desc.name = "FnVoice meeting"

        var newTap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &newTap)
        guard status == noErr else { throw CaptureError.tapCreation(status) }
        tapID = newTap

        // 2. Private aggregate device that carries the tap
        let outputUID = try defaultOutputUID()
        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "FnVoice meeting",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: desc.uuid.uuidString
                ]
            ]
        ]
        var newAggregate = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggregateDict as CFDictionary, &newAggregate)
        guard status == noErr else { throw CaptureError.aggregateCreation(status) }
        aggregateID = newAggregate

        // 3. Actual format delivered by the tap
        var formatAddress = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &formatAddress, 0, nil, &size, &asbd)
        guard status == noErr, let tapFormat = AVAudioFormat(streamDescription: &asbd) else {
            throw CaptureError.unsupportedFormat
        }
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: tapFormat, to: outFormat) else {
            throw CaptureError.unsupportedFormat
        }

        queue.sync {
            pipeline = Pipeline(file: file, converter: converter, tapFormat: tapFormat, outFormat: outFormat)
        }

        // 5. Reading the buffers on the dedicated queue
        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, queue) { [weak self] _, inInputData, _, _, _ in
            self?.process(inInputData)
        }
        guard status == noErr, let proc else { throw CaptureError.ioProc(status) }
        ioProcID = proc

        status = AudioDeviceStart(aggregateID, proc)
        guard status == noErr else { throw CaptureError.ioProc(status) }
        currentOutputUID = outputUID // only once the capture has really restarted
    }

    private static func makeFile(_ url: URL) throws -> AVAudioFile {
        do {
            return try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ],
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
        } catch {
            throw CaptureError.file(error)
        }
    }

    // MARK: - Audio output change

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private func listenForOutputChanges() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleRebuild()
        }
        outputListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, listener)
    }

    private func removeOutputListener() {
        guard let listener = outputListener else { return }
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &Self.defaultOutputAddress, .main, listener)
        outputListener = nil
    }

    /// On the main thread. Waits for the new output to be stable (AirPods switch mode
    /// when they connect), then rebuilds the tap and the aggregate device if the output really changed.
    private func scheduleRebuild() {
        guard !rebuildPending, outputListener != nil else { return }
        rebuildPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.rebuildPending = false
            guard self.outputListener != nil, self.file != nil,
                  let uid = try? self.defaultOutputUID(), uid != self.currentOutputUID else { return }
            self.tearDownCapture()
            self.padToWallClock()
            do {
                try self.setUpCapture()
            } catch {
                // One-off failure (output still switching): we will retry
                print("System audio capture not restarted: \(error.localizedDescription)")
                self.tearDownCapture()
                self.currentOutputUID = nil
                self.scheduleRebuild()
            }
        }
    }

    /// Fills with silence the gap left by the rebuild, to stay aligned with the microphone.
    private func padToWallClock() {
        guard let file,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false) else { return }
        let expected = AVAudioFramePosition(Date().timeIntervalSince(startDate) * 16_000)
        var missing = expected - file.length
        while missing > 0 {
            let count = AVAudioFrameCount(min(missing, 160_000))
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return }
            silence.frameLength = count // memory is already zeroed
            if let data = silence.floatChannelData?[0] { data.update(repeating: 0, count: Int(count)) }
            guard (try? file.write(from: silence)) != nil else { return }
            missing -= AVAudioFramePosition(count)
        }
    }

    /// Called on `queue`: converts to 16 kHz mono, writes, and updates the peak.
    private func process(_ inputData: UnsafePointer<AudioBufferList>) {
        guard let p = pipeline else { return }
        guard let input = AVAudioPCMBuffer(pcmFormat: p.tapFormat, bufferListNoCopy: inputData, deallocator: nil),
              input.frameLength > 0 else { return }

        let capacity = AVAudioFrameCount(Double(input.frameLength) * p.outFormat.sampleRate / p.tapFormat.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: p.outFormat, frameCapacity: capacity) else { return }

        var fed = false
        var convError: NSError?
        let status = p.converter.convert(to: output, error: &convError) { _, inputStatus in
            // A single input block per call
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, output.frameLength > 0, let samples = output.floatChannelData?[0] else { return }

        var localPeak: Float = 0
        for i in 0..<Int(output.frameLength) {
            localPeak = max(localPeak, abs(samples[i]))
        }
        lock.lock()
        _peak = max(_peak, localPeak)
        lock.unlock()

        do {
            try p.file.write(from: output)
        } catch {
            print("System audio write error: \(error.localizedDescription)")
        }
    }

    /// UID of the default output device, required by the aggregate device.
    private func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        guard status == noErr, deviceID != kAudioObjectUnknown else { throw CaptureError.noOutputDevice }

        address.mSelector = kAudioDevicePropertyDeviceUID
        // Core Audio returns a retained CFString (+1): it is handed over to ARC
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr, let uid else { throw CaptureError.noOutputDevice }
        return uid.takeRetainedValue() as String
    }
}
