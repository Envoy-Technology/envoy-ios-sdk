import Foundation

public struct ClaimUserRewardRequest: Encodable {
    public let userId: String
    
    public init(userId: String) {
        self.userId = userId
    }
}
