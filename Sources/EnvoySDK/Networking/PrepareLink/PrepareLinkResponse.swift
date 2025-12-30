import Foundation

public struct PrepLinkResponse: Codable {
    let msg: String
    let type: String
    let loc: [String]
}
