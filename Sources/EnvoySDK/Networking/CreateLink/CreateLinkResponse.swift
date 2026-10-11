import Foundation

public struct CreateLinkResponse: Codable {
    public let url: String
    public let userRemainingQuota: Int
    public let modaltitle: String?
    public let mandatoryEmail: Bool?
    public let buttonText: String?
}
