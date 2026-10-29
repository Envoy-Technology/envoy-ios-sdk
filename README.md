<a name="introduction"></a>
# Overview

Envoy iOS SDK lets users of your iOS app share your content as gift links.

# Quick Start Guide

## 1. Install Envoy SDK
You can install the Envoy iOS SDK - Swift library by using Swift Package Manager. It supports iOS 13 and later. You will need your API key to initialize the library. You can find it in the Security tab of [account settings](https://dashboard.envoy.is/dashboard/account/).

### Installation with Swift Package Manager
In Xcode:
1. Open **File > Add Package Dependencies…**
2. Enter `https://github.com/Envoy-Technology/envoy-ios-sdk.git`, choose **Up to Next Major Version** and **Add Package**.
3. Add the `EnvoySDK` library to your app target.

Or, in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Envoy-Technology/envoy-ios-sdk.git", from: "0.0.18")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "EnvoySDK", package: "envoy-ios-sdk")
    ])
]
```

> **Migrating from CocoaPods:** the `EnvoySDK` pod is deprecated and stays at 0.0.16, since CocoaPods trunk becomes read-only on December 2, 2026. Remove `pod 'EnvoySDK'` from your Podfile, run `pod install`, and add the package as above. The module name is the same, so `import EnvoySDK` doesn't change. Then follow the upgrade notes in 2.1 and 4.1.

## 2. Initialize EnvoySDK
To initialize the library, add `import EnvoySDK` into `AppDelegate` and call `initialize(apiKey:)` in [application(_:didFinishLaunchingWithOptions:)](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:didfinishlaunchingwithoptions:))
```swift
import EnvoySDK

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
...
  Envoy.initialize(apiKey: {your-api-key})
...
}
```

## 2.1 Check deferred link (required for install attribution)

> **Upgrading from 0.0.15 or earlier:**
> - `Envoy.initialize(apiKey:)` no longer reads the clipboard. If you don't call `checkDeferredLink`, installs are not attributed to the share link that brought the user: pixel events are sent without `share_link_hash` and `lead_uuid`.
> - If an earlier SDK version already read the clipboard on this install, `checkDeferredLink` doesn't read it again, so users who update don't see the paste prompt a second time.
> - `EnvoyType` has a new requirement, `checkDeferredLink(completion:)`. Types that conform to it, such as test doubles or wrappers, must implement it; a wrapper should forward it to `Envoy.shared`.

Envoy landing pages copy the share link to the clipboard before redirecting to the App Store. To attribute the install to that link, call `checkDeferredLink` after initialization, and log `.appDownloaded` once per install right after that call. The SDK doesn't read the clipboard on its own, so you decide when it happens. If you need user consent first (e.g. under GDPR/ePrivacy in the EU), call it right after consent is given.

```swift
Envoy.initialize(apiKey: {your-api-key})
Envoy.shared.checkDeferredLink { found in
    // found == true when Envoy link parameters were stored. Optional, e.g. to route the user.
}
// Once per install. Held until the check above ends, so it carries the attribution.
Envoy.shared.logPixelEvent(request: LogPixelEventRequest(event: .appDownloaded)) { _, _ in }
```

Don't log `.appDownloaded` in the completion: it is called on every call of `checkDeferredLink`, with `false` once the check has been used up, so the event would be sent on every launch.

What it does:
- Runs once per install. It works from the first launch; once more than a day has passed since install, the clipboard no longer relates to the install, so it isn't touched and the check completes with `false`. This also covers apps that add the call in a later version, or get consent much later.
- On iOS 14+ it first checks, without reading the content, whether the clipboard contains a web URL. It reads the clipboard only if it does, so iOS shows its paste banner/prompt only in that case. If the user denies the paste prompt, the check is used up and they are not asked again.
- It works with the clipboard only while the app is active, and waits for that if needed.
- It keeps only the `envoy_share_link_hash` and `envoy_lead_uuid` query parameters (stored in the Keychain and sent with pixel events). The rest of the clipboard content is discarded.
- Calls made while a check is in progress, through any `Envoy` instance, get the result of that check.
- The completion is called on the main thread, never before `checkDeferredLink` returns, and at most 3 seconds later. The check itself can take longer.
- If the check can't finish (iOS fails to tell whether the clipboard holds a URL twice in a row, or doesn't answer within 30 seconds), it is not used up and a later call, e.g. on the next launch, tries again.

Pixel events:
- Events logged while a check is in progress, or right after `checkDeferredLink` was called from another thread, are held until the check ends and then sent with the attribution it found, if any.
- If the app goes to the background first, held events are sent right away, since the app may be terminated. Events logged in the background aren't held.
- Events logged when no check is in progress are sent right away, with whatever attribution is already stored.
- `Envoy.shared.checkDeferredLink` and `Envoy.shared.logPixelEvent` can be called from any thread (through the `EnvoyType` protocol they are main-actor isolated).

Disclose this clipboard access and the attribution data in your privacy policy and App Privacy details. The SDK ships a `PrivacyInfo.xcprivacy` privacy manifest that declares the data it collects and its use of `UserDefaults`.

## 3. Configure `CreateLinkRequest`

`CreateLinkRequest` describes the content to share. For an article, use `forArticle`:

```swift
let request = CreateLinkRequest.forArticle(url: article.url,
                                           id: article.id,
                                           title: article.title,
                                           description: article.lead,
                                           sharerId: user.id,
                                           contentType: .htmlSource,  // or .screenshot
                                           imageURL: article.imageURL)
