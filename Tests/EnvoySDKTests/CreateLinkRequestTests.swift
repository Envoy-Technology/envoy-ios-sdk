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

    func testForArticle_sendsTheArticleAsSourceAndItsIdInExtra() {
        let body = CreateLinkRequest.forArticle(url: "https://news.example/1",
                                                id: "1",
                                                title: "Title",
                                                description: "Description",
                                                sharerId: "sharer-1",
                                                contentType: .htmlSource,
                                                imageURL: "https://news.example/1.jpg",
                                                extra: ["section": "world", "articleId": "old"])
            .asJSON(keyEncodingStrategy: .convertToSnakeCase)
        let contentSetting = body?["content_setting"] as? [String: Any]
        let common = contentSetting?["common"] as? [String: Any]

        XCTAssertEqual(contentSetting?["content_type"] as? String, "HTML_SOURCE")
        XCTAssertEqual(contentSetting?["content_name"] as? String, "Title")
        XCTAssertEqual(contentSetting?["preview_image"] as? String, "https://news.example/1.jpg")
        XCTAssertNil(contentSetting?["base64_file"])
        XCTAssertEqual(common?["source"] as? String, "https://news.example/1")
        XCTAssertEqual(common?["poster"] as? String, "https://news.example/1.jpg")
        XCTAssertEqual(body?["extra"] as? [String: String], ["section": "world", "articleId": "1"])
        XCTAssertEqual(body?["sharer_id"] as? String, "sharer-1")
    }
}
