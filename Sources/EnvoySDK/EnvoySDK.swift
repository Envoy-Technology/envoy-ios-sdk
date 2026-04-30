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

@available(iOS 13.0, *)
public final class Envoy: ObservableObject {
    private enum Constants {
        static let envoyShareLinkHash = "envoy_share_link_hash"
        static let envoyLeadUuid = "envoy_lead_uuid"
        static let devEnvironment = "https://dev-api.envoy.is/partner/"
        static let prodEnvironment = "https://api.envoy.is/partner/"
    }
    
    private let apiKey: String
    private let apiUrl: String

    fileprivate let webClient: WebClient
    fileprivate var notificationObserver: NSObjectProtocol?

    nonisolated(unsafe) public static var shared: Envoy!
    public var delegate: EnvoyProtocol?

    public static func initialize(apiKey: String) {
        Envoy.shared = Envoy(apiKey: apiKey)
    }

    private init(apiKey: String) {
        self.apiKey = apiKey
        self.apiUrl = Constants.prodEnvironment

        self.webClient = WebClient(baseURL: self.apiUrl)
        self.setupScreenshotNotification()
        if UserDefaults.standard.isFreshInstall {
            UserDefaults.standard.set(isFreshInstall: false)
            guard let clipboardLink = UIPasteboard.general.string,
                  let url = URL(string: clipboardLink),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  let parameters = components.queryItems else {
                return
            }
            for parameter in parameters {
                if parameter.name == Constants.envoyShareLinkHash,
                   let value = parameter.value {
                    Keychain.standard.set(value, forKey: .envoyShareLinkHash)
                } else if parameter.name == Constants.envoyLeadUuid,
                   let value = parameter.value {
                    Keychain.standard.set(value, forKey: .envoyLeadUuid)
                }
            }
        }
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
    
    public func logPixelEvent(request: LogPixelEventRequest,
                              completion: @escaping (EmptyResponse?, WebError?) -> ()) {
        LogPixelEventService(client: self.webClient, apiKey: self.apiKey)
            .logPixelEvent(request: request, completion: completion)
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
