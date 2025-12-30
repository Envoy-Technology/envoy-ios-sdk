import Foundation
// base64_file: str
public struct PrepLinkRequest: Codable {
    let url: String?

    public init(url: String) {
        self.url = url
    }
}
