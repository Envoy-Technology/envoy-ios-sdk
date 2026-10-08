import XCTest
@testable import EnvoySDK

final class PixelEventAttributionTests: XCTestCase {
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
    func testNoCheckInProgress_sendsEventImmediatelyWithStoredAttribution() {
        // Attribution stored on an earlier launch.
        fixture.keychain.values[.envoyShareLinkHash] = "hash-0"
        fixture.keychain.values[.envoyLeadUuid] = "lead-0"

        fixture.makeEnvoy().logPixelEvent(request: LogPixelEventRequest(event: .accountCreated)) { _, _ in }

        XCTAssertEqual(fixture.pixelEventService.sentBodies.count, 1)
        XCTAssertEqual(fixture.pixelEventService.sentBodies.first?["share_link_hash"] as? String, "hash-0")
        XCTAssertEqual(fixture.pixelEventService.sentBodies.first?["lead_uuid"] as? String, "lead-0")
    }

    @MainActor
    func testEventLoggedDuringCheck_isSentAfterItWithAttribution() {
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy()
        envoy.checkDeferredLink()

        var completed = false
        envoy.logPixelEvent(request: LogPixelEventRequest(event: .appDownloaded)) { _, _ in completed = true }
        XCTAssertTrue(fixture.pixelEventService.sentRequests.isEmpty, "Must wait for the deferred-link check")

        fixture.pasteboard.finishDetection(with: .success(true))

        XCTAssertEqual(fixture.pixelEventService.sentBodies.count, 1)
        XCTAssertEqual(fixture.pixelEventService.sentBodies.first?["share_link_hash"] as? String, "hash-1")
        XCTAssertEqual(fixture.pixelEventService.sentBodies.first?["lead_uuid"] as? String, "lead-1")
        XCTAssertTrue(completed)
    }

    @MainActor
    func testRequestCreatedBeforeAttributionWasStored_isSentWithIt() {
        let request = LogPixelEventRequest(event: .appDownloaded)
        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)
        let envoy = fixture.makeEnvoy()
        envoy.checkDeferredLink()

        envoy.logPixelEvent(request: request) { _, _ in }

