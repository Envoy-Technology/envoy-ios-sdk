import Foundation
// base64_file: str
public struct CreateLinkRequest: Codable {
    let autoplay: Bool?
    let contentSetting: ContentSetting
    let lifespanAfterClick: LifespanAfterClick?
    let openQuota: Int?
    let extra: String?
    let sharerId: String
    let isSandbox: Bool?
    let labels: [Label]?

    public init(autoplay: Bool?, contentSetting: ContentSetting,
                lifespanAfterClick: LifespanAfterClick? = nil,
                openQuota: Int? = nil, extra: String? = nil,
                sharerId: String, isSandbox: Bool? = nil, labels: [Label]? = nil) {
        self.autoplay = autoplay
        self.contentSetting = contentSetting
        self.lifespanAfterClick = lifespanAfterClick
        self.openQuota = openQuota
        self.extra = extra
        self.sharerId = sharerId
        self.isSandbox = isSandbox
        self.labels = labels
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

    // Define the ContentProtection structure
    public struct ContentProtection: Codable {
        let media: Common

        public init(media: Common) {
            self.media = media
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
