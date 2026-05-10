import XCTest
@testable import HermesWhisper02

final class SanityTests: XCTestCase {
    func testProtocolVersion() {
        XCTAssertEqual(ProtocolVersion.current, 1)
    }
}
