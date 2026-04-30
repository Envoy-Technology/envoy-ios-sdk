<a name="introduction"></a>
# Overview

Envoy iOS SDK aimed to deliver a fast solution to share content out of the iOS Application.

> **Authorization and Mixpanel usage**: For now ios-sdk has outdated in mentioned parts

# Quick Start Guide

## 1. Install Envoy SDK
You can install the Envoy iOS SDK - Swift library by using CocoaPods. You will need your project token for initializing your library. You can get your project token from [account settings](https://dev-platform.envoy.is/dashboard/account/).

### Installation CocoaPods
1. If this is your first time using CocoaPods, Install CocoaPods using `gem install cocoapods`. Otherwise, continue to Step 3.
2. Run `pod setup` to create a local CocoaPods spec mirror.
3. Create a Podfile in your Xcode project directory by running `pod init` in your terminal, edit the Podfile generated, and add the following line: `pod 'EnvoySDK'`.
4. Run `pod install` in your Xcode project directory. CocoaPods should download and install the EnvoySDK library, and create a new Xcode workspace. Open up this workspace in Xcode or typing `open *.xcworkspace` in your terminal.

## 2. Initialize EnvoySDK
To initialize the library, add `import EnvoySDK` into `AppDelegate` and call `initialize(apiKey:)` in [application:didFinishLaunchingWithOptions:](https://developer.apple.com/documentation/uikit/uiapplicationdelegate#//apple_ref/occ/intfm/UIApplicationDelegate/application:willFinishLaunchingWithOptions:)
```swift
import EnvoySDK

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
...
  Envoy.initialize(apiKey: {your-api-key})
...
}
```

## 2.1 Initialize EnvoySDK with delegate (optional)
To get inform when user did took screenshot add delegate right after SDK initialization and add EnvoyProtocol AppDelegate extension. 

```swift
import EnvoySDK

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
...
  Envoy.initialize(apiKey: {your-api-key})
  Envoy.shared.delegate = self
...
}

extension AppDelegate: EnvoyProtocol {
    func userDidTookScreenshot(_ image: UIImage?) { }
}

```    
To also capture user screenshots, add information about intentions and purpose of this action to info.plis application for key
```NSPhotoLibraryUsageDescription``` 


## 3. Configure `CreateLinkRequest`

You need to configure `CreateLinkRequest` with content, which you wanted to be shared. Request is pretty flexible and have both required and optional values.

```swift

 public struct CreateLinkRequest: Codable {
    let autoplay: Bool?
    let contentSetting: ContentSetting
    let lifespanAfterClick: LifespanAfterClick?
    let openQuota: Int?
    let extra: String?
    let sharerId: String
    let isSandbox: Bool?
    let labels: [Label]?
    
    public struct Common: Codable {
        let source: String
        let sourceIsRedirect: Bool?
        let poster: String?
    }

    public struct ContentProtection: Codable {
        let media: Common
    }

    public struct ContentSetting: Codable {
        let contentType: String
        let contentName: String
        let contentDescription: String
        let common: Common?
        let base64_file: String?
        let timeLimit: Int?
        let timeStart: Int?
        let availableFrom: String?
        let availableTo: String?
        let videoOrientation: Int?
        let previewTitle: String?
        let previewDescription: String?
        let previewImage: String?
        let mandatoryEmail: Bool?
        let modalTitle: String?
        let buttonText: String?
        let contentProtection: ContentProtection?
    }

    public struct LifespanAfterClick: Codable {
        let value: Int?
        let unit: String
    }

    public struct Label: Codable {
        let id: Int?
        let text: String
        let color: String
    }
```

## 4. Create link

Create a link using the previously configured request and handle the response and potential error

```swift
Envoy.shared.createLink(request: request) { response, error in            
    print(response)
    print(error)
}
```

## 4.1 Create link based on screenshot
CreateLink function also supports base64 images generated from screenshots taken by the user. 

Example of how to create request with image for CreateLink function.
```swift
    private func mockedScreenshotLinkRequest(image: UIImage) -> CreateLinkRequest {
        let imageBase64 = image.base64
        let contentSetting = CreateLinkRequest.ContentSetting(
            contentType: "SCREENSHOT",
            contentName: "Test screenshot Base64",
            contentDescription: "Content description Base64",
            base64_file: imageBase64)

        return CreateLinkRequest(autoplay: nil,
                                 contentSetting: contentSetting,
                                 sharerId: "ID",
                                 isSandbox: true)
    }
```

## 5. Add Gift Button (Optional)

SDK gives ability to add gift button with SDK design for quick implementation.

```swift
let button = envoySDK.giftButton(request: request)
buttin.addTarget(self, action: #selector(giftAction), for: .touchUpInside)
containerView.addSubview(button)
```

## 6. Present Share Screen

To present share screen you need to initialize instance of `Envoy` with `apiKey`. You can get your project token from [account settings](https://dev-platform.envoy.is/dashboard/account/).
Upon tapping on share button you need to call any of these methods.
* `func presentShareGift(from viewController: UIViewController, request: CreateLinkRequest)`
* `func pushShareGift(in navigationController: UINavigationController, request: CreateLinkRequest)`

```swift
import EnvoySDK

class ViewController: UIViewController {
  ...
  func giftAction() {
      envoySDK.presentShareGift(from: self, request: request)
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

Configure a LogPixelEventRequest

```swift
public struct LogPixelEventRequest: Encodable {
    public struct Extra: Encodable {
        let title: String?
        let type: String?
    }
    
    let eventName: String
    let userId: String?
    let sharerUserId: String?
    let shareLinkHash: String?
    let extra: Extra?
}
```

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
Envoy.shared.claimUserReward(request: request) { response, error in
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

Prepare link's content before it's gifted. Function specific for SCREENSHOT types of links.

```swift
Envoy.shared.prepLink(request: request) { response, error in
    print(response)
    print(error)
}
```