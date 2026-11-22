// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

@MainActor
public final class DynamicJSEngineKiller {
    public static let shared = DynamicJSEngineKiller()

    private var disabledDomains: Set<String> = []

    private init() {}

    public func shouldAllowJavaScript(for url: URL?) -> Bool {
        let config = GodModeConfig.shared.state
        guard config.isEnabled else { return true }

        if !config.allowsContentJavaScript {
            return false
        }

        if let host = url?.host, disabledDomains.contains(host) {
            return false
        }

        return true
    }

    public func setJavaScriptEnabled(_ enabled: Bool, for host: String) {
        if enabled {
            disabledDomains.remove(host)
        } else {
            disabledDomains.insert(host)
        }
    }

    public func configure(preferences: WKWebpagePreferences, for url: URL?) {
        preferences.allowsContentJavaScript = shouldAllowJavaScript(for: url)
    }
}
