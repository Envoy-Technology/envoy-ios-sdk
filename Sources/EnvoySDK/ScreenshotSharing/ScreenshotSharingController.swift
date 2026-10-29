#if canImport(UIKit)
import UIKit

/// While a screen has it turned on, answers each screenshot by creating the screen's link
/// and opening the system share sheet with it, previewed with the article image.
@MainActor
final class ScreenshotSharingController {
    typealias ShareProvider = () -> ScreenshotShare?
    typealias EventHandler = (ScreenshotSharingEvent) -> Void
    typealias BeforeSharing = (ScreenshotSharePrompt) -> Void
    /// Presents the share sheet over `viewController`; returns false when it can't be shown.
    typealias PresentShareSheet = @MainActor (_ items: [Any],
                                              _ viewController: UIViewController,
                                              _ completion: @escaping (UIActivity.ActivityType?, Bool) -> Void) -> Bool
    /// Calls `completion` with the image, or nil when it can't be loaded in time; returns a function that cancels it.
    typealias LoadImage = @MainActor (_ url: URL, _ completion: @escaping @MainActor (UIImage?) -> Void) -> () -> Void

    private struct Session {
        let id: Int
        weak var viewController: UIViewController?
        let share: ShareProvider
        let onEvent: EventHandler?
        let beforeSharing: BeforeSharing?
    }

    /// From the screenshot until both the link and the preview image are ready.
    private final class Preparation {
        let sessionID: Int
        let share: ScreenshotShare
        var link: CreateLinkResponse?
        var isImageLoaded = false
        var image: UIImage?
        var cancelImage: (() -> Void)?

        init(sessionID: Int, share: ScreenshotShare) {
            self.sessionID = sessionID
            self.share = share
        }
    }

    private let createLinkService: CreateLinkServiceType
    private let notificationCenter: NotificationCenter
    private let isApplicationActive: @MainActor () -> Bool
    private let presentShareSheet: PresentShareSheet
    private let loadImage: LoadImage

    private var session: Session?
    private var sessionCount = 0
    private var screenshotObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    /// Your screen is shown; nothing is created until it's resolved.
    private var prompt: ScreenshotSharePrompt?
    private var linkTask: URLSessionDataTask?
    private var preparation: Preparation?
    private var isPresenting = false
    /// Links created in this app session, by request, so more screenshots of the same content reuse them.
    private var createdLinks: [Data: CreateLinkResponse] = [:]
    private var loadedImages: [URL: UIImage] = [:]

    /// From the screenshot until the share sheet closes; screenshots taken meanwhile are ignored.
    private var isBusy: Bool {
        prompt != nil || preparation != nil || activationObserver != nil || isPresenting
    }

