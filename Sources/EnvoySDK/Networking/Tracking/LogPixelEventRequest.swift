import Foundation

public enum PixelEvent {
    case appDownloaded
    case accountCreated
    case trialActivated
    case paymentSuccess
    case custom(eventName: String)
    
    public var rawValue: String {
        switch self {
        case .appDownloaded:
            return "app_downloaded"
        case .accountCreated:
            return "account_created"
        case .trialActivated:
            return "trial_activated"
        case .paymentSuccess:
            return "payment_success"
        case .custom(let eventName):
            return eventName
        }
    }
}

public struct LogPixelEventRequest: Encodable {
    
    public struct Extra: Encodable {
        let title: String?
        let type: String?
        
        public init(title: String?, type: String?) {
            self.title = title
            self.type = type
        }
    }
    
    let eventName: String
    let sharerUserId: String?
    private(set) var shareLinkHash: String?
    private(set) var leadUuid: String?
    let extra: Extra?

    public init(event: PixelEvent, sharerUserId: String? = nil, extra: Extra? = nil) {
        self.eventName = event.rawValue
        self.sharerUserId = sharerUserId
        self.extra = extra
    }

    struct Attribution {
        let shareLinkHash: String?
        let leadUuid: String?
    }

    /// Attribution is added when the event is sent, not when the request is created,
    /// so a request built before the deferred-link check finished still carries it.
    func attributed(with attribution: Attribution) -> LogPixelEventRequest {
        var request = self
        request.shareLinkHash = attribution.shareLinkHash
        request.leadUuid = attribution.leadUuid
        return request
    }
}
