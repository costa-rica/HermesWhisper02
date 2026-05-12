import Foundation
import XCTest
@testable import HermesWhisper02

final class ServerInfoProbeTests: XCTestCase {
    override func tearDown() {
        ServerInfoURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testFetchParsesServerInfoPayload() async throws {
        ServerInfoURLProtocolStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/server/info")
            return try Self.jsonResponse(statusCode: 200, body: [
                "name": "fsdc-avatar08",
                "version": "0.1.0",
                "front_llm": "openai:gpt-4o-mini",
                "auth": "bearer-2fa",
                "protocol_version": 1
            ])
        }

        let info = try await ServerInfoProbe(session: makeSession())
            .fetch(baseURL: URL(string: "https://api.example.com")!)

        XCTAssertEqual(info.name, "fsdc-avatar08")
        XCTAssertEqual(info.version, "0.1.0")
        XCTAssertEqual(info.frontLLM, "openai:gpt-4o-mini")
        XCTAssertEqual(info.auth, .bearer2FA)
        XCTAssertEqual(info.protocolVersion, 1)
    }

    func testFetchThrowsForUnsupportedAuth() async throws {
        ServerInfoURLProtocolStub.handler = { _ in
            try Self.jsonResponse(statusCode: 200, body: [
                "name": "server",
                "version": "0.1.0",
                "front_llm": "openai:gpt-4o-mini",
                "auth": "unknown",
                "protocol_version": 1
            ])
        }

        do {
            _ = try await ServerInfoProbe(session: makeSession())
                .fetch(baseURL: URL(string: "https://api.example.com")!)
            XCTFail("Probe accepted unsupported auth")
        } catch let error as ServerInfoProbe.ProbeError {
            XCTAssertEqual(error, .unsupportedAuth("unknown"))
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServerInfoURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private static func jsonResponse(
        statusCode: Int,
        body: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        let data = try JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.example.com/api/server/info")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, data)
    }
}

private final class ServerInfoURLProtocolStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: ServerInfoProbe.ProbeError.invalidResponse)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
    }
}
