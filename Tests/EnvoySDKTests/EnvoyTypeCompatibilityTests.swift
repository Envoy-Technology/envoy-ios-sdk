import XCTest
@testable import EnvoySDK

final class EnvoyTypeCompatibilityTests: XCTestCase {
    private var fixture: EnvoyFixture!

    override func setUp() {
        super.setUp()
        fixture = EnvoyFixture()
    }

    override func tearDown() {
        fixture.removeUserDefaults()
        fixture = nil
        super.tearDown()
    }

    @MainActor
    func testCheckThroughEnvoyTypeWithoutArguments_runsEnvoysCheck() {
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)
        let envoy: EnvoyType = fixture.makeEnvoy()

        envoy.checkDeferredLink()

        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
    }
}
