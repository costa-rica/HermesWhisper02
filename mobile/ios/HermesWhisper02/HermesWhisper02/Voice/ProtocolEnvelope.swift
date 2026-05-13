import Foundation

enum ProtocolEnvelope {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    static func encode(_ frame: ClientFrame) throws -> String {
        let data = try encoder.encode(frame)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw ProtocolError.invalidUTF8Payload
        }
        return payload
    }

    static func decodeServerFrame(from text: String) throws -> ServerFrame {
        guard let data = text.data(using: .utf8) else {
            throw ProtocolError.invalidUTF8Payload
        }
        return try decoder.decode(ServerFrame.self, from: data)
    }
}

enum ProtocolError: Error, Equatable {
    case invalidUTF8Payload
    case unknownFrameType(String)
    case binaryWithoutPrelude
    case byteCountMismatch(expected: Int, actual: Int)
    case duplicateOrOutOfOrderSequence(turnID: String, source: AudioSource, expectedAtLeast: Int, actual: Int)
    case pendingPreludeReplaced
}

enum AudioFormat: String, Codable, Equatable {
    case pcm16
    case opus
}

enum AudioSource: String, Codable, Equatable, Hashable {
    case ack
    case answer
}

enum ClientFrame: Codable, Equatable {
    case clientHello(ClientHelloFrame)
    case cancelTurn(CancelTurnFrame)
    case ping(PingFrame)
    case clientBye(ClientByeFrame)

    private enum CodingKeys: String, CodingKey {
        case type
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .clientHello(let frame):
            try frame.encode(to: encoder)
        case .cancelTurn(let frame):
            try frame.encode(to: encoder)
        case .ping(let frame):
            try frame.encode(to: encoder)
        case .clientBye(let frame):
            try frame.encode(to: encoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case ClientHelloFrame.type:
            self = .clientHello(try ClientHelloFrame(from: decoder))
        case CancelTurnFrame.type:
            self = .cancelTurn(try CancelTurnFrame(from: decoder))
        case PingFrame.type:
            self = .ping(try PingFrame(from: decoder))
        case ClientByeFrame.type:
            self = .clientBye(try ClientByeFrame(from: decoder))
        default:
            throw ProtocolError.unknownFrameType(type)
        }
    }
}

struct ClientHelloFrame: Codable, Equatable {
    static let type = "client_hello"

    var protocolVersion: Int = ProtocolVersion.current
    var sessionID: String?
    var downlinkFormat: AudioFormat = .pcm16
    var sampleRate: Int = Int(AudioCapture.targetSampleRate)
    var pttMode: Bool

    private enum CodingKeys: String, CodingKey {
        case type
        case protocolVersion
        case sessionID = "sessionId"
        case downlinkFormat
        case sampleRate
        case pttMode
    }

    init(
        protocolVersion: Int = ProtocolVersion.current,
        sessionID: String? = nil,
        downlinkFormat: AudioFormat = .pcm16,
        sampleRate: Int = Int(AudioCapture.targetSampleRate),
        pttMode: Bool
    ) {
        self.protocolVersion = protocolVersion
        self.sessionID = sessionID
        self.downlinkFormat = downlinkFormat
        self.sampleRate = sampleRate
        self.pttMode = pttMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decode(Int.self, forKey: .protocolVersion)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        downlinkFormat = try container.decode(AudioFormat.self, forKey: .downlinkFormat)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        pttMode = try container.decode(Bool.self, forKey: .pttMode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
        try container.encode(downlinkFormat, forKey: .downlinkFormat)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(pttMode, forKey: .pttMode)
    }
}

struct CancelTurnFrame: Codable, Equatable {
    static let type = "cancel_turn"

    var turnID: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turnId"
    }

    init(turnID: String? = nil) {
        self.turnID = turnID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnID = try container.decodeIfPresent(String.self, forKey: .turnID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encodeIfPresent(turnID, forKey: .turnID)
    }
}

struct PingFrame: Codable, Equatable {
    static let type = "ping"

    var ts: Double

    private enum CodingKeys: String, CodingKey {
        case type
        case ts
    }

    init(ts: Double) {
        self.ts = ts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ts = try container.decode(Double.self, forKey: .ts)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(ts, forKey: .ts)
    }
}

struct ClientByeFrame: Codable, Equatable {
    static let type = "client_bye"

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init() {}

    init(from decoder: Decoder) throws {
        _ = try decoder.container(keyedBy: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
    }
}

enum ServerFrame: Codable, Equatable {
    case sessionStarted(SessionStartedFrame)
    case userStartedSpeaking(SpeechBoundaryFrame)
    case userStoppedSpeaking(SpeechBoundaryFrame)
    case transcript(TranscriptFrame)
    case assistantText(AssistantTextFrame)
    case assistantState(AssistantStateFrame)
    case hermesProgress(HermesProgressFrame)
    case audioChunk(AudioChunkPrelude)
    case turnEnd(TurnEndFrame)
    case pong(PongFrame)
    case error(ErrorEnvelope)

