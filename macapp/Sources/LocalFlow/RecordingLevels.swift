import Foundation
import Observation

/// Thread-safe RMS meter written from the audio tap.
final class AudioLevelMeter: @unchecked Sendable {
    static let shared = AudioLevelMeter()

    private let lock = NSLock()
    private var rawLevel: Float = 0

    func reset() {
        lock.lock()
        rawLevel = 0
        lock.unlock()
    }

    func pushRMS(_ rms: Float) {
        let boosted = min(1.0, pow(max(0, rms) * 3.2, 0.65))
        lock.lock()
        if boosted > rawLevel {
            rawLevel = rawLevel * 0.35 + boosted * 0.65
        } else {
            rawLevel = rawLevel * 0.82 + boosted * 0.18
        }
        lock.unlock()
    }

    func snapshot() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return rawLevel
    }
}

/// Live waveform bars for the recording indicator (MainActor / SwiftUI).
@MainActor
@Observable
final class RecordingLevels {
    static let shared = RecordingLevels()

    /// Newest bar on the right; smoothed RMS envelope.
    private(set) var bars: [CGFloat] = Array(repeating: 0.08, count: 20)
    private(set) var isActive = false

    private var displayLink: Timer?
    private var pendingLevel: CGFloat = 0

    func start() {
        isActive = true
        bars = Array(repeating: 0.08, count: bars.count)
        pendingLevel = 0
        AudioLevelMeter.shared.reset()

        displayLink?.invalidate()
        displayLink = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let displayLink {
            RunLoop.main.add(displayLink, forMode: .common)
        }
    }

    func stop() {
        isActive = false
        displayLink?.invalidate()
        displayLink = nil
        bars = Array(repeating: 0.08, count: bars.count)
        pendingLevel = 0
        AudioLevelMeter.shared.reset()
    }

    private func tick() {
        guard isActive else { return }
        let level = CGFloat(AudioLevelMeter.shared.snapshot())
        pendingLevel = pendingLevel * 0.45 + level * 0.55
        var next = bars
        next.removeFirst()
        let bar = max(0.06, min(1.0, pendingLevel))
        next.append(bar)
        bars = next
    }
}
