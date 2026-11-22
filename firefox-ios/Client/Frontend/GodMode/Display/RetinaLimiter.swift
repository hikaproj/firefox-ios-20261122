// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import WebKit

@MainActor
public final class RetinaLimiter {
    public static let shared = RetinaLimiter()

    private init() {}

    public func applyScale(to webView: WKWebView) {
        let config = GodModeConfig.shared.state
        guard config.isEnabled && config.retinaScaleLimit > 0.0 else { return }

        let targetScale = CGFloat(config.retinaScaleLimit)
        let screenScale = UIScreen.main.scale

        if screenScale > targetScale {
            webView.contentScaleFactor = targetScale
            webView.layer.contentsScale = targetScale

            for subview in webView.scrollView.subviews {
                subview.contentScaleFactor = targetScale
                subview.layer.contentsScale = targetScale
            }
        }
    }
}
