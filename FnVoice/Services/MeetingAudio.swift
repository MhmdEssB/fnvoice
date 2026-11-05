import AVFoundation
import Foundation

/// Mixing and splitting of meeting recordings (16 kHz mono, read in blocks).
enum MeetingAudio {
    private static let sampleRate: Double = 16_000
    /// Size of the blocks read and written (10 s at 16 kHz)
    private static let blockFrames: AVAudioFrameCount = 160_000
    /// Search window for a silence to cut at (200 ms)
    private static let silenceWindow: Int64 = 3_200

    private static let wavSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false
    ]

    /// Output format: mono float 16 kHz (the files written are mono)
    private static let monoFloat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!

    enum AudioError: LocalizedError {
        case buffer

        var errorDescription: String? {
            tr("Could not create the audio buffer", "Mémoire tampon audio impossible à créer")
        }
    }

    /// Mixes the microphone and the system audio (optional) into a 16 kHz mono 16-bit WAV.
    /// The track that started last is shifted (silence added at the beginning).
    static func mix(mic: URL, micStart: Date, system: URL?, systemStart: Date?, to output: URL) throws {
        let micFile = try AVAudioFile(forReading: mic)

        // Missing or unreadable system track: only the microphone is copied
        var sysFile: AVAudioFile?
        if let system, let file = try? AVAudioFile(forReading: system) {
            sysFile = file
        }

        var micOffset: Int64 = 0
        var sysOffset: Int64 = 0
        if sysFile != nil, let systemStart {
            let delta = systemStart.timeIntervalSince(micStart)
            if delta >= 0 {
                sysOffset = Int64((delta * sampleRate).rounded())
            } else {
                micOffset = Int64((-delta * sampleRate).rounded())
            }
        }

        let total = max(micOffset + micFile.length, sysOffset + (sysFile?.length ?? 0))

        guard let micBuf = AVAudioPCMBuffer(pcmFormat: micFile.processingFormat, frameCapacity: blockFrames),
              let sysBuf = AVAudioPCMBuffer(pcmFormat: micFile.processingFormat, frameCapacity: blockFrames),
              let mixBuf = AVAudioPCMBuffer(pcmFormat: monoFloat, frameCapacity: blockFrames),
              let mixed = mixBuf.floatChannelData?[0] else {
            throw AudioError.buffer
        }

        try? FileManager.default.removeItem(at: output)
        // `do` block: the output file is closed (header finalized) at the end of the block
        do {
            let outFile = try AVAudioFile(
                forWriting: output,
                settings: wavSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )

            var pos: Int64 = 0
            while pos < total {
                let n = AVAudioFrameCount(min(Int64(blockFrames), total - pos))
                mixed.update(repeating: 0, count: Int(n))

                try addTrack(micFile, offset: micOffset, from: pos, count: n, into: mixed, scratch: micBuf)
                if let sysFile {
                    // A system track that becomes unreadable along the way is simply ignored
                    try? addTrack(sysFile, offset: sysOffset, from: pos, count: n, into: mixed, scratch: sysBuf)
                }

                for i in 0..<Int(n) {
                    mixed[i] = min(1, max(-1, mixed[i]))
                }
                mixBuf.frameLength = n
                try outFile.write(from: mixBuf)
                pos += Int64(n)
            }
        }
    }

    /// Adds to the output block the samples of the track that cover [pos, pos + n).
    private static func addTrack(_ file: AVAudioFile, offset: Int64, from pos: Int64, count n: AVAudioFrameCount,
                                 into dst: UnsafeMutablePointer<Float>, scratch: AVAudioPCMBuffer) throws {
        let srcStart = pos - offset
        let lo = max(0, srcStart)
        let hi = min(file.length, srcStart + Int64(n))
        guard lo < hi else { return }

        file.framePosition = lo
        try file.read(into: scratch, frameCount: AVAudioFrameCount(hi - lo))
        guard let src = scratch.floatChannelData?[0] else { return }

        let base = Int(lo - srcStart)
        for i in 0..<Int(scratch.frameLength) {
            dst[base + i] += src[i]
        }
    }

    /// Splits a 16 kHz mono WAV into chunks of about `target` seconds (never more than `maxSeconds`).
    /// The cut is made at the center of the quietest 200 ms window between target-20 s and maxSeconds.
    static func split(_ url: URL, target: Double, maxSeconds: Double, into folder: URL) throws -> [(url: URL, start: Double, silent: Bool)] {
        let file = try AVAudioFile(forReading: url)
        let rate = file.processingFormat.sampleRate
        let total = file.length
        let maxFrames = Int64(maxSeconds * rate)
        let minFrames = Int64(max(0, target - 20) * rate)

        guard let scratch = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: blockFrames),
              let outBuf = AVAudioPCMBuffer(pcmFormat: monoFloat, frameCapacity: blockFrames) else {
            throw AudioError.buffer
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var result: [(url: URL, start: Double, silent: Bool)] = []
        var start: Int64 = 0
        while start < total {
            var end = total
            if total - start > maxFrames {
                let lo = start + max(silenceWindow, minFrames)
                let hi = start + maxFrames - silenceWindow
                if lo < hi {
                    end = try quietestCut(file, from: lo, to: hi, scratch: scratch)
                } else {
                    end = start + maxFrames  // degenerate case (target set badly): cut at the limit
                }
            }

            let chunkURL = folder.appendingPathComponent(String(format: "chunk-%03d.wav", result.count + 1))
            let rms = try writeChunk(file, from: start, to: end, url: chunkURL, scratch: scratch, outBuf: outBuf)
            result.append((chunkURL, Double(start) / rate, rms < 0.003))
            start = end
        }
        return result
    }

    /// Duration in seconds, 0 if the file is unreadable.
    static func duration(of url: URL) -> Double {
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Center of the quietest 200 ms window whose start is between lo and hi.
    private static func quietestCut(_ file: AVAudioFile, from lo: Int64, to hi: Int64, scratch: AVAudioPCMBuffer) throws -> Int64 {
        var best = lo
        var bestEnergy = Double.infinity
        var window = lo
        while window <= hi {
            let energy = try meanSquare(file, from: window, count: silenceWindow, scratch: scratch)
            if energy < bestEnergy {
                bestEnergy = energy
                best = window
            }
            window += silenceWindow
        }
        return best + silenceWindow / 2
    }

    private static func meanSquare(_ file: AVAudioFile, from lo: Int64, count: Int64, scratch: AVAudioPCMBuffer) throws -> Double {
        var sum = 0.0
        var seen: Int64 = 0
        try readBlocks(file, from: lo, to: lo + count, scratch: scratch) { samples, got in
            for i in 0..<got {
                sum += Double(samples[i] * samples[i])
            }
            seen += Int64(got)
        }
        return seen > 0 ? sum / Double(seen) : 0
    }

    /// Writes [lo, hi) to `url` and returns the RMS of the chunk.
    private static func writeChunk(_ file: AVAudioFile, from lo: Int64, to hi: Int64, url: URL,
                                   scratch: AVAudioPCMBuffer, outBuf: AVAudioPCMBuffer) throws -> Double {
        try? FileManager.default.removeItem(at: url)
        var sum = 0.0
        var count: Int64 = 0
        // `do` block: the file is closed (header finalized) before returning control
        do {
            let out = try AVAudioFile(forWriting: url, settings: wavSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let dst = outBuf.floatChannelData?[0] else { throw AudioError.buffer }
            try readBlocks(file, from: lo, to: hi, scratch: scratch) { samples, got in
                for i in 0..<got {
                    dst[i] = samples[i]
                    sum += Double(samples[i] * samples[i])
                }
                count += Int64(got)
                outBuf.frameLength = AVAudioFrameCount(got)
                try out.write(from: outBuf)
            }
        }
        return count > 0 ? (sum / Double(count)).squareRoot() : 0
    }

    /// Reads [lo, hi) block by block; `body` receives the samples (channel 0) and their count.
    private static func readBlocks(_ file: AVAudioFile, from lo: Int64, to hi: Int64, scratch: AVAudioPCMBuffer,
                                   _ body: (UnsafePointer<Float>, Int) throws -> Void) throws {
        guard let samples = scratch.floatChannelData?[0] else { return }
        var pos = lo
        while pos < hi {
            let n = AVAudioFrameCount(min(Int64(scratch.frameCapacity), hi - pos))
            file.framePosition = pos
            try file.read(into: scratch, frameCount: n)
            let got = Int(scratch.frameLength)
            if got == 0 { break }
            try body(UnsafePointer(samples), got)
            pos += Int64(got)
        }
    }
}
