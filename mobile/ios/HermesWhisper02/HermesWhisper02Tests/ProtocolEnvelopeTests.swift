import XCTest
@testable import HermesWhisper02

final class ProtocolEnvelopeTests: XCTestCase {
    func testClientHelloEncodesSnakeCaseTypeAndPayload() throws {
        let payload = try ProtocolEnvelope.encode(.clientHello(ClientHelloFrame(
            sessionID: "prior-session",
            pttMode: false
        )))

        XCTAssertTrue(payload.contains("\"type\":\"client_hello\""))
        XCTAssertTrue(payload.contains("\"protocol_version\":1"))
        XCTAssertTrue(payload.contains("\"session_id\":\"prior-session\""))
        XCTAssertTrue(payload.contains("\"downlink_format\":\"pcm16\""))
        XCTAssertTrue(payload.contains("\"sample_rate\":16000"))
        XCTAssertTrue(payload.contains("\"ptt_mode\":false"))
    }

    func testDecodesEveryServerFrameType() throws {
        let cases: [(String, ServerFrame)] = [
            (
                """
                {"type":"session_started","session_id":"s1","conversation_id":"c1","downlink_format":"pcm16","sample_rate":24000,"front_llm":"openai:gpt-4o-mini","resumed":false}
                """,
                .sessionStarted(SessionStartedFrame(
                    sessionID: "s1",
                    conversationID: "c1",
                    downlinkFormat: .pcm16,
                    sampleRate: 24_000,
                    frontLLM: "openai:gpt-4o-mini",
                    resumed: false
                ))
            ),
            (
                #"{"type":"user_started_speaking","ts":12.5}"#,
                .userStartedSpeaking(SpeechBoundaryFrame(type: SpeechBoundaryFrame.startedType, ts: 12.5))
            ),
            (
                #"{"type":"user_stopped_speaking","ts":13.5}"#,
                .userStoppedSpeaking(SpeechBoundaryFrame(type: SpeechBoundaryFrame.stoppedType, ts: 13.5))
            ),
            (
                #"{"type":"transcript","turn_id":"t1","text":"hello","is_final":true}"#,
                .transcript(TranscriptFrame(turnID: "t1", text: "hello", isFinal: true))
            ),
            (
                #"{"type":"assistant_state","state":"answer"}"#,
                .assistantState(AssistantStateFrame(state: .answer))
            ),
            (
                #"{"type":"hermes_progress","turn_id":"t1","kind":"preparing_audio","text":"Preparing spoken response.","ts":12.25}"#,
                .hermesProgress(HermesProgressFrame(
                    turnID: "t1",
                    kind: .preparingAudio,
                    text: "Preparing spoken response.",
                    ts: 12.25
                ))
            ),
            (
                #"{"type":"audio_chunk","turn_id":"t1","seq":0,"format":"pcm16","sample_rate":24000,"bytes":4,"source":"ack"}"#,
                .audioChunk(AudioChunkPrelude(
                    turnID: "t1",
                    seq: 0,
                    format: .pcm16,
                    sampleRate: 24_000,
                    bytes: 4,
                    source: .ack
                ))
            ),
            (
                #"{"type":"turn_end","turn_id":"t1","canceled":true}"#,
                .turnEnd(TurnEndFrame(turnID: "t1", canceled: true))
            ),
            (
                #"{"type":"pong","ts":99.25}"#,
                .pong(PongFrame(ts: 99.25))
            ),
            (
                #"{"error":{"code":"AUTH_FAILED","message":"Nope","status":401,"details":null}}"#,
                .error(ErrorEnvelope(error: .init(
                    code: "AUTH_FAILED",
                    message: "Nope",
                    status: 401,
                    details: nil
                )))
            )
        ]

        for (payload, expected) in cases {
            XCTAssertEqual(try ProtocolEnvelope.decodeServerFrame(from: payload), expected)
        }
    }

    func testRoundTripsEveryServerFrameType() throws {
        let cases: [ServerFrame] = [
            .sessionStarted(SessionStartedFrame(
                sessionID: "s1",
                conversationID: "c1",
                downlinkFormat: .pcm16,
                sampleRate: 24_000,
                frontLLM: "openai:gpt-4o-mini",
                resumed: true
            )),
            .userStartedSpeaking(SpeechBoundaryFrame(type: SpeechBoundaryFrame.startedType, ts: 12.5)),
            .userStoppedSpeaking(SpeechBoundaryFrame(type: SpeechBoundaryFrame.stoppedType, ts: 13.5)),
            .transcript(TranscriptFrame(turnID: "t1", text: "hello", isFinal: true)),
            .assistantState(AssistantStateFrame(state: .answer)),
            .hermesProgress(HermesProgressFrame(
                turnID: "t1",
                kind: .finished,
                text: "Hermes finished.",
                ts: 12.75
            )),
            .audioChunk(AudioChunkPrelude(
                turnID: "t1",
                seq: 0,
                format: .pcm16,
                sampleRate: 24_000,
                bytes: 4,
                source: .ack
            )),
            .turnEnd(TurnEndFrame(turnID: "t1", canceled: true)),
            .pong(PongFrame(ts: 99.25)),
            .error(ErrorEnvelope(error: .init(
                code: "AUTH_FAILED",
                message: "Nope",
                status: 401,
                details: nil
            )))
        ]

        for frame in cases {
            let data = try ProtocolEnvelope.encoder.encode(frame)
            let payload = try XCTUnwrap(String(data: data, encoding: .utf8))
            XCTAssertEqual(try ProtocolEnvelope.decodeServerFrame(from: payload), frame)
        }
    }
}
