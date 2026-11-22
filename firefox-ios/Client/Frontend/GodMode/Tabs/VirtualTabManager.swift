// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit

@MainActor
public final class VirtualTabManager {
    public static let shared = VirtualTabManager()

    private init() {}

    public func didSelectTab(_ tab: Tab, in bvc: BrowserViewController) {
        TabHibernationManager.shared.markTabActive(tab)
        enforceLimit(in: bvc)
    }

    public func enforceLimit(in bvc: BrowserViewController) {
        let config = GodModeConfig.shared.state
        guard config.isEnabled else { return }

        let maxActive = max(1, config.maxActiveWebViews)
        let tabsWithWebView = bvc.tabManager.tabs.filter { $0.webView != nil }

        guard tabsWithWebView.count > maxActive else { return }

        let selected = bvc.tabManager.selectedTab
        let candidates = tabsWithWebView.filter { $0 !== selected }
            .sorted { $0.lastExecutedTime < $1.lastExecutedTime }

        let excessCount = tabsWithWebView.count - maxActive
        let toOffload = candidates.prefix(excessCount)

        for tab in toOffload {
            TabHibernationManager.shared.hibernateTab(tab)
        }
    }
}
