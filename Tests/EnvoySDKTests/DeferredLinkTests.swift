import XCTest
@testable import EnvoySDK

final class DeferredLinkTests: XCTestCase {
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

    // MARK: Behavior that must survive the rework

    @MainActor
    func testLinkWithBothParameters_storesThemAndReportsTrue() {
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)

        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink { found = $0 }

        XCTAssertEqual(found, true)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
        XCTAssertEqual(fixture.keychain.values[.envoyLeadUuid], "lead-1")
    }

    @MainActor
    func testNoWebURLDetected_neverReadsPasteboard() {
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(false)

        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink { found = $0 }

        XCTAssertEqual(found, false)
        XCTAssertEqual(fixture.pasteboard.readCount, 0)
        XCTAssertTrue(fixture.keychain.values.isEmpty)
    }

    @MainActor
    func testNoWebURLDetected_endsCheckForLaterLaunches() {
        fixture.pasteboard.detectionResult = .success(false)
        fixture.makeEnvoy().checkDeferredLink()

        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)
        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink { found = $0 }

        XCTAssertEqual(found, false)
        XCTAssertEqual(fixture.pasteboard.detectionCount, 1)
        XCTAssertEqual(fixture.pasteboard.readCount, 0)
    }

    @MainActor
    func testPasteDenied_endsCheckSoUserIsNotPromptedAgain() {
        // A URL was detected, but the user denied the paste prompt, so the read returns nil.
        fixture.pasteboard.content = nil
        fixture.pasteboard.detectionResult = .success(true)
        let envoy = fixture.makeEnvoy()

        var first: Bool?
        envoy.checkDeferredLink { first = $0 }
        fixture.pasteboard.content = TestLinks.full
        var second: Bool?
        envoy.checkDeferredLink { second = $0 }

        XCTAssertEqual(first, false)
        XCTAssertEqual(second, false)
        XCTAssertEqual(fixture.pasteboard.readCount, 1)
    }

    // MARK: New behavior

    @MainActor
    func testDetectionFailure_allowsRetryOnLaterCall() {
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .failure(TestError.detectionFailed)
        let envoy = fixture.makeEnvoy()

        var first: Bool?
        envoy.checkDeferredLink { first = $0 }
        fixture.pasteboard.detectionResult = .success(true)
        var second: Bool?
        envoy.checkDeferredLink { second = $0 }

        XCTAssertEqual(first, false)
        XCTAssertEqual(second, true)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
    }

    @MainActor
    func testSecondCallDuringCheck_waitsForSameResult() {
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy()

        var first: Bool?
        var second: Bool?
        envoy.checkDeferredLink { first = $0 }
        envoy.checkDeferredLink { second = $0 }
        XCTAssertNil(second, "Must not answer before the check in progress has a result")

        fixture.pasteboard.finishDetection(with: .success(true))

        XCTAssertEqual(first, true)
        XCTAssertEqual(second, true)
        XCTAssertEqual(fixture.pasteboard.detectionCount, 1)
    }

    @MainActor
    func testCheckInProgress_finishesAfterEnvoyIsReleased() {
        // E.g. the host calls Envoy.initialize again while the check runs.
        fixture.pasteboard.content = TestLinks.full
        var envoy: Envoy? = fixture.makeEnvoy()

        var found: Bool?
        envoy?.checkDeferredLink { found = $0 }
        envoy = nil
        fixture.pasteboard.finishDetection(with: .success(true))

        XCTAssertEqual(found, true)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
    }

    @MainActor
    func testTwoInstancesCheckingAtOnce_readPasteboardOnce() {
        // E.g. the host initializes Envoy in both AppDelegate and SceneDelegate.
        fixture.pasteboard.content = TestLinks.full
        let first = fixture.makeEnvoy()
        let second = fixture.makeEnvoy()

        first.checkDeferredLink()
        second.checkDeferredLink()
        fixture.pasteboard.finishDetection(with: .success(true))

        XCTAssertEqual(fixture.pasteboard.readCount, 1)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
    }

    func testCheckCalledOffMainThread_completesOnMainThread() {
        // Hosts compiled in Swift 5 mode can call it from a background queue, e.g. a consent callback.
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)
        let envoy = fixture.makeEnvoy()

        let completed = expectation(description: "check completed")
        var completedOnMainThread: Bool?
        DispatchQueue.global().async {
            envoy.checkDeferredLink { _ in
                completedOnMainThread = Thread.isMainThread
                completed.fulfill()
            }
        }
        wait(for: [completed], timeout: 2)

        XCTAssertEqual(completedOnMainThread, true)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
    }

    @MainActor
    func testCheckThatNeverFinishes_completesWithFalseAfterTimeout() {
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy(deferredLinkTimeout: 0.05)

        let completed = expectation(description: "check completed")
        var found: Bool?
        envoy.checkDeferredLink {
            found = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)

        XCTAssertEqual(found, false)
    }

    @MainActor
    func testDetectionAnsweringAfterTimeout_isIgnoredAndLaterCallRetries() {
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy(deferredLinkTimeout: 0.05)
        let timedOut = expectation(description: "check timed out")
        envoy.checkDeferredLink { _ in timedOut.fulfill() }
        wait(for: [timedOut], timeout: 2)

        fixture.pasteboard.finishDetection(with: .success(true))
        XCTAssertEqual(fixture.pasteboard.readCount, 0)

        fixture.pasteboard.detectionResult = .success(true)
        var found: Bool?
        envoy.checkDeferredLink { found = $0 }
        XCTAssertEqual(found, true)
    }

    @MainActor
    func testLateAnswerToTimedOutCheck_doesNotEndTheRetry() {
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy(deferredLinkTimeout: 0.05)
        let timedOut = expectation(description: "first check timed out")
        envoy.checkDeferredLink { _ in timedOut.fulfill() }
        wait(for: [timedOut], timeout: 2)

        var retryResult: Bool?
        envoy.checkDeferredLink { retryResult = $0 }
        fixture.pasteboard.finishOldestDetection(with: .failure(TestError.detectionFailed))
        XCTAssertNil(retryResult, "A late answer to the first check must not end the retry")

        fixture.pasteboard.finishOldestDetection(with: .success(true))
        XCTAssertEqual(retryResult, true)
    }

    @MainActor
    func testCallMadeWhileClipboardIsRead_getsTheResult() {
        // E.g. the host calls again while the paste prompt is up.
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy()
        var joined: Bool?
        fixture.pasteboard.onRead = {
            envoy.checkDeferredLink { joined = $0 }
        }

        envoy.checkDeferredLink()
        fixture.pasteboard.finishDetection(with: .success(true))

        XCTAssertEqual(joined, true)
    }

    @MainActor
    func testDetectionCallbackDroppedAfterEnvoyIsReleased_stillCompletesAfterTimeout() {
        fixture.pasteboard.content = TestLinks.full
        var envoy: Envoy? = fixture.makeEnvoy(deferredLinkTimeout: 0.05)
        let completed = expectation(description: "check completed")
        var found: Bool?
        envoy?.checkDeferredLink {
            found = $0
            completed.fulfill()
        }

        envoy = nil
        fixture.pasteboard.dropPendingDetections()
        wait(for: [completed], timeout: 2)

        XCTAssertEqual(found, false)
    }
}
