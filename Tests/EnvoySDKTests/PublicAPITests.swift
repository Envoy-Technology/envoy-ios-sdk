import XCTest
import UIKit
// Not @testable: this file sees only the public API, as a host app does.
import EnvoySDK

final class PublicAPITests: XCTestCase {
    func testCreateLinkResponse_exposesItsFields() throws {
        let json = #"{"url":"https://envoy.is/l/abc","userRemainingQuota":3,"modaltitle":"Gift","mandatoryEmail":true,"buttonText":"Open"}"#

        let response = try JSONDecoder().decode(CreateLinkResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.url, "https://envoy.is/l/abc")
        XCTAssertEqual(response.userRemainingQuota, 3)
        XCTAssertEqual(response.modaltitle, "Gift")
        XCTAssertEqual(response.mandatoryEmail, true)
        XCTAssertEqual(response.buttonText, "Open")
    }

    func testPrepLinkResponse_exposesItsFields() throws {
        let json = #"{"msg":"Prepared","type":"screenshot","loc":["body","file"]}"#

        let response = try JSONDecoder().decode(PrepLinkResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.msg, "Prepared")
        XCTAssertEqual(response.type, "screenshot")
        XCTAssertEqual(response.loc, ["body", "file"])
    }

    func testCustomError_exposesDetail() throws {
        let json = #"{"detail":"Quota exceeded"}"#

        let error = try JSONDecoder().decode(CustomError.self, from: Data(json.utf8))

        XCTAssertEqual(error.detail, "Quota exceeded")
    }

    func testClaimUserRewardRequest_exposesUserId() {
        XCTAssertEqual(ClaimUserRewardRequest(userId: "user-1").userId, "user-1")
    }

    func testScreenshotShare_isBuiltFromArticle() {
        let share = ScreenshotShare(request: .forArticle(url: "https://news.example/1",
                                                         id: "1",
                                                         title: "Title",
                                                         description: "Description",
                                                         sharerId: "sharer-1",
                                                         contentType: .htmlSource),
                                    message: "Read it free")

        XCTAssertEqual(share.message, "Read it free")
    }

    /// Not run; it only has to compile, as in a host app.
    @MainActor
    private func useScreenshotSharing(_ envoy: EnvoyType, from viewController: UIViewController) {
        envoy.startScreenshotSharing(from: viewController) { nil }
        envoy.startScreenshotSharing(from: viewController, onEvent: { _ in }) { nil }
        envoy.startScreenshotSharing(from: viewController, beforeSharing: { prompt in
            _ = prompt.content.message
            let _: Bool = prompt.isActive
            let _: Bool = prompt.share()
            prompt.share()
            prompt.cancel()
        }) { nil }
        envoy.startScreenshotSharing(from: viewController, onEvent: { _ in }, beforeSharing: { _ in }) { nil }
        envoy.stopScreenshotSharing()
    }
}
