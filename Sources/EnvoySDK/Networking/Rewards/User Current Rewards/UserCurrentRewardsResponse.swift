import Foundation

public struct UserCurrentRewardsResponse: Decodable {
    public struct EventCount: Decodable {
        public let completed: Int
        public let leftToReward: Int
        public let percentageDone: Int
    }
    
    public let earnedThisPeriod: Int
    public let earnableLeft: Int
    public let eventCount: EventCount
}
