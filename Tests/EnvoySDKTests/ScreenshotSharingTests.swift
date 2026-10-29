import XCTest
import UIKit
@testable import EnvoySDK

final class FakeCreateLinkService: CreateLinkServiceType {
    private(set) var requests: [CreateLinkRequest] = []
    private var completions: [(CreateLinkResponse?, WebError?) -> ()] = []

    func createLink(request: CreateLinkRequest,
                    completion: @escaping (CreateLinkResponse?, WebError?) -> ()) -> URLSessionDataTask? {
        requests.append(request)
        completions.append(completion)
        return nil
    }

    /// Answers the oldest request, from a background queue like the real service.
    func finish(url: String = "https://envoy.is/l/abc", error: WebError? = nil) {
        let completion = completions.removeFirst()
        let response = error == nil
            ? CreateLinkResponse(url: url, userRemainingQuota: 3, modaltitle: nil, mandatoryEmail: nil, buttonText: nil)
            : nil
        DispatchQueue.global().sync {
            completion(response, error)
        }
    }
}

final class FakeShareSheet {
    var canPresent = true
    private(set) var presentedItems: [[Any]] = []
    private var completion: ((UIActivity.ActivityType?, Bool) -> Void)?

    func present(items: [Any],
                 over viewController: UIViewController,
                 completion: @escaping (UIActivity.ActivityType?, Bool) -> Void) -> Bool {
        guard canPresent else { return false }
        presentedItems.append(items)
        self.completion = completion
        return true
    }

    func close(activityType: UIActivity.ActivityType? = nil, completed: Bool) {
        completion?(activityType, completed)
        completion = nil
    }
}

final class FakeImageLoader {
    private(set) var urls: [URL] = []
    private(set) var cancelled = 0
    private var pending: [(id: Int, completion: (UIImage?) -> Void)] = []

    func load(url: URL, completion: @escaping (UIImage?) -> Void) -> () -> Void {
        urls.append(url)
        let id = urls.count
        pending.append((id, completion))
        return { [weak self] in
            self?.cancelled += 1
            self?.pending.removeAll { $0.id == id }
        }
    }

    /// Answers the oldest load that wasn't cancelled.
    func finish(_ image: UIImage?) {
        pending.removeFirst().completion(image)
    }
}

final class ScreenshotSharingTests: XCTestCase {
    private static let imageURL = "https://news.example/image.jpg"
    private let image = UIImage()

    private let service = FakeCreateLinkService()
    private let shareSheet = FakeShareSheet()
    private let imageLoader = FakeImageLoader()
    private let notificationCenter = NotificationCenter()
    private let viewController = UIViewController()
    private var isApplicationActive = true
    private var events: [String] = []
    private var prompts: [ScreenshotSharePrompt] = []

    @MainActor
    private func makeController() -> ScreenshotSharingController {
        ScreenshotSharingController(
            createLinkService: service,
            notificationCenter: notificationCenter,
            isApplicationActive: { [unowned self] in self.isApplicationActive },
            presentShareSheet: { [shareSheet] in shareSheet.present(items: $0, over: $1, completion: $2) },
            loadImage: { [imageLoader] url, completion in imageLoader.load(url: url) { completion($0) } })
    }

    private func makeShare(id: String = "article-1", imageURL: String? = nil) -> ScreenshotShare {
        ScreenshotShare(request: .forArticle(url: "https://news.example/\(id)",
                                             id: id,
                                             title: "Title",
                                             description: "Description",
                                             sharerId: "sharer-1",
                                             contentType: .screenshot,
                                             imageURL: imageURL),
                        message: "Read it free")
    }

    @MainActor
    private func start(_ controller: ScreenshotSharingController, share: ScreenshotShare? = nil) {
        let share = share ?? makeShare()
        controller.start(from: viewController, onEvent: { [unowned self] in self.record($0) }) { share }
    }

    /// A screen that shows its own screen before sharing; prompts are collected in `prompts`.
    @MainActor
    private func startWithPrompt(_ controller: ScreenshotSharingController, share: ScreenshotShare? = nil) {
        let share = share ?? makeShare()
        controller.start(from: viewController,
                         onEvent: { [unowned self] in self.record($0) },
                         beforeSharing: { [unowned self] in self.prompts.append($0) }) { share }
    }

    private func record(_ event: ScreenshotSharingEvent) {
        switch event {
        case .creatingLink: events.append("creatingLink")
        case let .linkCreated(response): events.append("linkCreated \(response.url)")
        case let .shared(activityType): events.append("shared \(activityType?.rawValue ?? "-")")
        case .cancelled: events.append("cancelled")
        case let .failed(error): events.append("failed \(error.message)")
        }
    }

