// The Swift Programming Language
// https://docs.swift.org/swift-book
#if canImport(UIKit)
import Foundation
import Combine
import UIKit

public protocol EnvoyProtocol {
    func userDidTookScreenshot(_ image: UIImage?)
}

public protocol EnvoyType {
    @MainActor
    func checkDeferredLink(completion: ((Bool) -> Void)?)
    @MainActor
    func pushShareGift(
        in navigationController: UINavigationController,
        request: CreateLinkRequest
    )
    @MainActor
    func presentShareGift(
        from viewController: UIViewController,
        request: CreateLinkRequest
    )
    @MainActor
    func giftButton(request: CreateLinkRequest) -> UIButton
    @MainActor
    func createLink(request: CreateLinkRequest,
                    completion: @escaping (CreateLinkResponse?, WebError?) -> ())
    @MainActor
    func prepLink(request: PrepLinkRequest,
                    completion: @escaping (PrepLinkResponse?, WebError?) -> ())
    @MainActor
    func manageLinks(request: ManageLinksRequest,
                     completion: @escaping (ManageLinksResponse?, WebError?) -> ())
    @MainActor
    func clearManagedLinks(completion: @escaping (ClearManagedLinksResponse?, WebError?) -> ())
    @MainActor
    func getUserRemainingQuota(userId: String,
                               completion: @escaping (UserQuotaResponse?, WebError?) -> ())
    @MainActor
    func logPixelEvent(request: LogPixelEventRequest,
                       completion: @escaping (EmptyResponse?, WebError?) -> ())
    @MainActor
    func getUserRewards(userId: String,
                        completion: @escaping (UserRewardsResponse?, WebError?) -> ())
    @MainActor
    func claimUserReward(request: ClaimUserRewardRequest,
                         completion: @escaping (ClaimUserRewardResponse?, WebError?) -> ())
    @MainActor
    func getUserCurrentRewards(
        userId: String,
        completion: @escaping (UserCurrentRewardsResponse?, WebError?) -> ())
}

public extension EnvoyType {
    @MainActor
    func checkDeferredLink() {
        checkDeferredLink(completion: nil)
    }
}

@available(iOS 13.0, *)
public final class Envoy: ObservableObject {
    private enum Constants {
        static let devEnvironment = "https://dev-api.envoy.is/partner/"
        static let prodEnvironment = "https://api.envoy.is/partner/"
    }
    
    private let apiKey: String
    private let apiUrl: String

    fileprivate let webClient: WebClient
    fileprivate var notificationObserver: NSObjectProtocol?

    private let pixelEventService: LogPixelEventServiceType
    private let deferredLinks: DeferredLinkCoordinator

    nonisolated(unsafe) public static var shared: Envoy!
    public var delegate: EnvoyProtocol?

    public static func initialize(apiKey: String) {
        Envoy.shared = Envoy(apiKey: apiKey)
    }

    init(apiKey: String,
         pixelEventService: LogPixelEventServiceType? = nil,
         deferredLinks: DeferredLinkCoordinator = .shared) {
        self.apiKey = apiKey
        self.apiUrl = Constants.prodEnvironment

        self.webClient = WebClient(baseURL: self.apiUrl)
        self.pixelEventService = pixelEventService
            ?? LogPixelEventService(client: webClient, apiKey: apiKey)
        self.deferredLinks = deferredLinks
        self.setupScreenshotNotification()
    }

    // MARK: Deferred link
    /// Reads the clipboard once per install, within a day of installing,
    /// and returns `true` in completion when Envoy link parameters were found and stored.
    /// On iOS 14+ the clipboard is read only when it contains a web URL, so iOS shows the paste prompt only then,
    /// and only while the app is active.
    /// Calls made while a check is in progress, from any `Envoy` instance, get its result.
    /// If the check can't finish (the system fails twice or doesn't answer within 30 seconds),
    /// it is not used up and a later call tries again.
    /// Pixel events logged while the check runs are sent after it, so they carry the attribution.
    /// Can be called from any thread; `completion` is called on the main thread, never before this returns,
    /// and at most 3 seconds later.
    nonisolated public func checkDeferredLink(completion: ((Bool) -> Void)? = nil) {
        deferredLinks.checkDeferredLink(completion: completion)
    }