    private enum CodingKeys: String, CodingKey {
        case type
        case error
    }

    init(from decoder: Decoder) throws {
        if let envelope = try? ErrorEnvelope(from: decoder) {
            self = .error(envelope)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case SessionStartedFrame.type:
            self = .sessionStarted(try SessionStartedFrame(from: decoder))
        case SpeechBoundaryFrame.startedType:
            self = .userStartedSpeaking(try SpeechBoundaryFrame(from: decoder))
        case SpeechBoundaryFrame.stoppedType:
            self = .userStoppedSpeaking(try SpeechBoundaryFrame(from: decoder))
        case TranscriptFrame.type:
            self = .transcript(try TranscriptFrame(from: decoder))
        case AssistantTextFrame.type:
            self = .assistantText(try AssistantTextFrame(from: decoder))
        case AssistantStateFrame.type:
            self = .assistantState(try AssistantStateFrame(from: decoder))
        case HermesProgressFrame.type:
            self = .hermesProgress(try HermesProgressFrame(from: decoder))
        case AudioChunkPrelude.type:
            self = .audioChunk(try AudioChunkPrelude(from: decoder))
        case TurnEndFrame.type:
            self = .turnEnd(try TurnEndFrame(from: decoder))
        case PongFrame.type:
            self = .pong(try PongFrame(from: decoder))
        default:
            throw ProtocolError.unknownFrameType(type)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .sessionStarted(let frame):
            try frame.encode(to: encoder)
        case .userStartedSpeaking(let frame):
            try frame.encode(to: encoder)
        case .userStoppedSpeaking(let frame):
            try frame.encode(to: encoder)
        case .transcript(let frame):
            try frame.encode(to: encoder)
        case .assistantText(let frame):
            try frame.encode(to: encoder)
        case .assistantState(let frame):
            try frame.encode(to: encoder)
        case .hermesProgress(let frame):
            try frame.encode(to: encoder)
        case .audioChunk(let frame):
            try frame.encode(to: encoder)
        case .turnEnd(let frame):
            try frame.encode(to: encoder)
        case .pong(let frame):
            try frame.encode(to: encoder)
        case .error(let envelope):
            try envelope.encode(to: encoder)
        }
    }
}

struct SessionStartedFrame: Codable, Equatable {
    static let type = "session_started"

    var sessionID: String
    var conversationID: String
    var downlinkFormat: AudioFormat
    var sampleRate: Int
    var frontLLM: String
    var resumed: Bool
    var created: Bool?

    private enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "sessionId"
        case conversationID = "conversationId"
        case downlinkFormat
        case sampleRate
        case frontLLM = "frontLlm"
        case resumed
        case created
    }

    init(
        sessionID: String,
        conversationID: String,
        downlinkFormat: AudioFormat,
        sampleRate: Int,
        frontLLM: String,
        resumed: Bool,
        created: Bool? = nil
    ) {
        self.sessionID = sessionID
        self.conversationID = conversationID
        self.downlinkFormat = downlinkFormat
        self.sampleRate = sampleRate
        self.frontLLM = frontLLM
        self.resumed = resumed
        self.created = created
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        conversationID = try container.decode(String.self, forKey: .conversationID)
        downlinkFormat = try container.decode(AudioFormat.self, forKey: .downlinkFormat)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        frontLLM = try container.decode(String.self, forKey: .frontLLM)
        resumed = try container.decode(Bool.self, forKey: .resumed)
        created = try container.decodeIfPresent(Bool.self, forKey: .created)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(conversationID, forKey: .conversationID)
        try container.encode(downlinkFormat, forKey: .downlinkFormat)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(frontLLM, forKey: .frontLLM)
        try container.encode(resumed, forKey: .resumed)
        try container.encodeIfPresent(created, forKey: .created)
    }
}

struct SpeechBoundaryFrame: Codable, Equatable {
    static let startedType = "user_started_speaking"
    static let stoppedType = "user_stopped_speaking"

    var type: String
    var ts: Double

    private enum CodingKeys: String, CodingKey {
        case type
        case ts
    }

    init(type: String = Self.startedType, ts: Double) {
        self.type = type
        self.ts = ts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        ts = try container.decode(Double.self, forKey: .ts)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(ts, forKey: .ts)
    }
}

struct TranscriptFrame: Codable, Equatable {
    static let type = "transcript"

    var turnID: String
    var text: String
    var isFinal: Bool

    private enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turnId"
        case text
        case isFinal
    }