    private func takeScreenshot() {
        notificationCenter.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        drainMainQueue()
    }

    private func finishLink(url: String = "https://envoy.is/l/abc", error: WebError? = nil) {
        service.finish(url: url, error: error)
        drainMainQueue()
    }

    // MARK: Sharing

    @MainActor
    func testScreenshot_createsTheLinkThenOpensShareSheetWithMessageAndLink() {
        let controller = makeController()
        start(controller)

        takeScreenshot()
        XCTAssertEqual(events, ["creatingLink"])
        XCTAssertEqual(service.requests.count, 1)
        XCTAssertTrue(shareSheet.presentedItems.isEmpty)

        finishLink()

        XCTAssertEqual(events, ["creatingLink", "linkCreated https://envoy.is/l/abc"])
        XCTAssertEqual(shareSheet.presentedItems.count, 1)
        XCTAssertEqual(shareSheet.presentedItems.first?.first as? String, "Read it free")
        let link = shareSheet.presentedItems.first?.last as? ShareLinkItemSource
        XCTAssertEqual(link?.url, URL(string: "https://envoy.is/l/abc"))
        XCTAssertEqual(link?.title, "Title")
        XCTAssertNil(link?.image)
    }

    @MainActor
    func testScreenshot_sendsTheRequestFromShare() {
        let controller = makeController()
        start(controller, share: makeShare(id: "article-7"))

        takeScreenshot()

        let body = service.requests.first?.asJSON(keyEncodingStrategy: .convertToSnakeCase)
        let contentSetting = body?["content_setting"] as? [String: Any]
        XCTAssertEqual(contentSetting?["content_type"] as? String, "SCREENSHOT")
        XCTAssertEqual((contentSetting?["common"] as? [String: Any])?["source"] as? String, "https://news.example/article-7")
        XCTAssertEqual(body?["extra"] as? [String: String], ["articleId": "article-7"])
    }

    @MainActor
    func testShareSheetClosed_reportsSharedOrCancelled() {
        let controller = makeController()
        start(controller)
        takeScreenshot()
        finishLink()

        shareSheet.close(activityType: .message, completed: true)
        takeScreenshot()
        shareSheet.close(completed: false)

        XCTAssertEqual(events.filter { !$0.hasPrefix("linkCreated") && $0 != "creatingLink" },
                       ["shared \(UIActivity.ActivityType.message.rawValue)", "cancelled"])
    }

