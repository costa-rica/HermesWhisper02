import Foundation

struct BargeInDetector {
    struct Config {
        var sampleRate: Double = AudioCapture.targetSampleRate
        var windowDuration: TimeInterval = 0.05
        var rmsThreshold: Double = 0.025
        var requiredConsecutiveWindows = 2
    }

    private let config: Config
    private var accumulatedSquares = 0.0
    private var accumulatedSamples = 0
    private var consecutiveLoudWindows = 0
    private var hasFiredForCurrentPlayback = false

    init(config: Config = Config()) {
        self.config = config
    }

    mutating func reset() {
        accumulatedSquares = 0
        accumulatedSamples = 0
        consecutiveLoudWindows = 0
        hasFiredForCurrentPlayback = false
    }

    mutating func process(frame: Data, playbackActive: Bool, onLikelySpeech: () -> Void) {
        guard playbackActive else {
            reset()
            return
        }
        guard !hasFiredForCurrentPlayback else {
            return
        }

        frame.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            let targetSamples = max(1, Int(config.sampleRate * config.windowDuration))
            for sample in samples {
                let normalized = Double(Int16(littleEndian: sample)) / Double(Int16.max)
                accumulatedSquares += normalized * normalized
                accumulatedSamples += 1

                if accumulatedSamples >= targetSamples {
                    evaluateWindow()
                    if hasFiredForCurrentPlayback {
                        return
                    }
                }
            }
        }
        if hasFiredForCurrentPlayback {
            onLikelySpeech()
        }
    }

    private mutating func evaluateWindow() {
        let rms = sqrt(accumulatedSquares / Double(accumulatedSamples))
        if rms >= config.rmsThreshold {
            consecutiveLoudWindows += 1
        } else {
            consecutiveLoudWindows = 0
        }

        accumulatedSquares = 0
        accumulatedSamples = 0

        if consecutiveLoudWindows >= config.requiredConsecutiveWindows {
            hasFiredForCurrentPlayback = true
        }
    }
}
