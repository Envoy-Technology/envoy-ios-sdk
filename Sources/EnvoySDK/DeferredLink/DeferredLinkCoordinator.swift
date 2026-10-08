#if canImport(UIKit)
import UIKit

/// Process-wide state of the deferred-link check and of the pixel events held while it runs.
/// Shared by every `Envoy` instance, because `Envoy.initialize` can be called more than once.
/// The state is touched only on the main thread, except `requestedChecks`, which is guarded
/// by `requestLock`. That is what makes it `Sendable`.
final class DeferredLinkCoordinator: @unchecked Sendable {
    static let shared = DeferredLinkCoordinator()

    private enum Constants {
        static let envoyShareLinkHash = "envoy_share_link_hash"
        static let envoyLeadUuid = "envoy_lead_uuid"
    }

    private typealias PendingPixelEvent = (request: LogPixelEventRequest,
                                           service: LogPixelEventServiceType,
                                           completion: (EmptyResponse?, WebError?) -> ())

    private struct Check {
        let id: Int
        let timeLimit: DispatchWorkItem
        var hasFailedOnce = false
    }

    private let pasteboard: PasteboardType
    private let keychain: KeychainType
    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let isApplicationActive: () -> Bool
    private let installDate: () -> Date?
    private let now: () -> Date
    private let attributionWindow: TimeInterval
    private let completionTimeout: TimeInterval
    private let checkTimeLimit: TimeInterval
    private let failureRetryDelay: TimeInterval

    private var check: Check?
    private var checkCount = 0
    private var waitingCompletions: [Int: (completion: (Bool) -> Void, timeout: DispatchWorkItem)] = [:]
    private var completionCount = 0
    private var activationObserver: NSObjectProtocol?
    /// Pixel events logged during a check, sent once it ends.
    private var pendingPixelEvents: [PendingPixelEvent] = []
    /// Attribution read from the Keychain; kept only when something was found, and replaced when a check stores a link.
    private var cachedAttribution: LogPixelEventRequest.Attribution?
    private var isInBackground = false
    private var lifecycleObservers: [NSObjectProtocol] = []

    private let requestLock = NSLock()
    /// Checks requested off the main thread that haven't started yet.
    private var requestedChecks = 0

    init(pasteboard: PasteboardType = SystemPasteboard(),
         keychain: KeychainType = Keychain.standard,
         userDefaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default,
         isApplicationActive: @escaping () -> Bool = DeferredLinkCoordinator.isApplicationActive,
         installDate: @escaping () -> Date? = DeferredLinkCoordinator.documentsCreationDate,
         now: @escaping () -> Date = Date.init,
         attributionWindow: TimeInterval = 24 * 60 * 60,
         completionTimeout: TimeInterval = 3,
         checkTimeLimit: TimeInterval = 30,
         failureRetryDelay: TimeInterval = 1) {
        self.pasteboard = pasteboard
        self.keychain = keychain
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        self.isApplicationActive = isApplicationActive
        self.installDate = installDate
        self.now = now
        self.attributionWindow = attributionWindow
        self.completionTimeout = completionTimeout
        self.checkTimeLimit = checkTimeLimit
        self.failureRetryDelay = failureRetryDelay
        observeLifecycle()
    }

    deinit {
        lifecycleObservers.forEach { notificationCenter.removeObserver($0) }
        stopWaitingForActivation()
    }

    // MARK: Entry points, callable from any thread

    func checkDeferredLink(completion: ((Bool) -> Void)?) {
        if Thread.isMainThread {
            startCheck(completion: completion)
            return
        }
        // Counted right away, so an event logged on the main thread before the check starts is held for it.
        requestLock.lock()
        requestedChecks += 1
        requestLock.unlock()
        nonisolated(unsafe) let completion = completion
        DispatchQueue.main.async {
            self.requestLock.lock()
            self.requestedChecks -= 1
            self.requestLock.unlock()
            self.startCheck(completion: completion)
        }
    }

    func logPixelEvent(_ request: LogPixelEventRequest,
                       service: LogPixelEventServiceType,
                       completion: @escaping (EmptyResponse?, WebError?) -> ()) {
        nonisolated(unsafe) let service = service
        nonisolated(unsafe) let completion = completion
        onMainThread {
            if self.shouldHoldPixelEvents {
                self.pendingPixelEvents.append((request, service, completion))
            } else {
                self.sendPixelEvents([(request, service, completion)])
            }
        }
    }

    // MARK: Check

    private func startCheck(completion: ((Bool) -> Void)?) {
        if check != nil {
            waitForResult(completion)
            return
        }
        guard !userDefaults.isDeferredLinkCheckDone else {
            reply(false, to: completion)
            sendPendingPixelEventsIfIdle()
            return
        }
        guard !isInstalledTooLongAgo else {
            // The clipboard no longer relates to the install, and a paste prompt would surprise the user.
            userDefaults.setDeferredLinkCheckDone()
            reply(false, to: completion)
            sendPendingPixelEventsIfIdle()
            return
        }

        checkCount += 1
        let id = checkCount
        // Strong capture: bounded by the time limit itself.
        let timeLimit = DispatchWorkItem {
            // Not used up, so a later call can retry.
            self.endCheck(id, found: false)
        }
        check = Check(id: id, timeLimit: timeLimit)
        DispatchQueue.main.asyncAfter(deadline: .now() + checkTimeLimit, execute: timeLimit)
        waitForResult(completion)
        detect(id)
    }

    private var isInstalledTooLongAgo: Bool {
        guard let installDate = installDate() else { return false }
        return now().timeIntervalSince(installDate) > attributionWindow
    }

    private func detect(_ id: Int) {
        guard isApplicationActive() else {
            // The clipboard is available only to the app in the foreground.
            waitForActivation { self.detect(id) }
            return
        }
        pasteboard.detectProbableWebURL { result in
            self.handleDetection(result, checkID: id)
        }
    }

