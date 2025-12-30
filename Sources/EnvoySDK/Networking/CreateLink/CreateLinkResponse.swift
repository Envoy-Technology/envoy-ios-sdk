import Foundation

public struct CreateLinkResponse: Codable {
    let url: String
    let userRemainingQuota: Int
    let modaltitle: String?
    let mandatoryEmail: Bool?
    let buttonText: String?
}
