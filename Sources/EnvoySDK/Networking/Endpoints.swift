import Foundation

enum Endpoint {
    case createLink
    case prepLink
    case manageLinks
    case clearManagedLinks
    case getUerRemainingQuota(userId: String)
    case logPixelEvent
    case getUserRewards(userId: String)
    case claimUserReward
    case getUserCurrentRewards(userId: String)

    var path: String {
        switch self {
        case .prepLink:
            return "prep-link"
        case .createLink:
            return "create-link"
        case .manageLinks:
            return "manage-links"
        case .clearManagedLinks:
            return "manage-links/clear"
        case .getUerRemainingQuota(let userId):
            return "user-quota/\(userId)"
        case .logPixelEvent:
            return "pixel-event"
        case .getUserRewards(let userId):
            return "user-rewards/\(userId)"
        case .claimUserReward:
            return "user-rewards"
        case .getUserCurrentRewards(let userId):
            return "user-current-rewards/\(userId)"
        }
    }
}


