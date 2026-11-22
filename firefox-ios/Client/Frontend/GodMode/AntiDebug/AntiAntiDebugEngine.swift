// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

public final class AntiAntiDebugEngine: Sendable {
    public static let shared = AntiAntiDebugEngine()

    private init() {}

    public func buildScript() -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isAntiAntiDebugEnabled else { return nil }

        let scriptSource = """
        (function() {
            try {
                var blockedEvents = ['copy', 'cut', 'paste', 'contextmenu', 'selectstart', 'dragstart'];
                var origAEL = EventTarget.prototype.addEventListener;

                EventTarget.prototype.addEventListener = function(type, listener, options) {
                    if (blockedEvents.indexOf(type) !== -1) {
                        var wrapped = function(e) {
                            var origPD = e.preventDefault;
                            e.preventDefault = function() {};
                            var res = (typeof listener === 'function') ? listener.apply(this, arguments) : (listener && listener.handleEvent && listener.handleEvent(e));
                            e.preventDefault = origPD;
                            return res;
                        };
                        return origAEL.call(this, type, wrapped, options);
                    }
                    return origAEL.apply(this, arguments);
                };

                ['copy', 'cut', 'paste', 'contextmenu', 'selectstart'].forEach(function(eventType) {
                    document.addEventListener(eventType, function(e) {
                        e.stopImmediatePropagation();
                    }, true);
                });

                var style = document.createElement('style');
                style.type = 'text/css';
                style.appendChild(document.createTextNode('* { user-select: auto !important; -webkit-user-select: auto !important; -webkit-touch-callout: default !important; }'));
                (document.head || document.documentElement).appendChild(style);

                var origFunction = Function.prototype.constructor;
                window.Function = function() {
                    var args = Array.prototype.slice.call(arguments);
                    for (var i = 0; i < args.length; i++) {
                        if (typeof args[i] === 'string' && args[i].indexOf('debugger') !== -1) {
                            args[i] = args[i].replace(/debugger/g, '/* bypassed */');
                        }
                    }
                    return origFunction.apply(this, args);
                };
                window.Function.prototype = origFunction.prototype;
            } catch(e) {}
        })();
        """

        return WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
