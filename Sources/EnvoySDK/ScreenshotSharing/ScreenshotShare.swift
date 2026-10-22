#if canImport(UIKit)
import UIKit

/// What to share when the user takes a screenshot: the link to create and the text sent with it.
public struct ScreenshotShare {
    public let request: CreateLinkRequest
    /// Shared together with the link, e.g. "Your friend wants to gift you this article".
    public let message: String?

    public init(request: CreateLinkRequest, message: String? = nil) {
        self.request = request
        self.message = message
    }
}

/// Progress of the sharing started by a screenshot.
public enum ScreenshotSharingEvent {
    /// The link is being created; the share sheet opens when it's ready.
    case creatingLink
    /// The link was created, or reused from an earlier screenshot of the same content.
    case linkCreated(CreateLinkResponse)
    /// The user shared the link. `activityType` is nil when the system doesn't tell where.
    case shared(activityType: UIActivity.ActivityType?)
    /// The user closed the share sheet without sharing.
    case cancelled
    /// The link couldn't be created, so no share sheet was shown.
    case failed(WebError)
}
#endif
