import XCTest
@testable import HermesWhisper02

final class VoiceSocketMessageProcessorTests: XCTestCase {
    func testPreludeThenBinaryEmitsPairedAudio() throws {
        var processor = VoiceSocketMessageProcessor()
        let prelude = makePrelude(bytes: 4)

        XCTAssertNil(try processor.handle(.audioChunk(prelude)))
        let (actualPrelude, data) = try processor.handleBinary(Data([0, 1, 2, 3]))

        XCTAssertEqual(actualPrelude, prelude)
        XCTAssertEqual(data, Data([0, 1, 2, 3]))
    }

    func testBinaryWithoutPreludeThrowsProtocolError() {
        var processor = VoiceSocketMessageProcessor()

        XCTAssertThrowsError(try processor.handleBinary(Data([0]))) { error in
            XCTAssertEqual(error as? ProtocolError, .binaryWithoutPrelude)
        }
    }

    func testByteCountMismatchThrowsProtocolError() throws {
        var processor = VoiceSocketMessageProcessor()
        _ = try processor.handle(.audioChunk(makePrelude(bytes: 4)))

        XCTAssertThrowsError(try processor.handleBinary(Data([0, 1]))) { error in
            XCTAssertEqual(error as? ProtocolError, .byteCountMismatch(expected: 4, actual: 2))
        }
    }

    func testDuplicateSequenceThrowsProtocolError() throws {
        var processor = VoiceSocketMessageProcessor()
        _ = try processor.handle(.audioChunk(makePrelude(seq: 0, bytes: 1)))
        _ = try processor.handleBinary(Data([0]))

        XCTAssertThrowsError(try processor.handle(.audioChunk(makePrelude(seq: 0, bytes: 1)))) { error in
            XCTAssertEqual(
                error as? ProtocolError,
                .duplicateOrOutOfOrderSequence(
                    turnID: "turn-1",
                    source: .ack,
                    expectedAtLeast: 1,
                    actual: 0
                )
            )
        }
    }

    func testOutOfOrderSequenceThrowsProtocolError() throws {
        var processor = VoiceSocketMessageProcessor()
        _ = try processor.handle(.audioChunk(makePrelude(seq: 2, bytes: 1)))
        _ = try processor.handleBinary(Data([0]))

        XCTAssertThrowsError(try processor.handle(.audioChunk(makePrelude(seq: 1, bytes: 1)))) { error in
            XCTAssertEqual(
                error as? ProtocolError,
                .duplicateOrOutOfOrderSequence(
                    turnID: "turn-1",
                    source: .ack,
                    expectedAtLeast: 3,
                    actual: 1
                )
            )
        }
    }

    private func makePrelude(seq: Int = 0, bytes: Int) -> AudioChunkPrelude {
        AudioChunkPrelude(
            turnID: "turn-1",
            seq: seq,
            format: .pcm16,
            sampleRate: 24_000,
            bytes: bytes,
            source: .ack
        )
    }
}
