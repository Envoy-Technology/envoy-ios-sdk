import XCTest
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
}
