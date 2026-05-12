import AVFoundation
import XCTest
@testable import HermesWhisper02

final class PlaybackActorTests: XCTestCase {
    func testPCM16BufferConversionUsesRequestedSampleRateAndFrameCount() throws {
        let samples: [Float] = [0, 0.5, -0.5, 1]
        let data = PCM16FrameProcessor.pcm16LittleEndianData(from: samples)

        let buffer = try PlaybackActor.makePCMBuffer(sampleRate: 24_000, pcm16: data)

        XCTAssertEqual(buffer.format.sampleRate, 24_000)
        XCTAssertEqual(buffer.format.channelCount, 1)
        XCTAssertEqual(buffer.frameLength, 4)
        XCTAssertEqual(buffer.floatChannelData?[0][0] ?? 99, 0, accuracy: 0.001)
        XCTAssertEqual(buffer.floatChannelData?[0][1] ?? 99, 0.5, accuracy: 0.001)
        XCTAssertEqual(buffer.floatChannelData?[0][2] ?? 99, -0.5, accuracy: 0.001)
    }

    func testFlushIgnoresStaleCompletion() async throws {
        let output = SpyPlaybackOutput()
        let playback = PlaybackActor(output: output)

        try await playback.enqueue(format: .pcm16, sampleRate: 24_000, pcm16: Self.audioData())
        var isPlaying = await playback.isPlaying
        XCTAssertTrue(isPlaying)

        await playback.flushAndStop()
        isPlaying = await playback.isPlaying
        XCTAssertFalse(isPlaying)

        output.complete(at: 0)
        isPlaying = await playback.isPlaying
        XCTAssertFalse(isPlaying)
        XCTAssertEqual(output.flushCount, 1)
    }

    func testRapidEnqueueFlushInterleavingsStayStoppedAfterFinalFlush() async throws {
        let output = SpyPlaybackOutput()
        let playback = PlaybackActor(output: output)

        for _ in 0..<10 {
            try await playback.enqueue(format: .pcm16, sampleRate: 24_000, pcm16: Self.audioData())
            await playback.flushAndStop()
        }

        output.completeAll()
        let isPlaying = await playback.isPlaying
        XCTAssertFalse(isPlaying)
        XCTAssertEqual(output.enqueuedBuffers.count, 10)
        XCTAssertEqual(output.flushCount, 10)
    }

    private static func audioData() -> Data {
        PCM16FrameProcessor.pcm16LittleEndianData(from: Array(repeating: Float(0.1), count: 320))
    }
}

private final class SpyPlaybackOutput: PlaybackOutput {
    private(set) var preparedFormats: [(Double, AVAudioChannelCount)] = []
    private(set) var enqueuedBuffers: [AVAudioPCMBuffer] = []
    private(set) var flushCount = 0
    private var completions: [@Sendable () -> Void] = []

    func prepareIfNeeded(sampleRate: Double, channels: AVAudioChannelCount) throws {
        preparedFormats.append((sampleRate, channels))
    }

    func enqueue(_ buffer: AVAudioPCMBuffer, completion: @escaping @Sendable () -> Void) {
        enqueuedBuffers.append(buffer)
        completions.append(completion)
    }

    func flushAndStop() {
        flushCount += 1
    }

    func complete(at index: Int) {
        completions[index]()
    }

    func completeAll() {
        completions.forEach { $0() }
    }
}
