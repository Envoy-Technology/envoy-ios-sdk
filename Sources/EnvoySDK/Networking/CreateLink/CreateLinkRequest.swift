import Foundation
// base64_file: str
public struct CreateLinkRequest: Codable {
    let autoplay: Bool?
    let contentSetting: ContentSetting
    let lifespanAfterClick: LifespanAfterClick?
    let openQuota: Int?
    let extra: [String: String]?
    let sharerId: String
    let isSandbox: Bool?
    let labels: [Label]?
    let isCarousel: Bool?
    let isCarouselLink: Bool?

    public init(autoplay: Bool?, contentSetting: ContentSetting,
                lifespanAfterClick: LifespanAfterClick? = nil,
                openQuota: Int? = nil, extra: [String: String]? = nil,
                sharerId: String, isSandbox: Bool? = nil, labels: [Label]? = nil, isCarousel: Bool? = false, isCarouselLink: Bool? = false) {
        self.autoplay = autoplay
        self.contentSetting = contentSetting
        self.lifespanAfterClick = lifespanAfterClick
        self.openQuota = openQuota
        self.extra = extra
        self.sharerId = sharerId
        self.isSandbox = isSandbox
        self.labels = labels
        self.isCarousel = isCarousel
        self.isCarouselLink = isCarouselLink
    }
    
    // Define the Common structure
    public struct Common: Codable {
        let source: String
        let sourceIsRedirect: Bool?
        let poster: String?

        public init(source: String, sourceIsRedirect: Bool?, poster: String?) {
            self.source = source
            self.sourceIsRedirect = sourceIsRedirect
            self.poster = poster
        }
    }

    /// DRM for the link's video or audio, played on the gift landing by Shaka Player
    /// (see https://docs.envoy.is/guides/drm/). Needs `sources`, `drm` or both.
    public struct ContentProtection: Codable {
        /// A manifest per key system (`KeySystem`), for browsers using that DRM system;
        /// others play `common.source` (e.g. common = DASH, sources = HLS for FairPlay).
        let sources: [String: String]?
        /// Shaka Player's DRM configuration.
        let drm: DRMConfig?
        /// The FairPlay license request format of your DRM provider; without it the raw SPC is sent.
        let fairPlayProvider: FairPlayProvider?

        public init(sources: [String: String]? = nil, drm: DRMConfig? = nil, fairPlayProvider: FairPlayProvider? = nil) {
            self.sources = sources
            self.drm = drm
            self.fairPlayProvider = fairPlayProvider
        }
    }

    /// Key system IDs, the keys of `ContentProtection.sources`, `DRMConfig.servers` and `DRMConfig.advanced`.
    public enum KeySystem {
        public static let widevine = "com.widevine.alpha"
        public static let playReady = "com.microsoft.playready"
        public static let fairPlay = "com.apple.fps"
        public static let clearKey = "org.w3.clearkey"
    }

    /// Shaka Player's FairPlay presets.
    public enum FairPlayProvider: String, Codable {
        case verimatrix, ezdrm, conax, expressplay, mux, gumlet
    }

    /// Shaka Player's `drm` configuration: license servers and per-key-system settings.
    public struct DRMConfig: Codable {
        /// The license server URL per key system.
        let servers: [String: String]
        let advanced: [String: AdvancedDRMConfig]?

        public init(servers: [String: String], advanced: [String: AdvancedDRMConfig]? = nil) {
            self.servers = servers
            self.advanced = advanced
        }
    }

    /// Shaka Player's per-key-system `drm.advanced` settings. Sent with Shaka's camelCase names
    /// (`serverCertificate`, ...): it encodes as a dictionary, whose keys `.convertToSnakeCase` leaves alone.
    public struct AdvancedDRMConfig: Codable {
        /// The server certificate, base64-encoded (FairPlay needs one, or `serverCertificateUri`).
        let serverCertificate: String?
        /// A URL the player downloads the server certificate from.
        let serverCertificateUri: String?
        /// Headers added to this key system's license requests.
        let headers: [String: String]?

        public init(serverCertificate: String? = nil, serverCertificateUri: String? = nil, headers: [String: String]? = nil) {
            self.serverCertificate = serverCertificate
            self.serverCertificateUri = serverCertificateUri
            self.headers = headers
        }

