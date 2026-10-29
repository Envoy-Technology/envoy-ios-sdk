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

/// A screenshot waiting for your own screen, e.g. a "Send a gift" sheet, before anything is shared.
/// No link is created, so no quota is used, until `share()` is called.
@MainActor
public final class ScreenshotSharePrompt {
    /// What `share()` shares, as returned for this screenshot.
    public let content: ScreenshotShare
    private var onResolved: ((ScreenshotSharePrompt, _ share: Bool) -> Void)?

    init(content: ScreenshotShare, onResolved: @escaping (ScreenshotSharePrompt, _ share: Bool) -> Void) {
        self.content = content
        self.onResolved = onResolved
    }

    /// Creates the link and opens the system share sheet with it. Only the first `share()` or `cancel()` counts.
    public func share() {
        resolve(share: true)
    }

    /// Nothing is shared and no link is created. Call it when your screen is closed without sharing.
    public func cancel() {
        resolve(share: false)
    }

    private func resolve(share: Bool) {
        guard let onResolved = onResolved else { return }
        self.onResolved = nil
        onResolved(self, share)
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
