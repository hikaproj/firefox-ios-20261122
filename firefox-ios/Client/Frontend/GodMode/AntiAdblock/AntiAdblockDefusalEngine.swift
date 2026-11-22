// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

public final class AntiAdblockDefusalEngine: Sendable {
    public static let shared = AntiAdblockDefusalEngine()

    private init() {}

    public func buildScript() -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isAntiAdblockDefusalEnabled else { return nil }

        let scriptSource = """
        (function() {
            try {
                window.canRunAds = true;
                window.isAdBlockActive = false;
                window.google_ad_status = 1;
                window.google_ad_client = "ca-pub-0000000000000000";
                window.gaGlobal = {};
                window._adblock = false;
                window.adblockDetector = {
                    init: function() {},
                    detect: function() {},
                    hasAds: function() { return true; },
                    isBlocked: function() { return false; }
                };

                window.addEventListener('DOMContentLoaded', function() {
                    var defuseOverlays = function() {
                        var selectors = [
                            '[id*="adblock-overlay"]',
                            '[class*="adblock-overlay"]',
                            '[id*="anti-adblock"]',
                            '[class*="anti-adblock"]',
                            '[id*="adblock-notice"]',
                            '[class*="adblock-notice"]',
                            '[id*="adblock-modal"]',
                            '[class*="adblock-modal"]'
                        ];
                        selectors.forEach(function(sel) {
                            document.querySelectorAll(sel).forEach(function(el) {
                                el.remove();
                            });
                        });
                        if (document.body && document.body.style.overflow === 'hidden') {
                            document.body.style.overflow = 'auto';
                        }
                    };

                    defuseOverlays();
                    setTimeout(defuseOverlays, 1000);
                    setTimeout(defuseOverlays, 3000);
                });
            } catch(e) {}
        })();
        """

        return WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
