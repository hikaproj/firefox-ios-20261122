// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

@MainActor
public final class CrashGuardManager {
    public static let shared = CrashGuardManager()

    private var recentCrashes: [String: [Date]] = [:]
    private var quarantinedHosts: Set<String> = []

    private init() {}

    public func isQuarantined(url: URL) -> Bool {
        guard let host = url.host else { return false }
        return quarantinedHosts.contains(host)
    }

    func handleProcessTermination(webView: WKWebView, in bvc: BrowserViewController) -> Bool {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isCrashGuardEnabled,
              let tab = bvc.tabManager[webView] else {
            return false
        }

        let targetKey = tab.url?.host ?? tab.lastKnownUrl?.host ?? "unknown"
        let now = Date()
        var timestamps = recentCrashes[targetKey] ?? []
        timestamps = timestamps.filter { now.timeIntervalSince($0) < 60.0 }
        timestamps.append(now)
        recentCrashes[targetKey] = timestamps

        let threshold = GodModeConfig.shared.state.crashQuarantineThreshold
        if timestamps.count >= threshold {
            quarantinedHosts.insert(targetKey)
            quarantineTab(tab, host: targetKey)
            return true
        }

        return false
    }

    private func quarantineTab(_ tab: Tab, host: String) {
        let safeHTML = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        body { font-family: -apple-system, system-ui; background: #121214; color: #fff; padding: 24px; text-align: center; }
        .card { background: #1c1c1e; border-radius: 14px; padding: 20px; margin-top: 40px; border: 1px solid #333; }
        h2 { color: #ff453a; font-size: 20px; margin-bottom: 8px; }
        p { color: #aaa; font-size: 14px; line-height: 1.5; }
        .btn { display: inline-block; margin-top: 16px; padding: 10px 18px; border-radius: 8px; background: #0a84ff; color: #fff; text-decoration: none; font-weight: bold; font-size: 14px; }
        </style>
        </head>
        <body>
        <div class="card">
        <h2>🛡️ GodMode Crash Guard</h2>
        <p>WebContent process for <b>\(host)</b> crashed repeatedly.<br>Page quarantined to prevent OS Jetsam termination.</p>
        <a class="btn" href="javascript:location.reload()">Retry Once</a>
        </div>
        </body>
        </html>
        """
        tab.webView?.loadHTMLString(safeHTML, baseURL: nil)
    }
}