    @MainActor
    func testWithoutShare_screenshotIsIgnored() {
        let controller = makeController()
        controller.start(from: viewController, onEvent: { [unowned self] in self.record($0) }) { nil }

        takeScreenshot()

        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testFailedLink_reportsErrorAndOpensNoShareSheet() {
        let controller = makeController()
        start(controller)

        takeScreenshot()
        finishLink(error: .unauthorized)

        XCTAssertEqual(events, ["creatingLink", "failed Unauthorized"])
        XCTAssertTrue(shareSheet.presentedItems.isEmpty)
    }

    @MainActor
    func testAfterFailedLink_nextScreenshotTriesAgain() {
        let controller = makeController()
        start(controller)
        takeScreenshot()
        finishLink(error: .other)

        takeScreenshot()

        XCTAssertEqual(service.requests.count, 2)
    }

    // MARK: Preview image

    private var presentedImage: UIImage? {
        (shareSheet.presentedItems.last?.last as? ShareLinkItemSource)?.image
    }

    @MainActor
    func testWithoutImageURL_noImageIsLoaded() {
        let controller = makeController()
        start(controller)

        takeScreenshot()
        finishLink()

        XCTAssertTrue(imageLoader.urls.isEmpty)
        XCTAssertEqual(shareSheet.presentedItems.count, 1)
    }

    @MainActor
    func testArticleImage_isLoadedTogetherWithTheLinkAndPreviewed() {
        let controller = makeController()
        start(controller, share: makeShare(imageURL: Self.imageURL))

        takeScreenshot()
        XCTAssertEqual(imageLoader.urls, [URL(string: Self.imageURL)!])

        finishLink()
        XCTAssertTrue(shareSheet.presentedItems.isEmpty)

        imageLoader.finish(image)
        XCTAssertTrue(presentedImage === image)
    }

    @MainActor
    func testImageReadyBeforeTheLink_waitsForIt() {
        let controller = makeController()
        start(controller, share: makeShare(imageURL: Self.imageURL))

        takeScreenshot()
        imageLoader.finish(image)
        XCTAssertTrue(shareSheet.presentedItems.isEmpty)

        finishLink()
        XCTAssertTrue(presentedImage === image)
    }

    @MainActor
    func testImageNotLoaded_opensShareSheetWithoutIt() {
        let controller = makeController()
        start(controller, share: makeShare(imageURL: Self.imageURL))

        takeScreenshot()
        finishLink()
        imageLoader.finish(nil)

        XCTAssertEqual(shareSheet.presentedItems.count, 1)
        XCTAssertNil(presentedImage)
    }

    @MainActor
    func testFailedLink_dropsTheImage() {
        let controller = makeController()
        start(controller, share: makeShare(imageURL: Self.imageURL))
        takeScreenshot()

        finishLink(error: .other)

        XCTAssertEqual(imageLoader.cancelled, 1)
        XCTAssertTrue(shareSheet.presentedItems.isEmpty)
    }

    @MainActor
    func testStopWhileLoadingTheImage_dropsIt() {
        let controller = makeController()
        start(controller, share: makeShare(imageURL: Self.imageURL))
        takeScreenshot()
        finishLink()

        controller.stop()

        XCTAssertEqual(imageLoader.cancelled, 1)
        XCTAssertTrue(shareSheet.presentedItems.isEmpty)
    }

    @MainActor
    func testScreenshotOfSameContentAgain_reusesTheImage() {
        let controller = makeController()
        start(controller, share: makeShare(imageURL: Self.imageURL))
        takeScreenshot()
        finishLink()
        imageLoader.finish(image)
        shareSheet.close(completed: false)

        takeScreenshot()

        XCTAssertEqual(imageLoader.urls.count, 1)
        XCTAssertEqual(shareSheet.presentedItems.count, 2)
        XCTAssertTrue(presentedImage === image)
    }

    // MARK: Turning it on and off

    @MainActor
    func testBeforeStart_screenshotIsIgnored() {
        _ = makeController()

        takeScreenshot()

        XCTAssertTrue(service.requests.isEmpty)
    }

    @MainActor
    func testAfterStop_screenshotIsIgnored() {
        let controller = makeController()
        start(controller)
        controller.stop()

        takeScreenshot()

        XCTAssertTrue(service.requests.isEmpty)
    }

    @MainActor
    func testStopWhileCreatingLink_opensNoShareSheet() {
        let controller = makeController()
        start(controller)
        takeScreenshot()

        controller.stop()
        finishLink()

        XCTAssertEqual(events, ["creatingLink"])
        XCTAssertTrue(shareSheet.presentedItems.isEmpty)
    }

    @MainActor
    func testStartAnotherScreenWhileCreatingLink_dropsTheEarlierLink() {
        let controller = makeController()
        start(controller)
        takeScreenshot()

        start(controller, share: makeShare(id: "article-2"))
        finishLink()
        takeScreenshot()

        XCTAssertTrue(shareSheet.presentedItems.isEmpty)
        XCTAssertEqual(service.requests.count, 2)
    }

    // MARK: Repeated screenshots

    @MainActor
    func testScreenshotsWhileCreatingLinkOrSharing_areIgnored() {
        let controller = makeController()
        start(controller)

        takeScreenshot()
        takeScreenshot()
        finishLink()
        takeScreenshot()

        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(shareSheet.presentedItems.count, 1)
    }

    @MainActor
    func testScreenshotOfSameContentAgain_reusesTheLink() {
        let controller = makeController()
        start(controller)
        takeScreenshot()
        finishLink()
        shareSheet.close(completed: false)

        controller.stop()
        start(controller)
        takeScreenshot()

        XCTAssertEqual(service.requests.count, 1)
        XCTAssertEqual(shareSheet.presentedItems.count, 2)
        XCTAssertEqual(events.last, "linkCreated https://envoy.is/l/abc")
    }

    @MainActor
    func testScreenshotOfOtherContent_createsAnotherLink() {
        let controller = makeController()
        start(controller)
        takeScreenshot()
        finishLink()
        shareSheet.close(completed: false)

        start(controller, share: makeShare(id: "article-2"))
        takeScreenshot()

        XCTAssertEqual(service.requests.count, 2)
    }

    @MainActor
    func testWhenShareSheetCantBePresented_nextScreenshotIsHandled() {
        shareSheet.canPresent = false
        let controller = makeController()
        start(controller)
        takeScreenshot()
        finishLink()

        shareSheet.canPresent = true
        takeScreenshot()

        XCTAssertEqual(shareSheet.presentedItems.count, 1)
    }

    // MARK: Your own screen before sharing

    @MainActor
    func testWithBeforeSharing_screenshotShowsThePromptAndCreatesNoLink() {
        let controller = makeController()
        startWithPrompt(controller, share: makeShare(id: "article-7", imageURL: Self.imageURL))

        takeScreenshot()

        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.content.request.contentSetting.common?.source, "https://news.example/article-7")
        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertTrue(imageLoader.urls.isEmpty)
        XCTAssertTrue(events.isEmpty)
    }

