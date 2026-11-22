// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

@MainActor
public final class JSTimeWarpEngine {
    public static let shared = JSTimeWarpEngine()

    public private(set) var currentSpeed: Double = 1.0

    private init() {}

    public func setSpeed(_ speed: Double, in webView: WKWebView?) {
        self.currentSpeed = max(0.1, min(50.0, speed))
        GodModeConfig.shared.update { state in
            state.timeWarpSpeed = self.currentSpeed
        }
        let js = "if (window.__godModeSetSpeed) { window.__godModeSetSpeed(\(self.currentSpeed)); }"
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    public func buildScript() -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled else { return nil }

        let initialSpeed = GodModeConfig.shared.state.timeWarpSpeed

        let scriptSource = """
        (function() {
            var speed = \(initialSpeed);
            var realStart = Date.now();
            var virtualStart = realStart;
            var realPerfStart = performance.now();
            var virtualPerfStart = realPerfStart;

            window.__godModeSetSpeed = function(newSpeed) {
                var now = Date.now();
                virtualStart = virtualStart + (now - realStart) * speed;
                realStart = now;

                var pNow = performance.now();
                virtualPerfStart = virtualPerfStart + (pNow - realPerfStart) * speed;
                realPerfStart = pNow;

                speed = Math.max(0.1, Math.min(50.0, newSpeed));
            };

            var origDateNow = Date.now;
            Date.now = function() {
                var now = origDateNow();
                return virtualStart + (now - realStart) * speed;
            };

            var origPerfNow = performance.now.bind(performance);
            performance.now = function() {
                var now = origPerfNow();
                return virtualPerfStart + (now - realPerfStart) * speed;
            };

            var origSetTimeout = window.setTimeout;
            window.setTimeout = function(callback, delay) {
                var args = Array.prototype.slice.call(arguments, 2);
                var scaledDelay = (delay || 0) / (speed || 1.0);
                return origSetTimeout(function() {
                    callback.apply(null, args);
                }, scaledDelay);
            };

            var origSetInterval = window.setInterval;
            window.setInterval = function(callback, delay) {
                var args = Array.prototype.slice.call(arguments, 2);
                var scaledDelay = (delay || 0) / (speed || 1.0);
                return origSetInterval(function() {
                    callback.apply(null, args);
                }, scaledDelay);
            };
        })();
        """

        return WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
