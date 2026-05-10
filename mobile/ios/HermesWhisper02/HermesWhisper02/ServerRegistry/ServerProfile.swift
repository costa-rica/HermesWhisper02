import Foundation

struct ServerProfile: Codable, Identifiable, Equatable {
    enum AuthKind: String, Codable {
        case bearer2FA = "bearer-2fa"
    }

    var id: UUID
    var displayName: String
    var baseURL: URL
    var notes: String?
    var authKind: AuthKind
}