    @MainActor
    func testPromptShare_createsTheLinkThenOpensShareSheet() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()

        prompts.first?.share()
        drainMainQueue()
        XCTAssertEqual(events, ["creatingLink"])

        finishLink()

        XCTAssertEqual(events, ["creatingLink", "linkCreated https://envoy.is/l/abc"])
        XCTAssertEqual(shareSheet.presentedItems.count, 1)
        XCTAssertEqual(shareSheet.presentedItems.first?.first as? String, "Read it free")
    }

    @MainActor
    func testPromptShareWithLinkCreatedEarlier_opensShareSheetAfterShareReturns() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()
        prompts[0].share()
        drainMainQueue()
        finishLink()
        shareSheet.close(completed: false)
        takeScreenshot()

        prompts[1].share()
        XCTAssertEqual(shareSheet.presentedItems.count, 1)

        drainMainQueue()
        XCTAssertEqual(shareSheet.presentedItems.count, 2)
    }

    @MainActor
    func testScreenshotRightAfterShare_isIgnored() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()

        prompts.first?.share()
        takeScreenshot()

        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(service.requests.count, 1)
    }

    @MainActor
    func testStopRightAfterShare_createsNoLink() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()

        prompts.first?.share()
        controller.stop()
        drainMainQueue()

        XCTAssertTrue(service.requests.isEmpty)
    }

    @MainActor
    func testPromptReleasedWithoutAnswer_nextScreenshotShowsAnotherPrompt() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()

        prompts.removeAll()
        takeScreenshot()

        XCTAssertEqual(prompts.count, 1)
        XCTAssertTrue(service.requests.isEmpty)
    }

    @MainActor
    func testPrompt_isActiveUntilAnswered() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()
        XCTAssertEqual(prompts.first?.isActive, true)

        XCTAssertEqual(prompts.first?.cancel(), true)

        XCTAssertEqual(prompts.first?.isActive, false)
        XCTAssertEqual(prompts.first?.cancel(), false)
    }

    @MainActor
    func testPromptCancel_createsNoLinkAndNextScreenshotShowsAnotherPrompt() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()

        prompts.first?.cancel()
        prompts.first?.share()
        takeScreenshot()

        XCTAssertTrue(service.requests.isEmpty)
        XCTAssertTrue(shareSheet.presentedItems.isEmpty)
        XCTAssertEqual(prompts.count, 2)
    }

    @MainActor
    func testScreenshotsWhileThePromptIsShown_areIgnored() {
        let controller = makeController()
        startWithPrompt(controller)

        takeScreenshot()
        takeScreenshot()

        XCTAssertEqual(prompts.count, 1)
    }

    @MainActor
    func testPromptSharedTwice_createsOneLink() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()

        XCTAssertEqual(prompts.first?.share(), true)
        XCTAssertEqual(prompts.first?.share(), false)
        drainMainQueue()

        XCTAssertEqual(service.requests.count, 1)
    }

    @MainActor
    func testPromptSharedAfterStop_doesNothing() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()

        controller.stop()

        XCTAssertEqual(prompts.first?.isActive, false)
        XCTAssertEqual(prompts.first?.share(), false)
        drainMainQueue()
        XCTAssertTrue(service.requests.isEmpty)
    }

    @MainActor
    func testPromptSharedAfterAnotherScreenStarted_doesNothing() {
        let controller = makeController()
        startWithPrompt(controller)
        takeScreenshot()

        start(controller, share: makeShare(id: "article-2"))

        XCTAssertEqual(prompts.first?.isActive, false)
        XCTAssertEqual(prompts.first?.share(), false)
        drainMainQueue()
        XCTAssertTrue(service.requests.isEmpty)
    }

    // MARK: App not active

    @MainActor
    func testLinkReadyWhileAppInactive_opensShareSheetWhenAppIsActiveAgain() {
        let controller = makeController()
        start(controller)
        takeScreenshot()

        isApplicationActive = false
        finishLink()
        XCTAssertTrue(shareSheet.presentedItems.isEmpty)

        isApplicationActive = true
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        drainMainQueue()

        XCTAssertEqual(shareSheet.presentedItems.count, 1)
    }

    @MainActor
    func testStopWhileWaitingForApp_opensNoShareSheet() {
        let controller = makeController()
        start(controller)
        takeScreenshot()
        isApplicationActive = false
        finishLink()

        controller.stop()
        isApplicationActive = true
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        drainMainQueue()

        XCTAssertTrue(shareSheet.presentedItems.isEmpty)
    }
}