        XCTAssertEqual(fixture.pixelEventService.sentBodies.first?["share_link_hash"] as? String, "hash-1")
        XCTAssertEqual(fixture.pixelEventService.sentBodies.first?["lead_uuid"] as? String, "lead-1")
    }

    @MainActor
    func testCheckThatNeverFinishes_releasesQueuedEventAfterTimeout() {
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy(deferredLinkTimeout: 0.05)
        envoy.checkDeferredLink()

        let sent = expectation(description: "event sent")
        envoy.logPixelEvent(request: LogPixelEventRequest(event: .appDownloaded)) { _, _ in sent.fulfill() }
        XCTAssertTrue(fixture.pixelEventService.sentRequests.isEmpty, "Must wait for the deferred-link check")

        wait(for: [sent], timeout: 2)

        XCTAssertEqual(fixture.pixelEventService.sentBodies.count, 1)
        XCTAssertNil(fixture.pixelEventService.sentBodies.first?["share_link_hash"])
    }

    func testEventLoggedOffMainThread_isSentOnMainThread() {
        // Hosts compiled in Swift 5 mode can log from a background queue, e.g. a StoreKit callback.
        let envoy = fixture.makeEnvoy()

        let sent = expectation(description: "event sent")
        DispatchQueue.global().async {
            envoy.logPixelEvent(request: LogPixelEventRequest(event: .paymentSuccess)) { _, _ in sent.fulfill() }
        }
        wait(for: [sent], timeout: 2)

        XCTAssertEqual(fixture.pixelEventService.sentOnMainThread, [true])
    }

    @MainActor
    func testEventLoggedInCheckCompletion_isSentAfterEventsHeldDuringCheck() {
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy()
        envoy.checkDeferredLink { _ in
            envoy.logPixelEvent(request: LogPixelEventRequest(event: .accountCreated)) { _, _ in }
        }
        envoy.logPixelEvent(request: LogPixelEventRequest(event: .appDownloaded)) { _, _ in }

        fixture.pasteboard.finishDetection(with: .success(true))

        XCTAssertEqual(fixture.pixelEventService.sentEventNames, ["app_downloaded", "account_created"])
    }

    @MainActor
    func testHeldEventsSentTogether_readAttributionOnce() {
        fixture.pasteboard.content = TestLinks.full
        let envoy = fixture.makeEnvoy()
        envoy.checkDeferredLink()
        for event in [PixelEvent.appDownloaded, .accountCreated, .trialActivated] {
            envoy.logPixelEvent(request: LogPixelEventRequest(event: event)) { _, _ in }
        }

        fixture.pasteboard.finishDetection(with: .success(true))

        XCTAssertEqual(fixture.pixelEventService.sentBodies.count, 3)
        XCTAssertEqual(fixture.keychain.readCount, 2, "One read per Keychain key")
    }

    @MainActor
    func testAttributionMissingAtFirstRead_isReadAgainLater() {
        // E.g. the Keychain was locked, or another Envoy instance stored the link meanwhile.
        let envoy = fixture.makeEnvoy()
        envoy.logPixelEvent(request: LogPixelEventRequest(event: .appDownloaded)) { _, _ in }

        fixture.keychain.values[.envoyShareLinkHash] = "hash-1"
        fixture.keychain.values[.envoyLeadUuid] = "lead-1"
        envoy.logPixelEvent(request: LogPixelEventRequest(event: .accountCreated)) { _, _ in }

        XCTAssertEqual(fixture.pixelEventService.sentBodies.last?["share_link_hash"] as? String, "hash-1")
        XCTAssertEqual(fixture.pixelEventService.sentBodies.last?["lead_uuid"] as? String, "lead-1")
    }

    @MainActor
    func testAttributionStoredByAnotherInstance_isUsedForLaterEvents() {
        // E.g. the host initializes Envoy twice and logs through the newer instance.
        fixture.keychain.values[.envoyShareLinkHash] = "hash-0"
        fixture.keychain.values[.envoyLeadUuid] = "lead-0"
        fixture.pasteboard.content = TestLinks.full
        let checking = fixture.makeEnvoy()
        let logging = fixture.makeEnvoy()
        checking.checkDeferredLink()
        logging.logPixelEvent(request: LogPixelEventRequest(event: .appDownloaded)) { _, _ in }

        fixture.pasteboard.finishDetection(with: .success(true))
        logging.logPixelEvent(request: LogPixelEventRequest(event: .accountCreated)) { _, _ in }

        XCTAssertEqual(fixture.pixelEventService.sentBodies.last?["share_link_hash"] as? String, "hash-1")
        XCTAssertEqual(fixture.pixelEventService.sentBodies.last?["lead_uuid"] as? String, "lead-1")
    }

    @MainActor
    func testAttributionStoredByCheck_replacesEarlierOne() {
        fixture.keychain.values[.envoyShareLinkHash] = "hash-0"
        fixture.keychain.values[.envoyLeadUuid] = "lead-0"
        let envoy = fixture.makeEnvoy()
        envoy.logPixelEvent(request: LogPixelEventRequest(event: .appDownloaded)) { _, _ in }

        fixture.pasteboard.content = TestLinks.full
        fixture.pasteboard.detectionResult = .success(true)
        envoy.checkDeferredLink()
        envoy.logPixelEvent(request: LogPixelEventRequest(event: .accountCreated)) { _, _ in }

        XCTAssertEqual(fixture.pixelEventService.sentBodies.last?["share_link_hash"] as? String, "hash-1")
        XCTAssertEqual(fixture.pixelEventService.sentBodies.last?["lead_uuid"] as? String, "lead-1")
    }
}
