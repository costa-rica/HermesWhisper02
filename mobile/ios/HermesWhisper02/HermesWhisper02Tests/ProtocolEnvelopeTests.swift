import XCTest
@testable import HermesWhisper02

final class ProtocolEnvelopeTests: XCTestCase {
    func testClientHelloEncodesSnakeCaseTypeAndPayload() throws {
        let payload = try ProtocolEnvelope.encode(.clientHello(ClientHelloFrame(
            sessionID: "prior-session",
            pttMode: false,
            intermediaryMode: .deterministic,
            audioParams: RuntimeAudioParams(
                speechRmsThreshold: 0.004,
                endSilenceSeconds: 1.2,
                minTurnSeconds: 0.7,
                maxTurnSeconds: 12.0
            )
        )))

        XCTAssertTrue(payload.contains("\"type\":\"client_hello\""))
        XCTAssertTrue(payload.contains("\"protocol_version\":1"))
        XCTAssertTrue(payload.contains("\"session_id\":\"prior-session\""))
        XCTAssertTrue(payload.contains("\"downlink_format\":\"pcm16\""))
        XCTAssertTrue(payload.contains("\"sample_rate\":16000"))
        XCTAssertTrue(payload.contains("\"ptt_mode\":false"))
        XCTAssertTrue(payload.contains("\"intermediary_mode\":\"deterministic\""))
        XCTAssertTrue(payload.contains("\"speech_rms_threshold\":0.004"))
        XCTAssertTrue(payload.contains("\"end_silence_seconds\":1.2"))
    }

    func testRuntimeConfigFramesEncodeSnakeCasePayloads() throws {
        let modePayload = try ProtocolEnvelope.encode(.setIntermediaryMode(SetIntermediaryModeFrame(mode: .llm)))
        let audioPayload = try ProtocolEnvelope.encode(.setAudioParams(SetAudioParamsFrame(
            speechRmsThreshold: 0.005,
            endSilenceSeconds: 1.4
        )))

        XCTAssertTrue(modePayload.contains("\"type\":\"set_intermediary_mode\""))
        XCTAssertTrue(modePayload.contains("\"mode\":\"llm\""))
        XCTAssertTrue(audioPayload.contains("\"type\":\"set_audio_params\""))
        XCTAssertTrue(audioPayload.contains("\"speech_rms_threshold\":0.005"))
        XCTAssertTrue(audioPayload.contains("\"end_silence_seconds\":1.4"))
    }

    func testDecodesEveryServerFrameType() throws {
        let cases: [(String, ServerFrame)] = [
            (
                """
                {"type":"session_started","session_id":"s1","conversation_id":"c1","downlink_format":"pcm16","sample_rate":24000,"front_llm":"openai:gpt-4o-mini","resumed":false,"created":true}
                """,
                .sessionStarted(SessionStartedFrame(
                    sessionID: "s1",
                    conversationID: "c1",
                    downlinkFormat: .pcm16,
                    sampleRate: 24_000,
                    frontLLM: "openai:gpt-4o-mini",
                    resumed: false,
                    created: true
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
                #"{"type":"assistant_text","turn_id":"t1","text":"hi there","final":true,"ts":12.75}"#,
                .assistantText(AssistantTextFrame(turnID: "t1", text: "hi there", final: true, ts: 12.75))
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
                #"{"type":"runtime_config_applied","fields":["speech_rms_threshold"],"values":{"speech_rms_threshold":0.005}}"#,
                .runtimeConfigApplied(RuntimeConfigAppliedFrame(
                    fields: ["speech_rms_threshold"],
                    values: RuntimeAudioParams(speechRmsThreshold: 0.005)
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
                resumed: true,
                created: false
            )),
            .userStartedSpeaking(SpeechBoundaryFrame(type: SpeechBoundaryFrame.startedType, ts: 12.5)),
            .userStoppedSpeaking(SpeechBoundaryFrame(type: SpeechBoundaryFrame.stoppedType, ts: 13.5)),
            .transcript(TranscriptFrame(turnID: "t1", text: "hello", isFinal: true)),
            .assistantText(AssistantTextFrame(turnID: "t1", text: "hi there", final: true, ts: 12.75)),
            .assistantState(AssistantStateFrame(state: .answer)),
            .hermesProgress(HermesProgressFrame(
                turnID: "t1",
                kind: .finished,
                text: "Hermes finished.",
                ts: 12.75
            )),
            .runtimeConfigApplied(RuntimeConfigAppliedFrame(
                fields: ["end_silence_seconds"],
                values: RuntimeAudioParams(endSilenceSeconds: 1.4)
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