    private func handleDetection(_ result: Swift.Result<Bool, Error>, checkID id: Int) {
        // Ignore a late answer to a check that already ended.
        guard let check = check, check.id == id else { return }

        switch result {
        case .failure where !check.hasFailedOnce:
            self.check?.hasFailedOnce = true
            DispatchQueue.main.asyncAfter(deadline: .now() + failureRetryDelay) {
                guard self.check?.id == id else { return }
                self.detect(id)
            }
        case .failure:
            // Not used up, so a later call can retry.
            endCheck(id, found: false)
        case .success(false):
            userDefaults.setDeferredLinkCheckDone()
            endCheck(id, found: false)
        case .success(true) where !isApplicationActive():
            // Reading in the background returns nothing, so detect again once the app is active.
            waitForActivation { self.detect(id) }
        case .success(true):
            // Used up before reading, so a user who denies the paste prompt is not asked again.
            userDefaults.setDeferredLinkCheckDone()
            endCheck(id, found: storeLinkParameters(from: pasteboard.string))
        }
    }

    private func endCheck(_ id: Int, found: Bool) {
        guard let check = check, check.id == id else { return }
        check.timeLimit.cancel()
        stopWaitingForActivation()
        self.check = nil
        // Events held during the check go before anything logged from a completion.
        sendPendingPixelEventsIfIdle()
        waitingCompletions.keys.sorted().forEach { answer($0, found: found) }
    }

    private func storeLinkParameters(from clipboardContent: String?) -> Bool {
        guard let clipboardLink = clipboardContent?.trimmingCharacters(in: .whitespacesAndNewlines),
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
        if didStore {
            cachedAttribution = nil
        }
        return didStore
    }

    // MARK: Completions

    private func waitForResult(_ completion: ((Bool) -> Void)?) {
        guard let completion = completion else { return }
        completionCount += 1
        let token = completionCount
        // A caller waits at most `completionTimeout`; the check itself can go on and still attribute held events.
        let timeout = DispatchWorkItem {
            self.answer(token, found: false)
        }
        waitingCompletions[token] = (completion, timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + completionTimeout, execute: timeout)
    }

    private func answer(_ token: Int, found: Bool) {
        guard let waiting = waitingCompletions.removeValue(forKey: token) else { return }
        waiting.timeout.cancel()
        reply(found, to: waiting.completion)
    }

    /// Always asynchronous, so a completion never runs before `checkDeferredLink` returns.
    private func reply(_ found: Bool, to completion: ((Bool) -> Void)?) {
        guard let completion = completion else { return }
        // Handed off to the main queue and only ever run there.
        nonisolated(unsafe) let callback = completion
        DispatchQueue.main.async {
            callback(found)
        }
    }

    // MARK: Pixel events

    private var shouldHoldPixelEvents: Bool {
        !isInBackground && (check != nil || hasRequestedChecks)
    }

    private var hasRequestedChecks: Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return requestedChecks > 0
    }

    private func sendPixelEvents(_ events: [PendingPixelEvent]) {
        guard !events.isEmpty else { return }
        let attribution = storedAttribution()
        events.forEach {
            $0.service.logPixelEvent(request: $0.request.attributed(with: attribution), completion: $0.completion)
        }
    }

    private func sendPendingPixelEvents() {
        let events = pendingPixelEvents
        pendingPixelEvents = []
        sendPixelEvents(events)
    }

    private func sendPendingPixelEventsIfIdle() {
        guard check == nil, !hasRequestedChecks else { return }
        sendPendingPixelEvents()
    }

    private func storedAttribution() -> LogPixelEventRequest.Attribution {
        if let cachedAttribution = cachedAttribution {
            return cachedAttribution
        }
        let attribution = LogPixelEventRequest.Attribution(
            shareLinkHash: keychain.value(forKey: .envoyShareLinkHash),
            leadUuid: keychain.value(forKey: .envoyLeadUuid)
        )
        // Nothing found can also mean the Keychain was locked, so it is read again next time.
        if attribution.shareLinkHash != nil || attribution.leadUuid != nil {
            cachedAttribution = attribution
        }
        return attribution
    }

    // MARK: App lifecycle

    private func observeLifecycle() {
        lifecycleObservers = [
            notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                           object: nil,
                                           queue: .main) { [weak self] _ in
                guard let self = self else { return }
                // The app may be terminated in the background, so held events go out now, attributed or not.
                self.isInBackground = true
                self.sendPendingPixelEvents()
            },
            notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification,
                                           object: nil,
                                           queue: .main) { [weak self] _ in
                self?.isInBackground = false
            }
        ]
    }

    private func waitForActivation(then work: @escaping () -> Void) {
        stopWaitingForActivation()
        nonisolated(unsafe) let work = work
        activationObserver = notificationCenter.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                            object: nil,
                                                            queue: .main) { _ in
            self.stopWaitingForActivation()
            work()
        }
    }

    private func stopWaitingForActivation() {
        if let activationObserver = activationObserver {
            notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    // MARK: Environment

    /// Hosts compiled in Swift 5 mode can end up calling the main-actor API off the main thread
    /// (e.g. from another SDK's callback) without a compiler error,
    /// so the state is touched on the main thread only.
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

    static func isApplicationActive() -> Bool {
        // Only called on the main thread.
        MainActor.assumeIsolated {
            UIApplication.shared.applicationState == .active
        }
    }

    /// The Documents directory is created on install and kept across updates.
    static func documentsCreationDate() -> Date? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let attributes = try? FileManager.default.attributesOfItem(atPath: documents.path) else {
            return nil
        }
        return attributes[.creationDate] as? Date
    }
}
#endif
