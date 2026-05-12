import XCTest
@testable import HermesWhisper02

final class BargeInDetectorTests: XCTestCase {
    func testFiresWithinOneHundredMillisecondsOfSyntheticSpeechOnset() {
        var detector = BargeInDetector(config: .init(
            sampleRate: 16_000,
            windowDuration: 0.05,
            rmsThreshold: 0.02,
            requiredConsecutiveWindows: 2
        ))
        var firedAtFrame: Int?

        for index in 0..<5 {
            detector.process(frame: Self.pcm16Frame(amplitude: 0.08), playbackActive: true) {
                firedAtFrame = index
            }
        }

        XCTAssertNotNil(firedAtFrame)
        XCTAssertLessThanOrEqual(Double((firedAtFrame ?? 99) + 1) * 0.02, 0.10)
    }

    func testDoesNotFireWhilePlaybackIsInactive() {
        var detector = BargeInDetector(config: .init(
            sampleRate: 16_000,
            windowDuration: 0.05,
            rmsThreshold: 0.02,
            requiredConsecutiveWindows: 2
        ))
        var fired = false

        for _ in 0..<8 {
            detector.process(frame: Self.pcm16Frame(amplitude: 0.15), playbackActive: false) {
                fired = true
            }
        }

        XCTAssertFalse(fired)
    }

    private static func pcm16Frame(amplitude: Float) -> Data {
        PCM16FrameProcessor.pcm16LittleEndianData(
            from: Array(repeating: amplitude, count: AudioCapture.samplesPerFrame)
        )
    }
}