    // MARK: Screenshot capture
    //
    // We snapshot the foreground key window the moment iOS posts
    // `userDidTakeScreenshotNotification`. This needs no Photos-library
    // permission, runs synchronously, and delivers exactly what the user
    // saw — sidestepping the iOS 26 / iPhone 17 Pro "Full-Screen Preview"
    // flow that delays or prevents the screenshot from reaching Photos.
    func setupScreenshotNotification() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let image = Self.captureKeyWindowImage()
            self.delegate?.userDidTookScreenshot(image)
        }
    }

    private static func captureKeyWindowImage() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows
            .first(where: { $0.isKeyWindow }) else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }
}

@available(iOS 13.0, *)
extension Envoy: EnvoyType {
    @MainActor
    public func pushShareGift(in navigationController: UINavigationController,
                              request: CreateLinkRequest) {
        navigationController.pushViewController(shareGiftViewController(request: request),
                                                animated: true)
    }
    
    public func presentShareGift(from viewController: UIViewController,
                                 request: CreateLinkRequest) {
        let parentViewController = viewController.navigationController ?? viewController
        let viewController = shareGiftViewController(request: request)
        let navigationController = UINavigationController(rootViewController: viewController)
        navigationController.modalPresentationStyle = .fullScreen
        parentViewController.present(navigationController, animated: true)
    }
    
    public func giftButton(request: CreateLinkRequest) -> UIButton {
        let button = GiftButton(type: .custom)
        button.token = apiKey
        button.request = request
        button.initialize()
        return button
    }
    
    public func createLink(request: CreateLinkRequest,
                           completion: @escaping (CreateLinkResponse?, WebError?) -> ()) {
        CreateLinkService(client: self.webClient, apiKey: self.apiKey)
            .createLink(request: request, completion: completion)
    }
    
    public func prepLink(request: PrepLinkRequest,
                           completion: @escaping (PrepLinkResponse?, WebError?) -> ()) {
        PrepLinkService(client: self.webClient, apiKey: self.apiKey)
            .prepLink(request: request, completion: completion)
    }

    public func manageLinks(request: ManageLinksRequest,
                            completion: @escaping (ManageLinksResponse?, WebError?) -> ()) {
        ManageLinksService(client: self.webClient, apiKey: self.apiKey)
            .manageLinks(request: request, completion: completion)
    }

    public func clearManagedLinks(completion: @escaping (ClearManagedLinksResponse?, WebError?) -> ()) {
        ClearManagedLinksService(client: self.webClient, apiKey: self.apiKey)
            .clearManagedLinks(completion: completion)
    }

    public func getUserRemainingQuota(userId: String,
                                      completion: @escaping (UserQuotaResponse?, WebError?) -> ()) {
        GetUserRemainingQuotaService(client: self.webClient, apiKey: self.apiKey)
            .getUserQuota(userId: userId, completion: completion)
    }
    
    /// Can be called from any thread.
    nonisolated public func logPixelEvent(request: LogPixelEventRequest,
                                          completion: @escaping (EmptyResponse?, WebError?) -> ()) {
        deferredLinks.logPixelEvent(request, service: pixelEventService, completion: completion)
    }
    
    public func getUserRewards(userId: String,
                               completion: @escaping (UserRewardsResponse?, WebError?) -> ()) {
        GetUserRewardsService(client: self.webClient, apiKey: self.apiKey)
            .getUserRewards(userId: userId, completion: completion)
    }
    
    public func claimUserReward(request: ClaimUserRewardRequest,
                                completion: @escaping (ClaimUserRewardResponse?, WebError?) -> ()) {
        ClaimUserRewardService(client: self.webClient, apiKey: self.apiKey)
            .claimUserReward(request: request, completion: completion)
    }
    
    public func getUserCurrentRewards(
        userId: String,
        completion: @escaping (UserCurrentRewardsResponse?, WebError?) -> ()) {
            GetUserCurrentRewardsService(client: self.webClient, apiKey: self.apiKey)
                .getUserCurrentRewards(userId: userId, completion: completion)
    }
}

@available(iOS 13.0, *)
private extension Envoy {
    @MainActor
    func shareGiftViewController(request: CreateLinkRequest) -> UIViewController {
        let viewController = ShareGiftBuilder.viewController(
            request: request,
            apiKey: apiKey,
            baseURL: self.apiUrl)
        viewController.modalPresentationStyle = .fullScreen
        return viewController
    }
}
#endif
