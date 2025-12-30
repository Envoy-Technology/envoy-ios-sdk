import Foundation

public struct UserRewardsResponse: Decodable {
    public let userId: String
    public let rewardAvailable: Bool
}
