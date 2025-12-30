import Foundation

private final class BundleToken {}

extension Bundle {
    static var envoyBundle: Bundle {
        let rootBundle = Bundle(for: BundleToken.self)
        return Bundle(url: rootBundle.resourceURL!.appendingPathComponent("EnvoySDK.bundle", isDirectory: true))!
    }
}
