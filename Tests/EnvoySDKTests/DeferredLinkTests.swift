import XCTest
import UIKit
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

    // MARK: Reading the link

    @MainActor
    func testLinkWithBothParameters_storesThemAndReportsTrue() {
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)

        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink { found = $0 }
        drainMainQueue()

        XCTAssertEqual(found, true)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
        XCTAssertEqual(fixture.keychain.values[.envoyLeadUuid], "lead-1")
    }

    @MainActor
    func testLinkWithSurroundingWhitespace_isStored() {
        fixture.pasteboard.content = " \(TestLinks.full)\n"
        fixture.pasteboard.detectionResult = .success(true)

        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink { found = $0 }
        drainMainQueue()

        XCTAssertEqual(found, true)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
    }

    @MainActor
    func testNoWebURLDetected_neverReadsPasteboard() {
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(false)

        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink { found = $0 }
        drainMainQueue()

        XCTAssertEqual(found, false)
        XCTAssertEqual(fixture.pasteboard.readCount, 0)
        XCTAssertTrue(fixture.keychain.values.isEmpty)
    }

    @MainActor
    func testNoWebURLDetected_endsCheckForLaterCalls() {
        fixture.pasteboard.detectionResult = .success(false)
        fixture.makeEnvoy().checkDeferredLink()

        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)
        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink { found = $0 }
        drainMainQueue()

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
        drainMainQueue()

        XCTAssertEqual(first, false)
        XCTAssertEqual(second, false)
        XCTAssertEqual(fixture.pasteboard.readCount, 1)
    }

    @MainActor
    func testHostsOwnIsFreshInstallKey_doesNotDisableTheCheck() {
        // A host app that uses the same generic key, e.g. during onboarding after launch.
        let envoy = fixture.makeEnvoy()
        fixture.userDefaults.set(false, forKey: "isFreshInstall")
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)

        var found: Bool?
        envoy.checkDeferredLink { found = $0 }
        drainMainQueue()

        XCTAssertEqual(found, true)
    }

    @MainActor
    func testUpdateFromSDKThatAlreadyReadClipboard_neverChecksAgain() {
        // SDKs before 0.0.16 read the clipboard at the first launch and stored "isFreshInstall" = false.
        fixture.userDefaults.set(false, forKey: "isFreshInstall")
        fixture.installDate = Date(timeIntervalSinceNow: -60 * 60)
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)

        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink { found = $0 }
        drainMainQueue()

        XCTAssertEqual(found, false)
        XCTAssertEqual(fixture.pasteboard.detectionCount, 0)
        XCTAssertEqual(fixture.pasteboard.readCount, 0)
    }

    // MARK: Install age

    @MainActor
    func testInstalledLongAgo_neverTouchesClipboard() {
        // E.g. the host adds the call in a later app version, or consent comes weeks later.
        fixture.installDate = Date(timeIntervalSinceNow: -2 * 24 * 60 * 60)
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)
        let envoy = fixture.makeEnvoy()

        var first: Bool?
        envoy.checkDeferredLink { first = $0 }
        var second: Bool?
        envoy.checkDeferredLink { second = $0 }
        drainMainQueue()

        XCTAssertEqual(first, false)
        XCTAssertEqual(second, false)
        XCTAssertEqual(fixture.pasteboard.detectionCount, 0)
        XCTAssertEqual(fixture.pasteboard.readCount, 0)
    }

    @MainActor
    func testInstallDateUnknown_checksAsUsual() {
        fixture.installDate = nil
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)

        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink { found = $0 }
        drainMainQueue()

        XCTAssertEqual(found, true)
    }

    // MARK: App state

    @MainActor
    func testAppNotActive_waitsForActivationBeforeDetecting() {
        fixture.isApplicationActive = false
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)
        let envoy = fixture.makeEnvoy()

        var found: Bool?
        envoy.checkDeferredLink { found = $0 }
        drainMainQueue()
        XCTAssertEqual(fixture.pasteboard.detectionCount, 0)
        XCTAssertNil(found)

        fixture.isApplicationActive = true
        fixture.notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        drainMainQueue()

        XCTAssertEqual(found, true)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
    }

    @MainActor
    func testAppInactiveWhenURLIsDetected_readsOnlyAfterActivation() {
        // The clipboard can't be read while the app is in the background, so it must not use up the check.
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy()
        var found: Bool?
        envoy.checkDeferredLink { found = $0 }

        fixture.isApplicationActive = false
        fixture.pasteboard.finishDetection(with: .success(true))
        drainMainQueue()
        XCTAssertEqual(fixture.pasteboard.readCount, 0)
        XCTAssertNil(found)

        fixture.isApplicationActive = true
        fixture.pasteboard.detectionResult = .success(true)
        fixture.notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        drainMainQueue()

        XCTAssertEqual(found, true)
        XCTAssertEqual(fixture.pasteboard.readCount, 1)
    }

    // MARK: Check in progress

    @MainActor
    func testSecondCallDuringCheck_waitsForSameResult() {
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy()

        var first: Bool?
        var second: Bool?
        envoy.checkDeferredLink { first = $0 }
        envoy.checkDeferredLink { second = $0 }
        drainMainQueue()
        XCTAssertNil(second, "Must not answer before the check in progress has a result")

        fixture.pasteboard.finishDetection(with: .success(true))
        drainMainQueue()

        XCTAssertEqual(first, true)
        XCTAssertEqual(second, true)
        XCTAssertEqual(fixture.pasteboard.detectionCount, 1)
    }

    @MainActor
    func testSecondInstanceCheckingDuringFirstOne_getsTheSameResult() {
        // E.g. the host initializes Envoy in both AppDelegate and SceneDelegate.
        fixture.pasteboard.content = TestLinks.full
        let first = fixture.makeEnvoy()
        let second = fixture.makeEnvoy()

        var firstFound: Bool?
        var secondFound: Bool?
        first.checkDeferredLink { firstFound = $0 }
        second.checkDeferredLink { secondFound = $0 }
        fixture.pasteboard.finishDetection(with: .success(true))
        drainMainQueue()

        XCTAssertEqual(firstFound, true)
        XCTAssertEqual(secondFound, true)
        XCTAssertEqual(fixture.pasteboard.detectionCount, 1)
        XCTAssertEqual(fixture.pasteboard.readCount, 1)
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
        drainMainQueue()

        XCTAssertEqual(found, true)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
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
        drainMainQueue()

        XCTAssertEqual(joined, true)
    }

    // MARK: Completion

    @MainActor
    func testCompletion_isNeverCalledBeforeCheckDeferredLinkReturns() {
        fixture.pasteboard.detectionResult = .success(false)
        let envoy = fixture.makeEnvoy()
        envoy.checkDeferredLink()
        drainMainQueue()

        var found: Bool?
        envoy.checkDeferredLink { found = $0 }
        XCTAssertNil(found)

        drainMainQueue()
        XCTAssertEqual(found, false)
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
    func testCheckThatNeverFinishes_completesWithFalseAfterCompletionTimeout() {
        fixture.pasteboard.content = TestLinks.full
        fixture.completionTimeout = 0.05
        let envoy = fixture.makeEnvoy()

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
    func testDetectionCallbackDroppedAfterEnvoyIsReleased_stillCompletesAfterTimeout() {
        fixture.pasteboard.content = TestLinks.full
        fixture.completionTimeout = 0.05
        var envoy: Envoy? = fixture.makeEnvoy()
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

    // MARK: Failures and late answers

    @MainActor
    func testDetectionFailingOnce_isRetriedWithinTheSameCheck() {
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.nextDetectionResults = [.failure(TestError.detectionFailed)]
        fixture.pasteboard.detectionResult = .success(true)

        let completed = expectation(description: "check completed")
        var found: Bool?
        fixture.makeEnvoy().checkDeferredLink {
            found = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)

        XCTAssertEqual(found, true)
        XCTAssertEqual(fixture.pasteboard.detectionCount, 2)
    }

    @MainActor
    func testDetectionFailingTwice_allowsRetryOnLaterCall() {
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .failure(TestError.detectionFailed)
        let envoy = fixture.makeEnvoy()

        let completed = expectation(description: "first check completed")
        var first: Bool?
        envoy.checkDeferredLink {
            first = $0
            completed.fulfill()
        }
        wait(for: [completed], timeout: 2)

        fixture.pasteboard.detectionResult = .success(true)
        var second: Bool?
        envoy.checkDeferredLink { second = $0 }
        drainMainQueue()

        XCTAssertEqual(first, false)
        XCTAssertEqual(second, true)
        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
    }

    @MainActor
    func testDetectionAnsweringAfterCompletionTimeout_stillStoresTheLink() {
        // E.g. detection takes longer while the clipboard content comes from another device.
        fixture.pasteboard.content = TestLinks.full
        fixture.completionTimeout = 0.05
        let envoy = fixture.makeEnvoy()
        let completed = expectation(description: "completion timed out")
        envoy.checkDeferredLink { _ in completed.fulfill() }
        wait(for: [completed], timeout: 2)

        fixture.pasteboard.finishDetection(with: .success(true))

        XCTAssertEqual(fixture.keychain.values[.envoyShareLinkHash], "hash-1")
    }

    @MainActor
    func testDetectionAnsweringAfterCheckTimeLimit_isIgnoredAndLaterCallRetries() {
        fixture.pasteboard.content = TestLinks.full
        fixture.checkTimeLimit = 0.2
        let envoy = fixture.makeEnvoy()
        let ended = expectation(description: "check ended")
        envoy.checkDeferredLink { _ in ended.fulfill() }
        wait(for: [ended], timeout: 2)

        fixture.pasteboard.finishDetection(with: .success(true))
        XCTAssertEqual(fixture.pasteboard.readCount, 0)

        fixture.pasteboard.detectionResult = .success(true)
        var found: Bool?
        envoy.checkDeferredLink { found = $0 }
        drainMainQueue()
        XCTAssertEqual(found, true)
    }

    @MainActor
    func testLateAnswerToCheckPastItsTimeLimit_doesNotEndTheRetry() {
        fixture.pasteboard.content = TestLinks.full
        fixture.checkTimeLimit = 0.2
        let envoy = fixture.makeEnvoy()
        let ended = expectation(description: "first check ended")
        envoy.checkDeferredLink { _ in ended.fulfill() }
        wait(for: [ended], timeout: 2)

        var retryResult: Bool?
        envoy.checkDeferredLink { retryResult = $0 }
        fixture.pasteboard.finishOldestDetection(with: .success(false))
        drainMainQueue()
        XCTAssertNil(retryResult, "A late answer to the first check must not end the retry")

        fixture.pasteboard.finishOldestDetection(with: .success(true))
        drainMainQueue()
        XCTAssertEqual(retryResult, true)
    }
}
