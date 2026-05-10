import Foundation

struct ErrorEnvelope: Codable, Equatable {
    struct APIError: Codable, Equatable {
        var code: String
        var message: String
        var status: Int
        var details: String?
    }

    var error: APIError
}
