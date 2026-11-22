// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

public final class AntiFingerprintingEngine: Sendable {
    public static let shared = AntiFingerprintingEngine()

    private let trackingQueryParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "gbraid", "wbraid", "msclkid", "mc_eid", "igshid",
        "_hsenc", "_openstat", "yclid"
    ]

    private init() {}

    public func cleanURL(_ url: URL) -> URL {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isTrackingParameterStrippingEnabled,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems, !queryItems.isEmpty else {
            return url
        }

        let filtered = queryItems.filter { item in
            !trackingQueryParameters.contains(item.name.lowercased())
        }

        components.queryItems = filtered.isEmpty ? nil : filtered
        return components.url ?? url
    }

    public func buildScript() -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled else { return nil }

        let config = GodModeConfig.shared.state
        guard config.isCanvasAudioNoiseEnabled || config.isReferrerStrippingEnabled else { return nil }

        let scriptSource = """
        (function() {
            try {
                var origToDataURL = HTMLCanvasElement.prototype.toDataURL;
                HTMLCanvasElement.prototype.toDataURL = function() {
                    var ctx = this.getContext('2d');
                    if (ctx && this.width > 0 && this.height > 0) {
                        try {
                            var imgData = ctx.getImageData(0, 0, 1, 1);
                            imgData.data[0] = (imgData.data[0] + 1) % 256;
                            ctx.putImageData(imgData, 0, 0);
                        } catch(e) {}
                    }
                    return origToDataURL.apply(this, arguments);
                };

                var origGetImageData = CanvasRenderingContext2D.prototype.getImageData;
                CanvasRenderingContext2D.prototype.getImageData = function() {
                    var res = origGetImageData.apply(this, arguments);
                    if (res && res.data && res.data.length > 3) {
                        res.data[0] = (res.data[0] + 1) % 256;
                    }
                    return res;
                };

                if (window.AudioBuffer) {
                    var origGetChannelData = AudioBuffer.prototype.getChannelData;
                    AudioBuffer.prototype.getChannelData = function() {
                        var buffer = origGetChannelData.apply(this, arguments);
                        if (buffer && buffer.length > 0) {
                            buffer[0] = buffer[0] + 0.0000001;
                        }
                        return buffer;
                    };
                }

                Object.defineProperty(navigator, 'hardwareConcurrency', { get: function() { return 4; }, configurable: true });
                Object.defineProperty(navigator, 'deviceMemory', { get: function() { return 8; }, configurable: true });

                Object.defineProperty(document, 'referrer', { get: function() { return ''; }, configurable: true });
                var meta = document.createElement('meta');
                meta.name = 'referrer';
                meta.content = 'no-referrer';
                (document.head || document.documentElement).appendChild(meta);
            } catch(e) {}
        })();
        """

        return WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
