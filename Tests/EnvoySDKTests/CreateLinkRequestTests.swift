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

    func testContentProtection_isSentInTheShakaShape() {
        typealias Link = CreateLinkRequest
        let protection = Link.ContentProtection(
            sources: [Link.KeySystem.fairPlay: "https://cdn.example/s.m3u8"],
            drm: Link.DRMConfig(
                servers: [Link.KeySystem.widevine: "https://license.example/wv"],
                advanced: [Link.KeySystem.fairPlay: Link.AdvancedDRMConfig(
                    serverCertificate: "Y2VydA==",
                    serverCertificateUri: "https://license.example/fps.cer",
                    headers: ["X-Drm-Token": "t"])]),
            fairPlayProvider: .ezdrm)
        let body = Link(autoplay: nil,
                        contentSetting: .init(contentType: "VIDEO",
                                              contentName: "Name",
                                              contentDescription: "Description",
                                              contentProtection: protection),
                        sharerId: "sharer-1")
            .asJSON(keyEncodingStrategy: .convertToSnakeCase)
        let sent = (body?["content_setting"] as? [String: Any])?["content_protection"] as? [String: Any]
        let drm = sent?["drm"] as? [String: Any]
        let advanced = (drm?["advanced"] as? [String: Any])?["com.apple.fps"] as? [String: Any]

        XCTAssertEqual(sent?["sources"] as? [String: String], ["com.apple.fps": "https://cdn.example/s.m3u8"])
        XCTAssertEqual(sent?["fair_play_provider"] as? String, "ezdrm")
        XCTAssertEqual(drm?["servers"] as? [String: String], ["com.widevine.alpha": "https://license.example/wv"])
        // Shaka's names, not snake case
        XCTAssertEqual(advanced?["serverCertificate"] as? String, "Y2VydA==")
        XCTAssertEqual(advanced?["serverCertificateUri"] as? String, "https://license.example/fps.cer")
        XCTAssertEqual(advanced?["headers"] as? [String: String], ["X-Drm-Token": "t"])
        XCTAssertEqual(advanced?.count, 3)
    }

    func testAdvancedDRMConfig_leavesOutWhatIsNotSet_andDecodesBack() throws {
        let config = CreateLinkRequest.AdvancedDRMConfig(headers: ["a": "b"])
        let data = try JSONEncoder().encode(config)

        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String: [String: String]], ["headers": ["a": "b"]])
        let decoded = try JSONDecoder().decode(CreateLinkRequest.AdvancedDRMConfig.self, from: data)
        XCTAssertEqual(decoded.headers, ["a": "b"])
        XCTAssertNil(decoded.serverCertificate)
    }

    func testNoContentProtection_isNotSent() {
        let body = makeRequest(extra: nil).asJSON(keyEncodingStrategy: .convertToSnakeCase)

        XCTAssertNil((body?["content_setting"] as? [String: Any])?["content_protection"])
    }
}
