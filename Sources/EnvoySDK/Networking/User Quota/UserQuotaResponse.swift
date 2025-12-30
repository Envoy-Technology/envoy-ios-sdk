import Foundation

public struct UserQuotaResponse: Decodable {
    public let userId: String
    public let userRemainingQuota: Int
}
