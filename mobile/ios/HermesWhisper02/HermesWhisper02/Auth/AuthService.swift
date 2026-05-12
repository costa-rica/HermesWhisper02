import Foundation

struct AuthService {
    enum ServiceError: Error, Equatable, LocalizedError {
        case invalidResponse
        case api(code: String, message: String, status: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Invalid server response."
            case let .api(_, message, _):
                message
            }
        }
    }

    private struct LoginRequest: Encodable {
        var email: String
        var password: String
    }

    private struct LoginResponse: Decodable {
        var ok: Bool
        var expiresIn: Int

        enum CodingKeys: String, CodingKey {
            case ok
            case expiresIn = "expires_in"
        }
    }

    private struct VerifyRequest: Encodable {
        var email: String
        var code: String
    }

    private struct VerifyResponse: Decodable {
        var token: String
        var expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case token
            case expiresAt = "expires_at"
        }
    }

    private let profile: ServerProfile
    private let keychain: KeychainStore
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(
        profile: ServerProfile,
        keychain: KeychainStore,
        session: URLSession = .shared
    ) {
        self.profile = profile
        self.keychain = keychain
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func login(email: String, password: String) async throws {
        let response: LoginResponse = try await post(
            path: ["api", "auth", "login"],
            body: LoginRequest(email: email, password: password)
        )

        guard response.ok else {
            throw ServiceError.invalidResponse
        }
    }

    func verify(email: String, code: String) async throws -> Credentials {
        let response: VerifyResponse = try await post(
            path: ["api", "auth", "verify"],
            body: VerifyRequest(email: email, code: code)
        )

        return Credentials(token: response.token, expiresAt: response.expiresAt, email: email)
    }

    func currentCredentials() throws -> Credentials? {
        try keychain.loadValid(profileID: profile.id)
    }

    func logout() throws {
        try keychain.delete(profileID: profile.id)
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        path: [String],
        body: RequestBody
    ) async throws -> ResponseBody {
        var request = URLRequest(url: url(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServiceError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw ServiceError.api(
                    code: envelope.error.code,
                    message: envelope.error.message,
                    status: envelope.error.status
                )
            }
            throw ServiceError.invalidResponse
        }

        return try decoder.decode(ResponseBody.self, from: data)
    }

    private func url(path: [String]) -> URL {
        path.reduce(profile.baseURL) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: false)
        }
    }
}