```

For other content, build it with the initializers. Only the parameters without default values are required:

```swift
let request = CreateLinkRequest(
    autoplay: true,
    contentSetting: .init(contentType: CreateLinkRequest.ContentType.video.rawValue,
                          contentName: "Episode 1",
                          contentDescription: "The first episode",
                          common: .init(source: "https://example.com/episode-1.mp4",
                                        sourceIsRedirect: false,
                                        poster: "https://example.com/episode-1.jpg"),
                          videoOrientation: .horizontal),
    sharerId: user.id)
```

The full initializers:

```swift
CreateLinkRequest(autoplay: Bool?,
                  contentSetting: ContentSetting,
                  lifespanAfterClick: LifespanAfterClick? = nil,  // LifespanAfterClick(value: Int?, unit: String)
                  openQuota: Int? = nil,
                  extra: [String: String]? = nil,
                  sharerId: String,
                  isSandbox: Bool? = nil,
                  labels: [Label]? = nil,                         // Label(id: Int?, text: String, color: String)
                  isCarousel: Bool? = false,
                  isCarouselLink: Bool? = false)

CreateLinkRequest.ContentSetting(contentType: String,             // a CreateLinkRequest.ContentType rawValue
                                 contentName: String,
                                 contentDescription: String,
                                 common: Common? = nil,           // Common(source: String, sourceIsRedirect: Bool?, poster: String?)
                                 base64_file: String? = nil,
                                 timeLimit: Int? = nil,
                                 timeStart: Int? = nil,
                                 availableFrom: String? = nil,
                                 availableTo: String? = nil,
                                 videoOrientation: VideoOrientation? = nil,  // .horizontal or .vertical
                                 previewTitle: String? = nil,
                                 previewDescription: String? = nil,
                                 previewImage: String? = nil,
                                 mandatoryEmail: Bool? = nil,
                                 modalTitle: String? = nil,
                                 buttonText: String? = nil,
                                 contentProtection: ContentProtection? = nil)  // ContentProtection(media: Common)
