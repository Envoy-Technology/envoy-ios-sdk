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

final class ScreenshotSharingTests: XCTestCase {
    private let service = FakeCreateLinkService()
    private let shareSheet = FakeShareSheet()
    private let notificationCenter = NotificationCenter()
    private let viewController = UIViewController()
    private var isApplicationActive = true
    private var events: [String] = []

    @MainActor
    private func makeController() -> ScreenshotSharingController {
        ScreenshotSharingController(
            createLinkService: service,
            notificationCenter: notificationCenter,
            isApplicationActive: { [unowned self] in self.isApplicationActive },
            presentShareSheet: { [shareSheet] in shareSheet.present(items: $0, over: $1, completion: $2) })
    }

    private func makeShare(id: String = "article-1") -> ScreenshotShare {
        ScreenshotShare(request: .forArticle(url: "https://news.example/\(id)",
                                             id: id,
                                             title: "Title",
                                             description: "Description",
                                             sharerId: "sharer-1",
                                             contentType: .screenshot),
                        message: "Read it free")
    }

    @MainActor
    private func start(_ controller: ScreenshotSharingController, share: ScreenshotShare? = nil) {
        let share = share ?? makeShare()
        controller.start(from: viewController, onEvent: { [unowned self] in self.record($0) }) { share }
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
        XCTAssertEqual(shareSheet.presentedItems.first?.last as? URL, URL(string: "https://envoy.is/l/abc"))
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
