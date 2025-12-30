import Foundation

/*
enum TrackEvent: String {
    case loadGiftButton = "load_gift_button"
    case viewGiftButton = "view_gift_button"
    case clickGenerateShareLink = "click_generate_share_link"
    case viewShareDetailsModel = "view_share_details_modal"
    case viewExceededQuotaError = "view_exceeded_quota_error"
    case clickChooseShareMedium = "click_choose_share_medium"
}

enum TrackParameter: Codable {
    case partner(PartnerTrackParameters)
    case subscriber(SubscriberTrackParameters)
    case content(ContentTrackParameters)
    case shareLink(ShareLinkTrackParameters)
    case custom([String : String])

    var asParameters: [String : String]? {
        switch self {
        case let .partner(parameters):
            return parameters.asParameters
        case let .subscriber(parameters):
            return parameters.asParameters
        case let .content(parameters):
            return parameters.asParameters
        case let .shareLink(parameters):
            return parameters.asParameters
        case let .custom(dictionary):
            return dictionary
        }
    }
}

struct PartnerTrackParameters: Codable {
    let orgId: String
    let orgName: String

    enum CodingKeys: String, CodingKey {
        case orgId = "org_id"
        case orgName = "org_name"
    }

    init(orgId: String, orgName: String) {
        self.orgId = orgId
        self.orgName = orgName
    }

    init(jwt: String) {
        let decoded = JWTDecode().decode(jwtToken: jwt)
        guard
            let orgId = decoded["jti"] as? String,
            let orgName = decoded["org_name"] as? String else {
                self.init()
                return
            }

        self.init(orgId: orgId, orgName: orgName)
    }

    init() {
        self.init(orgId: "", orgName: "")
    }
}

struct SubscriberTrackParameters: Codable {
    let partnerUserId: String

    enum CodingKeys: String, CodingKey {
        case partnerUserId = "partner_user_id"
    }

    init(partnerUserId: String) {
        self.partnerUserId = partnerUserId
    }

    init(request: CreateLinkRequest) {
        self.init(partnerUserId: request.userId)
    }
}

struct ContentTrackParameters: Codable {
    let contentType: String
    let contentId: String
    let contentName: String

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case contentId = "content_id"
        case contentName = "content_name"
    }

    init(contentType: String, contentId: String, contentName: String) {
        self.contentType = contentType
        self.contentId = contentId
        self.contentName = contentName
    }

    init(
        request: CreateLinkRequest,
        jwtToken: String
    ) {
        let decoded = JWTDecode().decode(jwtToken: jwtToken)
        let orgId = decoded["jti"] as? String ?? ""
        let contentId = request.contentConfig.contentId
        self.init(
            contentType: request.contentConfig.contentType.lowercased(),
            contentId: "\(orgId)#\(contentId)",
            contentName: request.contentConfig.contentName
        )
    }
}

struct ShareLinkTrackParameters: Codable {
    let shareLinkUrl: String
    let shareLinkHash: String

    enum CodingKeys: String, CodingKey {
        case shareLinkUrl = "share_link_url"
        case shareLinkHash = "share_link_hash"
    }
}
*/
