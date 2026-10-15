import XCTest
@testable import EnvoySDK

final class CreateLinkRequestTests: XCTestCase {
    private func makeRequest(extra: [String: String]?) -> CreateLinkRequest {
        CreateLinkRequest(autoplay: nil,
                          contentSetting: .init(contentType: "HTML_SOURCE",
                                                contentName: "Name",
                                                contentDescription: "Description"),
                          extra: extra,
                          sharerId: "sharer-1")
    }

    func testExtra_isSentAsJSONObjectWithKeysUnchanged() {
        let body = makeRequest(extra: ["articleId": "16208949"]).asJSON(keyEncodingStrategy: .convertToSnakeCase)

        XCTAssertEqual(body?["extra"] as? [String: String], ["articleId": "16208949"])
    }

    func testNoExtra_isNotSent() {
        let body = makeRequest(extra: nil).asJSON(keyEncodingStrategy: .convertToSnakeCase)

        XCTAssertNil(body?["extra"])
    }
}
