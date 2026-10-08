import XCTest
import UIKit
@testable import EnvoySDK

/// A host app's test double written before `checkDeferredLink` existed.
private final class HostEnvoyMock: EnvoyType {
    func pushShareGift(in navigationController: UINavigationController, request: CreateLinkRequest) {}
    func presentShareGift(from viewController: UIViewController, request: CreateLinkRequest) {}
    func giftButton(request: CreateLinkRequest) -> UIButton { UIButton() }
    func createLink(request: CreateLinkRequest,
                    completion: @escaping (CreateLinkResponse?, WebError?) -> ()) {}
    func prepLink(request: PrepLinkRequest,
                  completion: @escaping (PrepLinkResponse?, WebError?) -> ()) {}
    func manageLinks(request: ManageLinksRequest,
                     completion: @escaping (ManageLinksResponse?, WebError?) -> ()) {}
    func clearManagedLinks(completion: @escaping (ClearManagedLinksResponse?, WebError?) -> ()) {}
    func getUserRemainingQuota(userId: String,
                               completion: @escaping (UserQuotaResponse?, WebError?) -> ()) {}
    func logPixelEvent(request: LogPixelEventRequest,
                       completion: @escaping (EmptyResponse?, WebError?) -> ()) {}
    func getUserRewards(userId: String,
                        completion: @escaping (UserRewardsResponse?, WebError?) -> ()) {}
    func claimUserReward(request: ClaimUserRewardRequest,
                         completion: @escaping (ClaimUserRewardResponse?, WebError?) -> ()) {}
    func getUserCurrentRewards(userId: String,
                               completion: @escaping (UserCurrentRewardsResponse?, WebError?) -> ()) {}
}

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

    @MainActor
    func testHostMockWithoutCheck_conformsAndReportsNoLink() {
        let envoy: EnvoyType = HostEnvoyMock()

        var found: Bool?
        envoy.checkDeferredLink { found = $0 }

        XCTAssertEqual(found, false)
    }
}