    init(createLinkService: CreateLinkServiceType,
         notificationCenter: NotificationCenter = .default,
         isApplicationActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active },
         presentShareSheet: @escaping PresentShareSheet = ScreenshotSharingController.presentActivityViewController,
         loadImage: @escaping LoadImage = ScreenshotSharingController.downloadImage) {
        self.createLinkService = createLinkService
        self.notificationCenter = notificationCenter
        self.isApplicationActive = isApplicationActive
        self.presentShareSheet = presentShareSheet
        self.loadImage = loadImage
    }

    /// Replaces the screen started earlier, if any.
    func start(from viewController: UIViewController,
               onEvent: EventHandler?,
               beforeSharing: BeforeSharing? = nil,
               share: @escaping ShareProvider) {
        stop()
        sessionCount += 1
        session = Session(id: sessionCount,
                          viewController: viewController,
                          share: share,
                          onEvent: onEvent,
                          beforeSharing: beforeSharing)
        screenshotObserver = notificationCenter.addObserver(forName: UIApplication.userDidTakeScreenshotNotification,
                                                            object: nil,
                                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.userDidTakeScreenshot()
            }
        }
    }

    /// A link or image still loading is dropped; a share sheet already open stays open.
    func stop() {
        guard session != nil else { return }
        session = nil
        if let screenshotObserver = screenshotObserver {
            notificationCenter.removeObserver(screenshotObserver)
        }
        screenshotObserver = nil
        prompt = nil
        stopWaitingForActivation()
        linkTask?.cancel()
        linkTask = nil
        preparation?.cancelImage?()
        preparation = nil
    }

    private func userDidTakeScreenshot() {
        guard let session = session, !isBusy, let share = session.share() else { return }
        guard let beforeSharing = session.beforeSharing else {
            prepare(share, in: session)
            return
        }
        let prompt = ScreenshotSharePrompt(content: share) { [weak self] prompt, accepted in
            self?.promptResolved(prompt, share: accepted)
        }
        self.prompt = prompt
        beforeSharing(prompt)
    }

    /// A prompt of a stopped screen has already been dropped.
    private func promptResolved(_ prompt: ScreenshotSharePrompt, share: Bool) {
        guard self.prompt === prompt, let session = session else { return }
        self.prompt = nil
        if share {
            prepare(prompt.content, in: session)
        }
    }

    private func prepare(_ share: ScreenshotShare, in session: Session) {
        let preparation = Preparation(sessionID: session.id, share: share)
        self.preparation = preparation
        startLoadingImage(for: preparation)

        let cacheKey = Self.cacheKey(for: share.request)
        if let cacheKey = cacheKey, let link = createdLinks[cacheKey] {
            preparation.link = link
            session.onEvent?(.linkCreated(link))
            presentIfReady(preparation)
            return
        }

        session.onEvent?(.creatingLink)
        linkTask = createLinkService.createLink(request: share.request, completion: Self.onMain { [weak self] response, error in
            self?.linkCreated(response, error: error, preparation: preparation, cacheKey: cacheKey)
        })
    }

    /// Loaded together with the link; the share sheet opens without it if it isn't ready in time.
    private func startLoadingImage(for preparation: Preparation) {
        let setting = preparation.share.request.contentSetting
        guard let string = setting.previewImage ?? setting.common?.poster, let url = URL(string: string) else {
            preparation.isImageLoaded = true
            return
        }
        if let image = loadedImages[url] {
            preparation.image = image
            preparation.isImageLoaded = true
            return
        }
        preparation.cancelImage = loadImage(url) { [weak self] image in
            guard let self = self, self.preparation === preparation else { return }
            preparation.cancelImage = nil
            preparation.isImageLoaded = true
            preparation.image = image
            if let image = image {
                self.loadedImages[url] = image
            }
            self.presentIfReady(preparation)
        }
    }

    private func linkCreated(_ response: CreateLinkResponse?,
                             error: WebError?,
                             preparation: Preparation,
                             cacheKey: Data?) {
        // A stopped screen has already dropped its link.
        guard self.preparation === preparation, let session = session, session.id == preparation.sessionID else { return }
        linkTask = nil
        guard let response = response else {
            preparation.cancelImage?()
            self.preparation = nil
            session.onEvent?(.failed(error ?? .other))
            return
        }
        if let cacheKey = cacheKey {
            createdLinks[cacheKey] = response
        }
        preparation.link = response
        session.onEvent?(.linkCreated(response))
        presentIfReady(preparation)
    }

    private func presentIfReady(_ preparation: Preparation) {
        guard self.preparation === preparation,
              let link = preparation.link,
              preparation.isImageLoaded,
              let session = session,
              session.id == preparation.sessionID else { return }
        self.preparation = nil
        present(link, share: preparation.share, image: preparation.image, in: session)
    }

    private func present(_ link: CreateLinkResponse, share: ScreenshotShare, image: UIImage?, in session: Session) {
        guard isApplicationActive() else {
            // The system screenshot preview can cover the app; the share sheet opens once the app is back.
            let sessionID = session.id
            waitForActivation { [weak self] in
                guard let self = self, let session = self.session, session.id == sessionID else { return }
                self.present(link, share: share, image: image, in: session)
            }
            return
        }
        guard let viewController = session.viewController else { return }

        var items: [Any] = []
        if let message = share.message {
            items.append(message)
        }
        if let url = URL(string: link.url) {
            items.append(ShareLinkItemSource(url: url, title: share.request.contentSetting.contentName, image: image))
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

    static let imageTimeout: TimeInterval = 2

    static func downloadImage(url: URL, completion: @escaping @MainActor (UIImage?) -> Void) -> () -> Void {
        nonisolated(unsafe) let completion = completion
        let task = URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: imageTimeout)) { data, response, _ in
            let isOK = (response as? HTTPURLResponse)?.statusCode == 200
            nonisolated(unsafe) let image = isOK ? data.flatMap { UIImage(data: $0) } : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(image)
                }
            }
        }
        task.resume()
        // Cancelling completes the task without an image.
        DispatchQueue.main.asyncAfter(deadline: .now() + imageTimeout) {
            task.cancel()
        }
        return { task.cancel() }
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
