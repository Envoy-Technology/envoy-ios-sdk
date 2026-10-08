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
    /// Default for conforming types written before 0.1.0 (e.g. test doubles): reports no link.
    @MainActor
    func checkDeferredLink(completion: ((Bool) -> Void)?) {
        completion?(false)
    }

    @MainActor
    func checkDeferredLink() {
        checkDeferredLink(completion: nil)
    }
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

    private let pasteboard: PasteboardType
    private let keychain: KeychainType
    private let userDefaults: UserDefaults
    private let pixelEventService: LogPixelEventServiceType
    private let deferredLinkTimeout: TimeInterval

    // State of the deferred-link check and pixel events, touched only on the main thread.
    /// Non-nil while a deferred-link check is in progress; holds the completions waiting for its result.
    private var deferredLinkCompletions: [(Bool) -> Void]?
    /// Tells the check in progress apart from a late answer to a check that already timed out.
    private var deferredLinkCheckID = 0
    private var deferredLinkCheckTimeout: DispatchWorkItem?
    /// Pixel events logged during a deferred-link check, sent once it ends.
    private var pendingPixelEvents: [PendingPixelEvent] = []

    private typealias PendingPixelEvent = (request: LogPixelEventRequest,
                                           completion: (EmptyResponse?, WebError?) -> ())

    nonisolated(unsafe) public static var shared: Envoy!
    public var delegate: EnvoyProtocol?

    public static func initialize(apiKey: String) {
        Envoy.shared = Envoy(apiKey: apiKey)
    }

    init(apiKey: String,
         pasteboard: PasteboardType = SystemPasteboard(),
         keychain: KeychainType = Keychain.standard,
         userDefaults: UserDefaults = .standard,
         pixelEventService: LogPixelEventServiceType? = nil,
         deferredLinkTimeout: TimeInterval = 3) {
        self.apiKey = apiKey
        self.apiUrl = Constants.prodEnvironment

        self.webClient = WebClient(baseURL: self.apiUrl)
        self.pasteboard = pasteboard
        self.keychain = keychain
        self.userDefaults = userDefaults
        self.pixelEventService = pixelEventService
            ?? LogPixelEventService(client: webClient, apiKey: apiKey)
        self.deferredLinkTimeout = deferredLinkTimeout
        self.setupScreenshotNotification()
    }

    // MARK: Deferred link
    /// Reads the clipboard once per install
    /// and returns `true` in completion when Envoy link parameters were found and stored.
    /// On iOS 14+ the clipboard is read only when it contains a web URL, so iOS shows the paste prompt only then.
    /// Calls made while a check is in progress get its result. If the system cannot tell whether
    /// the clipboard holds a URL, or doesn't answer in time, the check is not used up and a later call tries again.
    /// Pixel events logged while the check runs are sent after it, so they carry the attribution.
    /// Can be called from any thread; `completion` is called on the main thread.
    nonisolated public func checkDeferredLink(completion: ((Bool) -> Void)? = nil) {
        onMainThread {
            self.startDeferredLinkCheck(completion: completion)
        }
    }

    private func startDeferredLinkCheck(completion: ((Bool) -> Void)?) {
        if deferredLinkCompletions != nil {
            deferredLinkCompletions?.append { completion?($0) }
            return
        }
        guard userDefaults.isFreshInstall else {
            completion?(false)
            return
        }
        deferredLinkCompletions = [{ completion?($0) }]
        deferredLinkCheckID += 1
        let checkID = deferredLinkCheckID

        // Strong captures: the check must finish even if this instance is replaced meanwhile,
        // and the timeout bounds how long it is kept alive.
        let timeout = DispatchWorkItem {
            self.finishDeferredLinkCheck(checkID, detection: .failure(DeferredLinkCheckTimeout()))
        }
        deferredLinkCheckTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredLinkTimeout, execute: timeout)

        pasteboard.detectProbableWebURL { result in
            self.finishDeferredLinkCheck(checkID, detection: result)
        }
    }

    private func finishDeferredLinkCheck(_ checkID: Int, detection: Swift.Result<Bool, Error>) {
        guard checkID == deferredLinkCheckID, deferredLinkCompletions != nil else {
            return
        }
        deferredLinkCheckTimeout?.cancel()
        deferredLinkCheckTimeout = nil

        let found: Bool
        switch detection {
        case .failure:
            // Keep the check available so a later call can retry.
            found = false
        case .success(false):
            userDefaults.set(isFreshInstall: false)
            found = false
        case .success(true) where !userDefaults.isFreshInstall:
            // Another Envoy instance finished its own check meanwhile and already read the clipboard.
            found = false
        case .success(true):
            // Used up before reading, so a user who denies the paste prompt is not asked again.
            userDefaults.set(isFreshInstall: false)
            found = storeDeferredLinkParameters(from: pasteboard.string)
        }

        // Taken only now, so a call made while the clipboard was read (e.g. with the paste prompt up) gets the result.
        let completions = deferredLinkCompletions ?? []
        deferredLinkCompletions = nil
        // Events held during the check go before anything logged from a completion.
        sendPendingPixelEvents()
        completions.forEach { $0(found) }
    }

    private func storeDeferredLinkParameters(from clipboardLink: String?) -> Bool {
        guard let clipboardLink = clipboardLink,
              let url = URL(string: clipboardLink),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let parameters = components.queryItems else {
            return false
        }
        var didStore = false
        for parameter in parameters {
            if parameter.name == Constants.envoyShareLinkHash,
               let value = parameter.value {
                keychain.set(value, forKey: .envoyShareLinkHash)
                didStore = true
            } else if parameter.name == Constants.envoyLeadUuid,
               let value = parameter.value {
                keychain.set(value, forKey: .envoyLeadUuid)
                didStore = true
            }
        }
        return didStore
    }

    // MARK: Pixel events
    private func sendPixelEvents(_ events: [PendingPixelEvent]) {
        guard !events.isEmpty else { return }
        // Read once per batch, and fresh each time: another Envoy instance may have stored a link meanwhile.
        let attribution = LogPixelEventRequest.Attribution(
            shareLinkHash: keychain.value(forKey: .envoyShareLinkHash),
            leadUuid: keychain.value(forKey: .envoyLeadUuid)
        )
        events.forEach {
            pixelEventService.logPixelEvent(request: $0.request.attributed(with: attribution),
                                            completion: $0.completion)
        }
    }

    private func sendPendingPixelEvents() {
        let events = pendingPixelEvents
        pendingPixelEvents = []
        sendPixelEvents(events)
    }

    // MARK: Threading
    private struct DeferredLinkCheckTimeout: Error {}

    /// Hosts compiled in Swift 5 mode can end up calling the main-actor API off the main thread
    /// (e.g. from another SDK's callback) without a compiler error,
    /// so the deferred-link and pixel-event state is touched on the main thread only.
    private func onMainThread(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            // Handed off to the main queue and only ever run there.
            nonisolated(unsafe) let work = work
            DispatchQueue.main.async {
                work()
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
    
    /// Can be called from any thread.
    nonisolated public func logPixelEvent(request: LogPixelEventRequest,
                                          completion: @escaping (EmptyResponse?, WebError?) -> ()) {
        onMainThread {
            if self.deferredLinkCompletions != nil {
                self.pendingPixelEvents.append((request, completion))
            } else {
                self.sendPixelEvents([(request, completion)])
            }
        }
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
