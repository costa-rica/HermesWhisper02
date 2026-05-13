import Combine
import Foundation
import SQLite3

final class ConversationStore: ObservableObject {
    enum StoreError: Error, Equatable {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
        case invalidRow
    }

    @Published private(set) var changeToken = UUID()

    let serverProfileID: UUID
    let databaseURL: URL

    private var db: OpaquePointer?
    private let fileManager: FileManager

    init(
        serverProfileID: UUID,
        fileManager: FileManager = .default,
        applicationSupportURL: URL? = nil,
        databaseURL: URL? = nil
    ) throws {
        self.serverProfileID = serverProfileID
        self.fileManager = fileManager

        if let databaseURL {
            self.databaseURL = databaseURL
        } else {
            let rootURL = try applicationSupportURL ?? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.databaseURL = rootURL
                .appendingPathComponent("HermesWhisper02", isDirectory: true)
                .appendingPathComponent("conversations", isDirectory: true)
                .appendingPathComponent("\(serverProfileID.uuidString).sqlite", isDirectory: false)
        }

        try fileManager.createDirectory(
            at: self.databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try open()
        try execute("PRAGMA foreign_keys = ON")
        try bootstrap()
    }

    deinit {
        sqlite3_close(db)
    }

    @discardableResult
    func upsertSession(
        id: String,
        hermesConversationID: String,
        title: String?
    ) throws -> ConversationSession {
        let now = Date()
        try run(
            """
            INSERT INTO voice_sessions (
                id, server_profile_id, hermes_conversation_id, title,
                created_at, updated_at, last_message_preview, message_count, archived_at
            )
            VALUES (?, ?, ?, ?, ?, ?, NULL, 0, NULL)
            ON CONFLICT(id) DO UPDATE SET
                hermes_conversation_id = excluded.hermes_conversation_id,
                title = COALESCE(excluded.title, voice_sessions.title),
                updated_at = excluded.updated_at
            """,
            [
                id,
                serverProfileID.uuidString,
                hermesConversationID,
                title,
                Self.string(from: now),
                Self.string(from: now)
            ]
        )
        signalChange()
        return try loadSession(id: id)
    }

    @discardableResult
    func appendMessage(
        sessionID: String,
        turnID: String?,
        role: ConversationMessage.Role,
        text: String,
        final: Bool,
        metadata: String
    ) throws -> ConversationMessage {
        let now = Date()
        let message = ConversationMessage(
            id: UUID().uuidString,
            sessionID: sessionID,
            turnID: turnID,
            role: role,
            text: text,
            final: final,
            createdAt: now,
            metadata: metadata
        )
        try run(
            """
            INSERT INTO voice_messages (
                id, session_id, turn_id, role, text, final, created_at, metadata
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                message.id,
                message.sessionID,
                message.turnID,
                message.role.rawValue,
                message.text,
                message.final ? 1 : 0,
                Self.string(from: message.createdAt),
                message.metadata
            ]
        )
        try run(
            """
            UPDATE voice_sessions
            SET updated_at = ?, last_message_preview = ?, message_count = message_count + 1
            WHERE id = ? AND server_profile_id = ?
            """,
            [Self.string(from: now), text, sessionID, serverProfileID.uuidString]
        )
        signalChange()
        return message
    }

    func listSessions(includeArchived: Bool = false) throws -> [ConversationSession] {
        let archivedFilter = includeArchived ? "" : "AND archived_at IS NULL"
        return try querySessions(
            """
            SELECT id, server_profile_id, hermes_conversation_id, title, created_at, updated_at,
                   last_message_preview, message_count, archived_at
            FROM voice_sessions
            WHERE server_profile_id = ? \(archivedFilter)
            ORDER BY updated_at DESC, id ASC
            """,
            [serverProfileID.uuidString]
        )
    }

    func loadMessages(sessionID: String) throws -> [ConversationMessage] {
        try queryMessages(
            """
            SELECT id, session_id, turn_id, role, text, final, created_at, metadata
            FROM voice_messages
            WHERE session_id = ?
            ORDER BY created_at ASC, id ASC
            """,
            [sessionID]
        )
    }

    func deleteSession(sessionID: String) throws {
        try run("DELETE FROM voice_messages WHERE session_id = ?", [sessionID])
        try run(
            "DELETE FROM voice_sessions WHERE id = ? AND server_profile_id = ?",
            [sessionID, serverProfileID.uuidString]
        )
        signalChange()
    }

    func updateSessionPreview(
        sessionID: String,
        preview: String?,
        lastUpdated: Date
    ) throws {
        try run(
            """
            UPDATE voice_sessions
            SET last_message_preview = ?, updated_at = ?
            WHERE id = ? AND server_profile_id = ?
            """,
            [preview, Self.string(from: lastUpdated), sessionID, serverProfileID.uuidString]
        )
        signalChange()
    }

    private func open() throws {
        if sqlite3_open(databaseURL.path, &db) != SQLITE_OK {
            throw StoreError.openFailed(lastErrorMessage)
        }
    }

    private func bootstrap() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS voice_sessions (
                id TEXT PRIMARY KEY,
                server_profile_id TEXT NOT NULL,
                hermes_conversation_id TEXT NOT NULL,
                title TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                last_message_preview TEXT,
                message_count INTEGER NOT NULL DEFAULT 0,
                archived_at TEXT
            );
            CREATE INDEX IF NOT EXISTS idx_voice_sessions_updated
                ON voice_sessions(archived_at, updated_at DESC);
            CREATE TABLE IF NOT EXISTS voice_messages (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                turn_id TEXT,
                role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
                text TEXT NOT NULL,
                final INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                metadata TEXT NOT NULL DEFAULT '{}',
                FOREIGN KEY(session_id) REFERENCES voice_sessions(id)
            );
            CREATE INDEX IF NOT EXISTS idx_voice_messages_session_created
                ON voice_messages(session_id, created_at ASC);
            """
        )
    }

    private func loadSession(id: String) throws -> ConversationSession {
        let sessions = try querySessions(
            """
            SELECT id, server_profile_id, hermes_conversation_id, title, created_at, updated_at,
                   last_message_preview, message_count, archived_at
            FROM voice_sessions
            WHERE id = ? AND server_profile_id = ?
            LIMIT 1
            """,
            [id, serverProfileID.uuidString]
        )
        guard let session = sessions.first else {
            throw StoreError.invalidRow
        }
        return session
    }

    private func querySessions(_ sql: String, _ values: [Any?]) throws -> [ConversationSession] {
        try withStatement(sql, values) { statement in
            var sessions: [ConversationSession] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                sessions.append(try Self.session(from: statement))
            }
            return sessions
        }
    }

