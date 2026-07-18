@preconcurrency import AVFoundation
import Foundation

enum AudioRecorderError: LocalizedError {
    case engineStart(Error)
    case noBuffer
    case tooShort

    var errorDescription: String? {
        switch self {
        case .engineStart(let e): return "Mic start failed: \(e.localizedDescription)"
        case .noBuffer: return "No audio captured."
        case .tooShort: return "Hold a bit longer — recording too short."
        }
    }
}

/// Records microphone audio to mono PCM16 WAV (native sample rate).
/// whisper-server `--convert` + ffmpeg resamples to what Whisper needs.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var sampleRate: Double = 48_000
    private var isRecording = false

    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        isRecording = true
        lock.unlock()

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        sampleRate = format.sampleRate

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.append(buffer: buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AudioRecorderError.engineStart(error)
        }
    }

    func stop() throws -> Data {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        lock.lock()
        isRecording = false
        let captured = samples
        let rate = sampleRate
        samples.removeAll(keepingCapacity: false)
        lock.unlock()

        guard captured.count >= Int(rate * 0.25) else {
            throw AudioRecorderError.tooShort
        }
        return Self.wavData(samples: captured, sampleRate: Int(rate))
    }

    func cancel() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        lock.lock()
        isRecording = false
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private func append(buffer: AVAudioPCMBuffer) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var mono = [Int16](repeating: 0, count: frameCount)

        if let int16 = buffer.int16ChannelData {
            let ch0 = int16[0]
            for i in 0..<frameCount {
                mono[i] = ch0[i]
            }
        } else if let float = buffer.floatChannelData {
            let ch0 = float[0]
            let channels = Int(buffer.format.channelCount)
            for i in 0..<frameCount {
                var sample = ch0[i]
                if channels > 1 {
                    var sum = sample
                    for c in 1..<channels {
                        sum += float[c][i]
                    }
                    sample = sum / Float(channels)
                }
                let clipped = max(-1.0, min(1.0, sample))
                mono[i] = Int16(clipped * Float(Int16.max))
            }
        } else {
            return
        }

        lock.lock()
        if isRecording {
            samples.append(contentsOf: mono)
        }
        lock.unlock()
    }

    private static func wavData(samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = samples.count * MemoryLayout<Int16>.size
        var data = Data()
        data.reserveCapacity(44 + dataSize)

        func appendASCII(_ s: String) { data.append(contentsOf: s.utf8) }
        func appendUInt16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(36 + dataSize))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(dataSize))
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
