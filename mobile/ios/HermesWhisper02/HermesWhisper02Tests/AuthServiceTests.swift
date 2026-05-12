import Foundation
import XCTest
@testable import HermesWhisper02

final class AuthServiceTests: XCTestCase {
    private var keychain: InMemoryAuthKeychainAccess!
    private var store: KeychainStore!
    private var session: URLSession!
    private var profile: ServerProfile!

    override func setUp() {
        super.setUp()
        keychain = InMemoryAuthKeychainAccess()
        store = KeychainStore(keychain: keychain)
        session = makeSession()
        profile = ServerProfile(
            id: UUID(),
            displayName: "test",
            baseURL: URL(string: "https://api.example.com")!,
            notes: nil,
            authKind: .bearer2FA
        )
    }

    override func tearDown() {
        URLProtocolStub.handler = nil
        profile = nil
        session = nil
        store = nil
        keychain = nil
        super.tearDown()
    }

    func testLoginAndVerifyHappyPath() async throws {
        let service = makeService()
        var requestedPaths: [String] = []

        URLProtocolStub.handler = { request in
            requestedPaths.append(request.url?.path ?? "")

            switch request.url?.path {
            case "/api/auth/login":
                return try Self.jsonResponse(statusCode: 200, body: [
                    "ok": true,
                    "expires_in": 600
                ])
            case "/api/auth/verify":
                return try Self.jsonResponse(statusCode: 200, body: [
                    "token": "bearer-token",
                    "expires_at": "2027-01-15T12:00:00Z"
                ])
            default:
                return try Self.jsonResponse(statusCode: 404, body: [
                    "error": [
                        "code": "NOT_FOUND",
                        "message": "Not found",
                        "status": 404,
                        "details": NSNull()
                    ]
                ])
            }
        }

        try await service.login(email: "nrodrig1@gmail.com", password: "password")
        let credentials = try await service.verify(
            email: "nrodrig1@gmail.com",
            code: "123456"
        )

        XCTAssertEqual(requestedPaths, ["/api/auth/login", "/api/auth/verify"])
        XCTAssertEqual(credentials.token, "bearer-token")
        XCTAssertEqual(credentials.email, "nrodrig1@gmail.com")
        XCTAssertEqual(credentials.expiresAt, Date(timeIntervalSince1970: 1_800_014_400))
    }

    func testLoginThrowsAPIErrorForBadCredentials() async throws {
        let service = makeService()
        URLProtocolStub.handler = { _ in
            try Self.authFailure(message: "Invalid email or password")
        }

        do {
            try await service.login(email: "nrodrig1@gmail.com", password: "wrong")
            XCTFail("login accepted bad credentials")
        } catch let error as AuthService.ServiceError {
            XCTAssertEqual(
                error,
                .api(code: "AUTH_FAILED", message: "Invalid email or password", status: 401)
            )
        }
    }

    func testVerifyThrowsAPIErrorForExpiredCode() async throws {
        let service = makeService()
        URLProtocolStub.handler = { _ in
            try Self.authFailure(message: "Verification code expired")
        }

        do {
            _ = try await service.verify(email: "nrodrig1@gmail.com", code: "123456")
            XCTFail("verify accepted an expired code")
        } catch let error as AuthService.ServiceError {
            XCTAssertEqual(
                error,
                .api(code: "AUTH_FAILED", message: "Verification code expired", status: 401)
            )
        }
    }

    private func makeService() -> AuthService {
        AuthService(profile: profile, keychain: store, session: session)
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func authFailure(message: String) throws -> (HTTPURLResponse, Data) {
        try jsonResponse(statusCode: 401, body: [
            "error": [
                "code": "AUTH_FAILED",
                "message": message,
                "status": 401,
                "details": NSNull()
            ]
        ])
    }

    private static func jsonResponse(
        statusCode: Int,
        body: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}

private final class URLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: AuthService.ServiceError.invalidResponse)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}

private final class InMemoryAuthKeychainAccess: KeychainAccessing {
    private var values: [String: Data] = [:]

    func save(data: Data, service: String, account: String) throws {
        values[key(service: service, account: account)] = data
    }

    func load(service: String, account: String) throws -> Data? {
        values[key(service: service, account: account)]
    }

    func delete(service: String, account: String) throws {
        values.removeValue(forKey: key(service: service, account: account))
    }

    private func key(service: String, account: String) -> String {
        "\(service):\(account)"
    }
}
