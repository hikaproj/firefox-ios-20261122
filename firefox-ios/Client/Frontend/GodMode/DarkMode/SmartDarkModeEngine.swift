// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit
import os.lock

public final class SmartDarkModeEngine: @unchecked Sendable {
    public static let shared = SmartDarkModeEngine()

    private var lock = os_unfair_lock()
    private var customCSSStore: [String: String] = [:]
    private let storageKey = "GodModeDomainCustomCSSKey"

    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            self.customCSSStore = saved
        }
    }

    public func setCustomCSS(_ css: String, for domain: String) {
        os_unfair_lock_lock(&lock)
        customCSSStore[domain] = css
        let copy = customCSSStore
        os_unfair_lock_unlock(&lock)

        UserDefaults.standard.set(copy, forKey: storageKey)
    }

    public func getCustomCSS(for domain: String) -> String? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return customCSSStore[domain]
    }

    public func removeCustomCSS(for domain: String) {
        os_unfair_lock_lock(&lock)
        customCSSStore.removeValue(forKey: domain)
        let copy = customCSSStore
        os_unfair_lock_unlock(&lock)

        UserDefaults.standard.set(copy, forKey: storageKey)
    }

    public func getAllCustomCSSRules() -> [String: String] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return customCSSStore
    }

    public func buildSmartDarkModeScript() -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isSmartDarkModeEnabled else { return nil }

        let css = """
        html {
            filter: invert(100%) hue-rotate(180deg) !important;
            background: #111 !important;
        }
        img, video, canvas, svg, picture, [style*="background-image"], iframe {
            filter: invert(100%) hue-rotate(180deg) !important;
        }
        """

        let escapedCSS = css.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            var el = document.createElement('style');
            el.id = '__godModeSmartDarkMode';
            el.textContent = '\(escapedCSS)';
            (document.head || document.documentElement).appendChild(el);
        })();
        """

        return WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    public func buildCustomCSSScript(for url: URL?) -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled,
              let host = url?.host?.lowercased() else { return nil }

        os_unfair_lock_lock(&lock)
        let css = customCSSStore[host] ?? customCSSStore.first(where: { host.hasSuffix($0.key) })?.value
        os_unfair_lock_unlock(&lock)

        guard let targetCSS = css, !targetCSS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let escapedCSS = targetCSS.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            var el = document.createElement('style');
            el.id = '__godModeDomainCustomCSS';
            el.textContent = '\(escapedCSS)';
            (document.head || document.documentElement).appendChild(el);
        })();
        """

        return WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }
}
