import Foundation

struct ServerInfoProbe {
    struct ServerInfo: Codable, Equatable {
        var name: String
        var version: String
        var frontLLM: String
        var auth: ServerProfile.AuthKind
        var protocolVersion: Int

        enum CodingKeys: String, CodingKey {
            case name
            case version
            case frontLLM = "front_llm"
            case auth
            case protocolVersion = "protocol_version"
        }
    }

    enum ProbeError: Error, Equatable, LocalizedError {
        case invalidResponse
        case unsupportedAuth(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                "Unable to read server info."
            case let .unsupportedAuth(auth):
                "Unsupported auth type: \(auth)"
            }
        }
    }

    private struct RawServerInfo: Decodable {
        var name: String
        var version: String
        var frontLLM: String
        var auth: String
        var protocolVersion: Int

        enum CodingKeys: String, CodingKey {
            case name
            case version
            case frontLLM = "front_llm"
            case auth
            case protocolVersion = "protocol_version"
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetch(baseURL: URL) async throws -> ServerInfo {
        let url = baseURL
            .appendingPathComponent("api", isDirectory: false)
            .appendingPathComponent("server", isDirectory: false)
            .appendingPathComponent("info", isDirectory: false)
        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ProbeError.invalidResponse
        }

        let raw = try JSONDecoder().decode(RawServerInfo.self, from: data)
        guard let authKind = ServerProfile.AuthKind(rawValue: raw.auth) else {
            throw ProbeError.unsupportedAuth(raw.auth)
        }

        return ServerInfo(
            name: raw.name,
            version: raw.version,
            frontLLM: raw.frontLLM,
            auth: authKind,
            protocolVersion: raw.protocolVersion
        )
    }
}
