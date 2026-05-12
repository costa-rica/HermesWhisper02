import AVFoundation
import XCTest
@testable import HermesWhisper02

final class AudioCaptureFormatTests: XCTestCase {
    func testConvertsFloatBufferToSixteenKilohertzPCM16Frames() throws {
        let inputSampleRate = 48_000.0
        let inputFrameCount = AVAudioFrameCount(4_992)
        let inputFormat = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: false
        ))
        let inputBuffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: inputFrameCount
        ))
        inputBuffer.frameLength = inputFrameCount

        let channel = try XCTUnwrap(inputBuffer.floatChannelData?[0])
        for index in 0..<Int(inputFrameCount) {
            let time = Double(index) / inputSampleRate
            channel[index] = Float(sin(2 * Double.pi * 440 * time) * 0.5)
        }

        var processor = try PCM16FrameProcessor(inputFormat: inputFormat)
        let chunks = try processor.append(inputBuffer)

        XCTAssertEqual(chunks.count, 4)
        XCTAssertTrue(chunks.allSatisfy { $0.count == AudioCapture.bytesPerFrame })
        XCTAssertGreaterThan(AudioCapture.rms(forPCM16Frame: chunks[0]), 0.1)
    }

    func testPCM16ConversionClampsAndUsesLittleEndianSamples() {
        let data = PCM16FrameProcessor.pcm16LittleEndianData(from: [-2, 0.5, 2])

        var samples: [Int16] = []
        data.withUnsafeBytes { rawBuffer in
            for sample in rawBuffer.bindMemory(to: Int16.self) {
                samples.append(Int16(littleEndian: sample))
            }
        }

        XCTAssertEqual(samples[0], Int16.min + 1)
        XCTAssertEqual(samples[1], 16_383)
        XCTAssertEqual(samples[2], Int16.max)
    }
}
