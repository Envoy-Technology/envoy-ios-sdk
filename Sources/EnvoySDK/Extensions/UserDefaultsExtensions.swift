//
//  UserDefaultsExtensions.swift
//  EnvoySDK
//
//

import Foundation

extension UserDefaults {
    
    private struct Keys {
        // Prefixed, because these live in the host app's defaults.
        static let isDeferredLinkCheckDone = "envoy.isDeferredLinkCheckDone"
        /// Written by SDKs before 0.0.16; generic, so the host app may use it too.
        static let legacyIsFreshInstall = "isFreshInstall"
    }
    
    // MARK: Deferred link
    var isDeferredLinkCheckDone: Bool {
        bool(forKey: Keys.isDeferredLinkCheckDone)
    }

    func setDeferredLinkCheckDone() {
        set(true, forKey: Keys.isDeferredLinkCheckDone)
    }

    /// Runs at every SDK start but acts only once per install, at the first start of 0.0.16 or later.
    /// SDKs before 0.0.16 read the clipboard at the first launch and stored "isFreshInstall" = false,
    /// so an update from them must not check again. Reading the generic key only this once, at SDK start,
    /// keeps a host app that writes the same key later, e.g. in onboarding, from disabling the check.
    func migrateDeferredLinkCheckDone() {
        guard object(forKey: Keys.isDeferredLinkCheckDone) == nil else { return }
        let checkedByEarlierSDK = object(forKey: Keys.legacyIsFreshInstall) as? Bool == false
        set(checkedByEarlierSDK, forKey: Keys.isDeferredLinkCheckDone)
    }
}