    init(turnID: String, text: String, isFinal: Bool) {
        self.turnID = turnID
        self.text = text
        self.isFinal = isFinal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnID = try container.decode(String.self, forKey: .turnID)
        text = try container.decode(String.self, forKey: .text)
        isFinal = try container.decode(Bool.self, forKey: .isFinal)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(text, forKey: .text)
        try container.encode(isFinal, forKey: .isFinal)
    }
}

struct AssistantTextFrame: Codable, Equatable {
    static let type = "assistant_text"

    var turnID: String
    var text: String
    var final: Bool
    var ts: Double

    private enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turnId"
        case text
        case final
        case ts
    }

    init(turnID: String, text: String, final: Bool, ts: Double) {
        self.turnID = turnID
        self.text = text
        self.final = final
        self.ts = ts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnID = try container.decode(String.self, forKey: .turnID)
        text = try container.decode(String.self, forKey: .text)
        final = try container.decode(Bool.self, forKey: .final)
        ts = try container.decode(Double.self, forKey: .ts)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(text, forKey: .text)
        try container.encode(final, forKey: .final)
        try container.encode(ts, forKey: .ts)
    }
}

struct AssistantStateFrame: Codable, Equatable {
    static let type = "assistant_state"

    var state: AssistantState

    private enum CodingKeys: String, CodingKey {
        case type
        case state
    }

    init(state: AssistantState) {
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(AssistantState.self, forKey: .state)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(state, forKey: .state)
    }
}

enum HermesProgressKind: String, Codable, Equatable {
    case sentToHermes = "sent_to_hermes"
    case responseStarted = "response_started"
    case toolCall = "tool_call"
    case toolResult = "tool_result"
    case preparingAudio = "preparing_audio"
    case audioReady = "audio_ready"
    case finished
    case failed
}

struct HermesProgressFrame: Codable, Equatable {
    static let type = "hermes_progress"

    var turnID: String
    var kind: HermesProgressKind
    var text: String
    var ts: Double

    private enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turnId"
        case kind
        case text
        case ts
    }

    init(turnID: String, kind: HermesProgressKind, text: String, ts: Double) {
        self.turnID = turnID
        self.kind = kind
        self.text = text
        self.ts = ts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnID = try container.decode(String.self, forKey: .turnID)
        kind = try container.decode(HermesProgressKind.self, forKey: .kind)
        text = try container.decode(String.self, forKey: .text)
        ts = try container.decode(Double.self, forKey: .ts)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(kind, forKey: .kind)
        try container.encode(text, forKey: .text)
        try container.encode(ts, forKey: .ts)
    }
}

struct AudioChunkPrelude: Codable, Equatable {
    static let type = "audio_chunk"

    var turnID: String
    var seq: Int
    var format: AudioFormat
    var sampleRate: Int
    var bytes: Int
    var source: AudioSource

    private enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turnId"
        case seq
        case format
        case sampleRate
        case bytes
        case source
    }

    init(
        turnID: String,
        seq: Int,
        format: AudioFormat,
        sampleRate: Int,
        bytes: Int,
        source: AudioSource
    ) {
        self.turnID = turnID
        self.seq = seq
        self.format = format
        self.sampleRate = sampleRate
        self.bytes = bytes
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnID = try container.decode(String.self, forKey: .turnID)
        seq = try container.decode(Int.self, forKey: .seq)
        format = try container.decode(AudioFormat.self, forKey: .format)
        sampleRate = try container.decode(Int.self, forKey: .sampleRate)
        bytes = try container.decode(Int.self, forKey: .bytes)
        source = try container.decode(AudioSource.self, forKey: .source)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(turnID, forKey: .turnID)
        try container.encode(seq, forKey: .seq)
        try container.encode(format, forKey: .format)
        try container.encode(sampleRate, forKey: .sampleRate)
        try container.encode(bytes, forKey: .bytes)
        try container.encode(source, forKey: .source)
    }
}

struct TurnEndFrame: Codable, Equatable {
    static let type = "turn_end"

    var turnID: String
    var canceled: Bool?

    private enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turnId"
        case canceled
    }

    init(turnID: String, canceled: Bool? = nil) {
        self.turnID = turnID
        self.canceled = canceled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnID = try container.decode(String.self, forKey: .turnID)
        canceled = try container.decodeIfPresent(Bool.self, forKey: .canceled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(turnID, forKey: .turnID)
        try container.encodeIfPresent(canceled, forKey: .canceled)
    }
}

struct PongFrame: Codable, Equatable {
    static let type = "pong"

    var ts: Double

    private enum CodingKeys: String, CodingKey {
        case type
        case ts
    }

    init(ts: Double) {
        self.ts = ts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ts = try container.decode(Double.self, forKey: .ts)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.type, forKey: .type)
        try container.encode(ts, forKey: .ts)
    }
}
