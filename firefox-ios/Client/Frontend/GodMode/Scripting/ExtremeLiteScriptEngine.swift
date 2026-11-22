// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

public final class ExtremeLiteScriptEngine: Sendable {
    public static let shared = ExtremeLiteScriptEngine()

    private init() {}

    public func buildUserScripts(for config: GodModeState) -> [WKUserScript] {
        guard config.isEnabled else { return [] }

        var scripts: [WKUserScript] = []

        var cssRules: [String] = []

        if config.disableCSSAnimations {
            cssRules.append("""
            *, *::before, *::after {
                animation-duration: 0.001s !important;
                animation-delay: 0s !important;
                transition-duration: 0.001s !important;
                transition-delay: 0s !important;
            }
            """)
        }

        if config.stripHeavyGPUCSS {
            cssRules.append("""
            *, *::before, *::after {
                backdrop-filter: none !important;
                -webkit-backdrop-filter: none !important;
                filter: none !important;
                -webkit-filter: none !important;
                box-shadow: none !important;
                text-shadow: none !important;
                will-change: auto !important;
            }
            """)
        }

        if config.blockWebFonts {
            cssRules.append("""
            * {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif !important;
            }
            @font-face {
                font-family: 'GodModeBlockedFont';
                src: local('Arial');
            }
            """)
        }

        if config.blockImages {
            cssRules.append("""
            img, image, picture, svg, canvas {
                display: none !important;
                visibility: hidden !important;
            }
            """)
        }

        if !cssRules.isEmpty {
            let combinedCSS = cssRules.joined(separator: "\n")
            let cssInjectionJS = """
            (function() {
                var style = document.createElement('style');
                style.type = 'text/css';
                style.appendChild(document.createTextNode(`\(combinedCSS)`));
                var target = document.head || document.documentElement;
                if (target) {
                    target.appendChild(style);
                } else {
                    document.addEventListener('DOMContentLoaded', function() {
                        (document.head || document.documentElement).appendChild(style);
                    });
                }
            })();
            """
            scripts.append(WKUserScript(source: cssInjectionJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }

        if config.stripAutoplayVideo {
            let autoplayBlockJS = """
            (function() {
                var origPlay = HTMLMediaElement.prototype.play;
                HTMLMediaElement.prototype.play = function() {
                    if (this.autoplay && !this.paused) {
                        this.autoplay = false;
                        this.preload = 'none';
                        return Promise.reject(new Error('GodMode: Autoplay blocked'));
                    }
                    return origPlay.apply(this, arguments);
                };
                window.addEventListener('DOMContentLoaded', function() {
                    document.querySelectorAll('video, audio').forEach(function(el) {
                        el.autoplay = false;
                        el.preload = 'none';
                    });
                });
            })();
            """
            scripts.append(WKUserScript(source: autoplayBlockJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }

        if config.lazyLoadImages && !config.blockImages {
            let lazyLoadJS = """
            (function() {
                window.addEventListener('DOMContentLoaded', function() {
                    document.querySelectorAll('img').forEach(function(img) {
                        if (!img.loading) {
                            img.loading = 'lazy';
                        }
                    });
                });
            })();
            """
            scripts.append(WKUserScript(source: lazyLoadJS, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        }

        if config.domPruningEnabled {
            let domPrunerJS = """
            (function() {
                var lastPrune = 0;
                function pruneOffscreenNodes() {
                    var now = Date.now();
                    if (now - lastPrune < 2500) return;
                    lastPrune = now;
                    var viewHeight = window.innerHeight;
                    var maxDistance = viewHeight * 4;
                    var candidates = document.querySelectorAll('article, section, [data-testid], .tweet, .post');
                    if (candidates.length < 50) return;
                    for (var i = 0; i < candidates.length - 20; i++) {
                        var node = candidates[i];
                        var rect = node.getBoundingClientRect();
                        if (rect.bottom < -maxDistance && !node.dataset.godmodePruned) {
                            node.dataset.godmodePruned = 'true';
                            node.style.height = rect.height + 'px';
                            node.innerHTML = '';
                        }
                    }
                }
                window.addEventListener('scroll', pruneOffscreenNodes, { passive: true });
            })();
            """
            scripts.append(WKUserScript(source: domPrunerJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }

        if config.textOnlyModeEnabled {
            let textStripperJS = """
            (function() {
                window.addEventListener('DOMContentLoaded', function() {
                    var elements = document.querySelectorAll('script, style, iframe, svg, canvas, video, img, picture, audio');
                    elements.forEach(function(el) { el.remove(); });
                    document.body.style.backgroundColor = '#121214';
                    document.body.style.color = '#e0e0e0';
                    document.body.style.fontFamily = '-apple-system, sans-serif';
                    document.body.style.lineHeight = '1.6';
                    document.body.style.padding = '16px';
                });
            })();
            """
            scripts.append(WKUserScript(source: textStripperJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }

        if config.thermalThrottlingEnabled {
            let thermalFPSJS = """
            (function() {
                var targetFPS = 30;
                var minInterval = 1000 / targetFPS;
                var lastFrameTime = 0;
                var realRAF = window.requestAnimationFrame;
                window.requestAnimationFrame = function(callback) {
                    return realRAF(function(timestamp) {
                        var delta = timestamp - lastFrameTime;
                        if (delta >= minInterval) {
                            lastFrameTime = timestamp;
                            callback(timestamp);
                        } else {
                            setTimeout(function() { callback(performance.now()); }, minInterval - delta);
                        }
                    });
                };
            })();
            """
            scripts.append(WKUserScript(source: thermalFPSJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        return scripts
    }
}
