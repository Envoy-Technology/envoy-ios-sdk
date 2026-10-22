#if canImport(UIKit)
import UIKit

/// While a screen has it turned on, answers each screenshot by creating the screen's link
/// and opening the system share sheet with it.
@MainActor
final class ScreenshotSharingController {
    typealias ShareProvider = () -> ScreenshotShare?
    typealias EventHandler = (ScreenshotSharingEvent) -> Void
    /// Presents the share sheet over `viewController`; returns false when it can't be shown.
    typealias PresentShareSheet = @MainActor (_ items: [Any],
                                              _ viewController: UIViewController,
                                              _ completion: @escaping (UIActivity.ActivityType?, Bool) -> Void) -> Bool

    private struct Session {
        let id: Int
        weak var viewController: UIViewController?
        let share: ShareProvider
        let onEvent: EventHandler?
    }

    private let createLinkService: CreateLinkServiceType
    private let notificationCenter: NotificationCenter
    private let isApplicationActive: @MainActor () -> Bool
    private let presentShareSheet: PresentShareSheet

    private var session: Session?
    private var sessionCount = 0
    private var screenshotObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var linkTask: URLSessionDataTask?
    private var isCreatingLink = false
    private var isPresenting = false
    /// Links created in this app session, by request, so more screenshots of the same content reuse them.
    private var createdLinks: [Data: CreateLinkResponse] = [:]

    /// From the screenshot until the share sheet closes; screenshots taken meanwhile are ignored.
    private var isBusy: Bool {
        isCreatingLink || activationObserver != nil || isPresenting
    }

    init(createLinkService: CreateLinkServiceType,
         notificationCenter: NotificationCenter = .default,
         isApplicationActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
         presentShareSheet: @escaping PresentShareSheet = ScreenshotSharingController.presentActivityViewController) {
        self.createLinkService = createLinkService
        self.notificationCenter = notificationCenter
        self.isApplicationActive = isApplicationActive
        self.presentShareSheet = presentShareSheet
    }

    /// Replaces the screen started earlier, if any.
    func start(from viewController: UIViewController, onEvent: EventHandler?, share: @escaping ShareProvider) {
        stop()
        sessionCount += 1
        session = Session(id: sessionCount, viewController: viewController, share: share, onEvent: onEvent)
        screenshotObserver = notificationCenter.addObserver(forName: UIApplication.userDidTakeScreenshotNotification,
                                                            object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.userDidTakeScreenshot()
            }
        }
    }

    /// A link still being created is dropped; a share sheet already open stays open.
    func stop() {
        guard session != nil else { return }
        session = nil
        if let screenshotObserver = screenshotObserver {
            notificationCenter.removeObserver(screenshotObserver)
        }
        screenshotObserver = nil
        stopWaitingForActivation()
        linkTask?.cancel()
        linkTask = nil
        isCreatingLink = false
    }

    private func userDidTakeScreenshot() {
        guard let session = session, !isBusy, let share = session.share() else { return }
        let cacheKey = Self.cacheKey(for: share.request)
        if let cacheKey = cacheKey, let link = createdLinks[cacheKey] {
            session.onEvent?(.linkCreated(link))
            present(link, message: share.message, in: session)
            return
        }

        isCreatingLink = true
        session.onEvent?(.creatingLink)
        let sessionID = session.id
        linkTask = createLinkService.createLink(request: share.request, completion: Self.onMain { [weak self] response, error in
            self?.linkCreated(response, error: error, sessionID: sessionID, cacheKey: cacheKey, message: share.message)
        })
    }

    private func linkCreated(_ response: CreateLinkResponse?,
                             error: WebError?,
                             sessionID: Int,
                             cacheKey: Data?,
                             message: String?) {
        // A stopped screen has already dropped its link.
        guard let session = session, session.id == sessionID else { return }
        isCreatingLink = false
        linkTask = nil
        guard let response = response else {
            session.onEvent?(.failed(error ?? .other))
            return
        }
        if let cacheKey = cacheKey {
            createdLinks[cacheKey] = response
        }
        session.onEvent?(.linkCreated(response))
        present(response, message: message, in: session)
    }

    private func present(_ link: CreateLinkResponse, message: String?, in session: Session) {
        guard isApplicationActive() else {
            // The system screenshot preview can cover the app; the share sheet opens once the app is back.
            let sessionID = session.id
            waitForActivation { [weak self] in
                guard let self = self, let session = self.session, session.id == sessionID else { return }
                self.present(link, message: message, in: session)
            }
            return
        }
        guard let viewController = session.viewController else { return }

        var items: [Any] = []
        if let message = message {
            items.append(message)
        }
        if let url = URL(string: link.url) {
            items.append(url)
        } else {
            items.append(link.url)
        }

        let onEvent = session.onEvent
        isPresenting = true
        let presented = presentShareSheet(items, viewController) { [weak self] activityType, completed in
            self?.isPresenting = false
            onEvent?(completed ? .shared(activityType: activityType) : .cancelled)
        }
        if !presented {
            isPresenting = false
        }
    }

    // MARK: App activation

    private func waitForActivation(then work: @escaping () -> Void) {
        stopWaitingForActivation()
        nonisolated(unsafe) let work = work
        activationObserver = notificationCenter.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                            object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopWaitingForActivation()
                work()
            }
        }
    }

    private func stopWaitingForActivation() {
        if let activationObserver = activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    // MARK: Helpers

    /// The same request gives the same key, whatever the order of its `extra` keys.
    private static func cacheKey(for request: CreateLinkRequest) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(request)
    }

    /// Network completions arrive on a background queue; `work` runs on the main queue.
    nonisolated private static func onMain(
        _ work: @escaping @MainActor (CreateLinkResponse?, WebError?) -> Void
    ) -> (CreateLinkResponse?, WebError?) -> Void {
        nonisolated(unsafe) let work = work
        return { response, error in
            nonisolated(unsafe) let response = response
            nonisolated(unsafe) let error = error
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    work(response, error)
                }
            }
        }
    }

    static func presentActivityViewController(items: [Any],
                                              over viewController: UIViewController,
                                              completion: @escaping (UIActivity.ActivityType?, Bool) -> Void) -> Bool {
        guard viewController.viewIfLoaded?.window != nil else { return false }
        var presenter = viewController
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }

        let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil)
        nonisolated(unsafe) let completion = completion
        activityViewController.completionWithItemsHandler = { activityType, completed, _, _ in
            MainActor.assumeIsolated {
                completion(activityType, completed)
            }
        }
        // Required on iPad; centered without an arrow, as nothing on screen was tapped.
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activityViewController, animated: true)
        return true
    }
}
#endif
