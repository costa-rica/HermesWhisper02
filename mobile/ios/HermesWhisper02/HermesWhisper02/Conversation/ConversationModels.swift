import Foundation

struct ConversationSession: Identifiable, Equatable {
    var id: String
    var serverProfileID: UUID
    var hermesConversationID: String
    var title: String?
    var createdAt: Date
    var updatedAt: Date
    var lastMessagePreview: String?
    var messageCount: Int
    var archivedAt: Date?
}

struct ConversationMessage: Identifiable, Equatable {
    enum Role: String, Equatable {
        case user
        case assistant
    }

    var id: String
    var sessionID: String
    var turnID: String?
    var role: Role
    var text: String
    var final: Bool
    var createdAt: Date
    var metadata: String
}