        private enum Value: Codable {
            case string(String)
            case headers([String: String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let string = try? container.decode(String.self) {
                    self = .string(string)
                } else {
                    self = .headers(try container.decode([String: String].self))
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .string(let string): try container.encode(string)
                case .headers(let headers): try container.encode(headers)
                }
            }
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.singleValueContainer().decode([String: Value].self)
            func string(_ key: String) -> String? {
                if case .string(let value)? = values[key] { return value }
                return nil
            }
            serverCertificate = string("serverCertificate")
            serverCertificateUri = string("serverCertificateUri")
            if case .headers(let value)? = values["headers"] { headers = value } else { headers = nil }
        }

        public func encode(to encoder: Encoder) throws {
            var values: [String: Value] = [:]
            if let serverCertificate { values["serverCertificate"] = .string(serverCertificate) }
            if let serverCertificateUri { values["serverCertificateUri"] = .string(serverCertificateUri) }
            if let headers { values["headers"] = .headers(headers) }
            var container = encoder.singleValueContainer()
            try container.encode(values)
        }
    }

    // Define the ContentSetting structure
    public struct ContentSetting: Codable {
        public enum VideoOrientation: String {
            case horizontal
            case vertical
        }
        
        let contentType: String
        let contentName: String
        let contentDescription: String
        let common: Common?
        let base64_file: String?
        let timeLimit: Int?
        let timeStart: Int?
        let availableFrom: String?
        let availableTo: String?
        let videoOrientation: String?
        let previewTitle: String?
        let previewDescription: String?
        let previewImage: String?
        let mandatoryEmail: Bool?
        let modalTitle: String?
        let buttonText: String?
        let contentProtection: ContentProtection?

        public init(contentType: String, contentName: String, contentDescription: String, common: Common? = nil, base64_file: String? = nil,
                    timeLimit: Int? = nil, timeStart: Int? = nil, availableFrom: String? = nil, availableTo: String? = nil,
                    videoOrientation: VideoOrientation? = nil, previewTitle: String? = nil, previewDescription: String? = nil,
                    previewImage: String? = nil, mandatoryEmail: Bool? = nil,
                    modalTitle: String? = nil, buttonText: String? = nil, contentProtection: ContentProtection? = nil) {
            self.contentType = contentType
            self.contentName = contentName
            self.contentDescription = contentDescription
            self.common = common
            self.base64_file = base64_file
            self.timeLimit = timeLimit
            self.timeStart = timeStart
            self.availableFrom = availableFrom
            self.availableTo = availableTo
            self.videoOrientation = videoOrientation?.rawValue
            self.previewTitle = previewTitle
            self.previewDescription = previewDescription
            self.previewImage = previewImage
            self.mandatoryEmail = mandatoryEmail
            self.modalTitle = modalTitle
            self.buttonText = buttonText
            self.contentProtection = contentProtection
        }
    }

    // Define the LifespanAfterClick structure
    public struct LifespanAfterClick: Codable {
        let value: Int?
        let unit: String

        public init(value: Int?, unit: String) {
            self.value = value
            self.unit = unit
        }
    }

    // Define the Label structure
    public struct Label: Codable {
        let id: Int?
        let text: String
        let color: String

        public init(id: Int?, text: String, color: String) {
            self.id = id
            self.text = text
            self.color = color
        }
    }

}

public extension CreateLinkRequest {
    enum ContentType: String {
        case video = "VIDEO"
        case audio = "AUDIO"
        case htmlPlain = "HTML_PLAIN"
        case htmlSource = "HTML_SOURCE"
        case screenshot = "SCREENSHOT"
    }

    /// A link to the article at `url`. With `.screenshot` the gift landing shows a screenshot of the page,
    /// which Envoy renders from `url`; with `.htmlSource` it shows the page itself.
    /// `id` is sent in `extra` as "articleId", next to `extra`; `title`, `description` and `imageURL`
    /// also make the link preview in messaging apps.
    static func forArticle(url: String,
                           id: String,
                           title: String,
                           description: String,
                           sharerId: String,
                           contentType: ContentType,
                           imageURL: String? = nil,
                           extra: [String: String] = [:],
                           isSandbox: Bool? = nil) -> CreateLinkRequest {
        let contentSetting = ContentSetting(
            contentType: contentType.rawValue,
            contentName: title,
            contentDescription: description,
            common: Common(source: url, sourceIsRedirect: false, poster: imageURL),
            previewTitle: title,
            previewDescription: description,
            previewImage: imageURL)
        return CreateLinkRequest(autoplay: nil,
                                 contentSetting: contentSetting,
                                 extra: extra.merging(["articleId": id]) { _, articleId in articleId },
                                 sharerId: sharerId,
                                 isSandbox: isSandbox)
    }
}
