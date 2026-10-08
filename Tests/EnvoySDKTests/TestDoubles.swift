import XCTest
@testable import EnvoySDK

enum TestError: Error {
    case detectionFailed
}

enum TestLinks {
    static let full = "https://envoy.is/l/abc?envoy_share_link_hash=hash-1&envoy_lead_uuid=lead-1"
}

final class FakePasteboard: PasteboardType {
    var content: String?
    /// Answers for the next detections, in order; after them `detectionResult` applies.
    var nextDetectionResults: [Swift.Result<Bool, Error>] = []
    /// When nil, detection stays in progress until `finishDetection(with:)` is called.
    var detectionResult: Swift.Result<Bool, Error>?
    /// Runs while the content is being read, like the system paste prompt.
    var onRead: (() -> Void)?
    private(set) var detectionCount = 0
    private(set) var readCount = 0
    private var pendingDetections: [(Swift.Result<Bool, Error>) -> Void] = []

    var string: String? {
        readCount += 1
        onRead?()
        return content
    }

    func detectProbableWebURL(completion: @escaping (Swift.Result<Bool, Error>) -> Void) {
        detectionCount += 1
        if !nextDetectionResults.isEmpty {
            completion(nextDetectionResults.removeFirst())
        } else if let detectionResult = detectionResult {
            completion(detectionResult)
        } else {
            pendingDetections.append(completion)
        }
    }

    func finishDetection(with result: Swift.Result<Bool, Error>) {
        let pending = pendingDetections
        pendingDetections = []
        pending.forEach { $0(result) }
    }

    func finishOldestDetection(with result: Swift.Result<Bool, Error>) {
        pendingDetections.removeFirst()(result)
    }

    /// Like the system releasing the callback without ever calling it.
    func dropPendingDetections() {
        pendingDetections = []
    }
}

final class FakeKeychain: KeychainType {
    var values: [Keychain.Key: String] = [:]
    private(set) var readCount = 0

    func set(_ value: String, forKey key: Keychain.Key) -> Bool {
        values[key] = value
        return true
    }

    func value(forKey key: Keychain.Key) -> String? {
        readCount += 1
        return values[key]
    }
}

final class FakePixelEventService: LogPixelEventServiceType {
    private(set) var sentRequests: [LogPixelEventRequest] = []
    private(set) var sentOnMainThread: [Bool] = []

    func logPixelEvent(request: LogPixelEventRequest,
                       completion: @escaping (EmptyResponse?, WebError?) -> ()) -> URLSessionDataTask? {
        sentRequests.append(request)
        sentOnMainThread.append(Thread.isMainThread)
        completion(EmptyResponse(), nil)
        return nil
    }

    /// The body the real service would send.
    var sentBodies: [[String: Any]] {
        sentRequests.compactMap { $0.asJSON() }
    }

    var sentEventNames: [String] {
        sentBodies.compactMap { $0["event_name"] as? String }
    }
}

/// Fakes for one test, which plays the role of one app process, plus an isolated UserDefaults suite.
final class EnvoyFixture {
    let pasteboard = FakePasteboard()
    let keychain = FakeKeychain()
    let pixelEventService = FakePixelEventService()
    let notificationCenter = NotificationCenter()
    let userDefaults: UserDefaults
    var isApplicationActive = true
    var installDate: Date? = Date()
    var completionTimeout: TimeInterval = 10
    var checkTimeLimit: TimeInterval = 10
    var failureRetryDelay: TimeInterval = 0.01
    private let suiteName = "EnvoySDKTests.\(UUID().uuidString)"

    init() {
        userDefaults = UserDefaults(suiteName: suiteName)!
    }

    /// The process-wide state, created on first use so a test can change the settings above first.
    private(set) lazy var deferredLinks = DeferredLinkCoordinator(
        pasteboard: pasteboard,
        keychain: keychain,
        userDefaults: userDefaults,
        notificationCenter: notificationCenter,
        isApplicationActive: { [weak self] in self?.isApplicationActive ?? false },
        installDate: { [weak self] in self?.installDate },
        completionTimeout: completionTimeout,
        checkTimeLimit: checkTimeLimit,
        failureRetryDelay: failureRetryDelay
    )

    /// Each call is like another `Envoy.initialize` in the same process.
    func makeEnvoy() -> Envoy {
        Envoy(apiKey: "test-api-key",
              pixelEventService: pixelEventService,
              deferredLinks: deferredLinks)
    }

    func removeUserDefaults() {
        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

extension XCTestCase {
    /// Runs the blocks already queued on the main queue, such as completions called asynchronously.
    func drainMainQueue() {
        let drained = expectation(description: "main queue drained")
        DispatchQueue.main.async {
            drained.fulfill()
        }
        wait(for: [drained], timeout: 2)
    }
}