    private func queryMessages(_ sql: String, _ values: [Any?]) throws -> [ConversationMessage] {
        try withStatement(sql, values) { statement in
            var messages: [ConversationMessage] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                messages.append(try Self.message(from: statement))
            }
            return messages
        }
    }

    private func execute(_ sql: String) throws {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            throw StoreError.stepFailed(lastErrorMessage)
        }
    }

    private func run(_ sql: String, _ values: [Any?]) throws {
        try withStatement(sql, values) { statement in
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw StoreError.stepFailed(lastErrorMessage)
            }
        }
    }

    private func withStatement<T>(
        _ sql: String,
        _ values: [Any?],
        body: (OpaquePointer) throws -> T
    ) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw StoreError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        return try body(statement)
    }

    private func bind(_ values: [Any?], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case nil:
                sqlite3_bind_null(statement, index)
            case let value as String:
                sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
            case let value as Int:
                sqlite3_bind_int64(statement, index, sqlite3_int64(value))
            case let value as Bool:
                sqlite3_bind_int(statement, index, value ? 1 : 0)
            default:
                throw StoreError.invalidRow
            }
        }
    }

    private func signalChange() {
        changeToken = UUID()
    }

    private var lastErrorMessage: String {
        if let db, let message = sqlite3_errmsg(db) {
            return String(cString: message)
        }
        return "Unknown SQLite error"
    }

    private static func session(from statement: OpaquePointer) throws -> ConversationSession {
        guard let id = text(statement, 0),
              let profileID = text(statement, 1).flatMap(UUID.init(uuidString:)),
              let hermesConversationID = text(statement, 2),
              let createdAt = text(statement, 4).flatMap(date(from:)),
              let updatedAt = text(statement, 5).flatMap(date(from:)) else {
            throw StoreError.invalidRow
        }
        return ConversationSession(
            id: id,
            serverProfileID: profileID,
            hermesConversationID: hermesConversationID,
            title: text(statement, 3),
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastMessagePreview: text(statement, 6),
            messageCount: Int(sqlite3_column_int64(statement, 7)),
            archivedAt: text(statement, 8).flatMap(date(from:))
        )
    }

    private static func message(from statement: OpaquePointer) throws -> ConversationMessage {
        guard let id = text(statement, 0),
              let sessionID = text(statement, 1),
              let roleText = text(statement, 3),
              let role = ConversationMessage.Role(rawValue: roleText),
              let messageText = text(statement, 4),
              let createdAt = text(statement, 6).flatMap(date(from:)),
              let metadata = text(statement, 7) else {
            throw StoreError.invalidRow
        }
        return ConversationMessage(
            id: id,
            sessionID: sessionID,
            turnID: text(statement, 2),
            role: role,
            text: messageText,
            final: sqlite3_column_int(statement, 5) == 1,
            createdAt: createdAt,
            metadata: metadata
        )
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private static func string(from date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static func date(from string: String) -> Date? {
        isoFormatter.date(from: string)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
