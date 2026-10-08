//
//  UserDefaultsExtensions.swift
//  EnvoySDK
//
//

import Foundation

extension UserDefaults {
    
    private struct Keys {
        // Prefixed, because these live in the host app's defaults. The generic "isFreshInstall"
        // used before 0.1.0 is not read: it may be the host's own, and existing installs are
        // covered by the install-age limit of the deferred-link check.
        static let isDeferredLinkCheckDone = "envoy.isDeferredLinkCheckDone"
        static let notifyScreenShot = "notifyScreenShot"
    }
    
    // MARK: Deferred link
    var isDeferredLinkCheckDone: Bool {
        bool(forKey: Keys.isDeferredLinkCheckDone)
    }

    func setDeferredLinkCheckDone() {
        set(true, forKey: Keys.isDeferredLinkCheckDone)
    }
}
