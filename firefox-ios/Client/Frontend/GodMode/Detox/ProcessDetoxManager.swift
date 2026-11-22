// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

@MainActor
public final class ProcessDetoxManager {
    public static let shared = ProcessDetoxManager()

    private init() {}

    public func detoxTab(_ tab: Tab, in bvc: BrowserViewController) {
        guard let url = tab.url ?? tab.lastKnownUrl else { return }

        Task { @MainActor [weak bvc, weak tab] in
            guard let bvc = bvc, let tab = tab else { return }
            let savedUrl = url
            await tab.offloadWebView()
            bvc.tabManager.selectTab(tab, previous: nil, immediatePreservation: false)
            if tab.webView?.url == nil {
                tab.loadRequest(URLRequest(url: savedUrl))
            }
        }
    }
}
