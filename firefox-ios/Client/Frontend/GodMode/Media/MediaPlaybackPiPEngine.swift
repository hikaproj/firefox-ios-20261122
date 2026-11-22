// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import AVFoundation
import Foundation
import WebKit

@MainActor
public final class MediaPlaybackPiPEngine {
    public static let shared = MediaPlaybackPiPEngine()

    private init() {
        configureAudioSession()
    }

    public func configureAudioSession() {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isBackgroundMediaPlaybackEnabled else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .allowAirPlay])
            try session.setActive(true)
        } catch {
            try? session.setCategory(.playback, options: [.mixWithOthers])
            try? session.setActive(true)
        }
    }

    public func buildMediaScripts() -> [WKUserScript] {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isBackgroundMediaPlaybackEnabled else { return [] }

        let mediaPatchJS = """
        (function() {
            try {
                Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
                Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
                Object.defineProperty(document, 'webkitHidden', { get: function() { return false; }, configurable: true });
                Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: true });

                document.addEventListener('visibilitychange', function(e) {
                    e.stopImmediatePropagation();
                }, true);

                window.addEventListener('pagehide', function(e) {
                    e.stopImmediatePropagation();
                }, true);

                window.__godModeForcedPiP = function() {
                    var videos = Array.from(document.querySelectorAll('video'));
                    var target = videos.find(function(v) { return !v.paused; }) || videos[0];
                    if (!target) return false;
                    if (target.webkitSetPresentationMode) {
                        var current = target.webkitPresentationMode;
                        target.webkitSetPresentationMode(current === 'picture-in-picture' ? 'inline' : 'picture-in-picture');
                        return true;
                    } else if (target.requestPictureInPicture) {
                        target.requestPictureInPicture();
                        return true;
                    }
                    return false;
                };
            } catch(e) {}
        })();
        """

        return [
            WKUserScript(source: mediaPatchJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        ]
    }

    public func triggerPiP(in webView: WKWebView?, completion: ((Bool) -> Void)? = nil) {
        guard let webView = webView else {
            completion?(false)
            return
        }

        webView.evaluateJavaScript("window.__godModeForcedPiP ? window.__godModeForcedPiP() : false") { result, _ in
            let success = (result as? Bool) ?? false
            completion?(success)
        }
    }
}