```

`CreateLinkRequest.ContentType` is one of `.video`, `.audio`, `.htmlPlain`, `.htmlSource` or `.screenshot`.

## 4. Create link

Create a link using the previously configured request and handle the response and potential error

```swift
Envoy.shared.createLink(request: request) { response, error in            
    print(response)
    print(error)
}
```

## 4.1 Share a link when the user takes a screenshot
When the user takes a screenshot of a screen with screenshot sharing turned on, the SDK creates that screen's link and opens the system share sheet with it, so the user shares a gift link instead of the image. It needs no permission: the screenshot itself isn't read.

Turn it on when the screen appears and off when it disappears, only on screens that show shareable content, such as an article:

```swift
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Envoy.shared.startScreenshotSharing(from: self) { [weak self] in
        guard let self else { return nil }  // nil ignores the screenshot
        return ScreenshotShare(
            request: .forArticle(url: article.url,
                                 id: article.id,
                                 title: article.title,
                                 description: article.lead,
                                 sharerId: user.id,
                                 contentType: .screenshot,  // or .htmlSource
                                 imageURL: article.imageURL),
            message: "Your friend wants to gift you this article")
    }
}

override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    Envoy.shared.stopScreenshotSharing()
}
```

- The closure is called on each screenshot and can return any `CreateLinkRequest`. `forArticle` sends the article URL as the content source and its id in `extra` as `articleId`. With `.screenshot` the gift landing shows a screenshot of the page, rendered by Envoy from the URL; with `.htmlSource` it shows the page itself.
- The share sheet previews the link with the request's title and its `previewImage` (the `imageURL` of `forArticle`), loaded together with the link. If the image isn't loaded within 2 seconds, the share sheet opens without it. Only the message and the link are shared; Mail uses the title as the subject.
- Screenshots taken while the link is being created or the share sheet is open are ignored. A later screenshot of the same request reuses the link created earlier in the app session.
- If the link can't be created, no share sheet is shown.
- `stopScreenshotSharing` drops a link still being created, so no share sheet opens on another screen.
- Pass `onEvent` to follow the progress, e.g. to show a loader while the link is created:

```swift
Envoy.shared.startScreenshotSharing(from: self, onEvent: { event in
    switch event {
    case .creatingLink: break                    // link requested
    case .linkCreated(let response): break       // share sheet opens next
    case .shared(let activityType): break        // user shared, e.g. to .message
    case .cancelled: break                       // share sheet closed without sharing
    case .failed(let error): print(error.message)
    }
}) { [weak self] in
    self?.screenshotShare()
}
```

### Show your own screen before sharing
To show your own screen first, e.g. a "Send a gift" sheet, pass `beforeSharing`. After the closure returns a `ScreenshotShare`, `beforeSharing` is called with a `ScreenshotSharePrompt` instead of creating the link. Nothing is created until you call `prompt.share()`, so a screen closed without sharing uses none of the user's quota:

```swift
Envoy.shared.startScreenshotSharing(from: self, beforeSharing: { [weak self] prompt in
    let gift = GiftViewController(message: prompt.content.message)
    gift.onSend = { [weak gift] in gift?.dismiss(animated: true) { prompt.share() } }  // creates the link, then opens the share sheet
    gift.onClose = { prompt.cancel() }  // nothing is shared or created
    self?.present(gift, animated: true)
}) { [weak self] in
    self?.screenshotShare()
}
```

- Screenshots are ignored while the prompt is waiting for `share()` or `cancel()`, so call `cancel()` when the user closes your screen, including when they swipe the sheet down. Only the first call counts.
- A prompt your app no longer holds counts as cancelled, e.g. when your screen couldn't be presented or was closed without calling either. So keep the prompt in your screen, not in an object that outlives it.
- Present it over the screen, e.g. as a sheet (the default style) or `.overFullScreen`, not pushed or `.fullScreen`: those make the screen disappear, and `stopScreenshotSharing` in `viewWillDisappear` drops the prompt.
- A dropped prompt does nothing: `share()` and `cancel()` return `false`, and `prompt.isActive` is `false`. Check the result to tell the user that nothing was shared.
- The share sheet opens once `share()` has returned, over the topmost presented screen. Dismiss your screen right before or after calling `share()`, or call it in the dismissal's completion as above; if your screen stays, the share sheet opens over it.
- Pass `onEvent` too to follow the progress: it reports nothing while your screen is shown, and after `share()` it follows the flow above, starting with `.creatingLink`, or with `.linkCreated` when a link created earlier in the app session is reused.

> **Upgrading from 0.0.19 or earlier:** `EnvoyType.startScreenshotSharing(from:onEvent:share:)` is now `startScreenshotSharing(from:onEvent:beforeSharing:share:)`. Calls don't change, but types that conform to `EnvoyType`, such as test doubles, must implement the new method.

> **Upgrading from 0.0.17 or earlier:** `EnvoyProtocol`, `Envoy.shared.delegate` and `userDidTookScreenshot(_:)` are removed; the SDK no longer captures the screen. Use `startScreenshotSharing` on the screens where it applies. `NSPhotoLibraryUsageDescription` isn't needed for it.

## 5. Add Gift Button (Optional)

The SDK provides a ready-made gift button. It does nothing on its own, so add an action, e.g. to present the share screen (see 6).

```swift
let button = Envoy.shared.giftButton(request: request)
button.addTarget(self, action: #selector(giftAction), for: .touchUpInside)
containerView.addSubview(button)
```

## 6. Present Share Screen

The share screen creates the link and lets the user share it. When the user taps your share button, call one of these methods on `Envoy.shared` (after `Envoy.initialize(apiKey:)`, see 2):
* `func presentShareGift(from viewController: UIViewController, request: CreateLinkRequest)`
* `func pushShareGift(in navigationController: UINavigationController, request: CreateLinkRequest)`

```swift
import EnvoySDK

class ViewController: UIViewController {
  ...
  @objc func giftAction() {
      Envoy.shared.presentShareGift(from: self, request: request)
  }
  ...
}
```

## 7. Get remaining quota

Get remaining quota for a specific user

```swift
Envoy.shared.getUserRemainingQuota(userId: "1") { response, error in
    print(response)
    print(error)
}
```

## 8. Log pixel event

Log a pixel event

Configure a LogPixelEventRequest with one of the events: `.appDownloaded`, `.accountCreated`, `.trialActivated`, `.paymentSuccess` or `.custom(eventName:)`

```swift
let request = LogPixelEventRequest(event: .appDownloaded)

// With the optional sharer and extra details
let paymentRequest = LogPixelEventRequest(event: .paymentSuccess,
                                          sharerUserId: "sharer-id",
                                          extra: .init(title: "Premium", type: "subscription"))
```

The SDK adds the install attribution (`share_link_hash`, `lead_uuid`) stored by `checkDeferredLink` (see 2.1) when the event is sent.

And log the event using the request

```swift
Envoy.shared.logPixelEvent(request: request) { response, error in
    print(response)
    print(error)
}
```

## 9. Get user rewards

Get rewards for a specific user

```swift
Envoy.shared.getUserRewards(userId: "1") { response, error in
    print(response)
    print(error)
}
```

## 10. Claim user reward

Configure the ClaimUserRewardRequest

```swift
public struct ClaimUserRewardRequest: Encodable {
    public let userId: String
}
```

And claim a reward for a specific user

```swift
Envoy.shared.claimUserReward(request: ClaimUserRewardRequest(userId: "1")) { response, error in
    print(response)
    print(error)
}
```

## 11. Get user current rewards

Get current rewards for a specific user

```swift
Envoy.shared.getUserCurrentRewards(userId: "1") { response, error in
    print(response)
    print(error)
}
```
## 12. Prepare link

Prepare the content at a URL before it's gifted. Only for links with the `.screenshot` content type.

```swift
Envoy.shared.prepLink(request: PrepLinkRequest(url: article.url)) { response, error in
    print(response)
    print(error)
}
```
## 13. Manage Links

Add links to a carousel.

```swift
Envoy.shared.manageLinks(request: ManageLinksRequest(links: ["https://example.com/a", "https://example.com/b"])) { response, error in
    print(response)
    print(error)
}
```
## 14. Clear additional links

Clear additional links from carousel.

```swift
Envoy.shared.clearManagedLinks() { response, error in
    print(response)
    print(error)
}
```