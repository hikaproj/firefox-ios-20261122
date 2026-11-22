// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

public struct MITMRule: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var urlRegex: String
    public var method: String
    public var replaceResponseBody: String?
    public var replaceStatusCode: Int
    public var responseContentType: String
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString,
                name: String,
                urlRegex: String,
                method: String = "ANY",
                replaceResponseBody: String? = nil,
                replaceStatusCode: Int = 200,
                responseContentType: String = "application/json",
                isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.urlRegex = urlRegex
        self.method = method
        self.replaceResponseBody = replaceResponseBody
        self.replaceStatusCode = replaceStatusCode
        self.responseContentType = responseContentType
        self.isEnabled = isEnabled
    }
}

@MainActor
public final class NetworkMITMEngine {
    public static let shared = NetworkMITMEngine()

    private var rules: [MITMRule] = []
    private let storageKey = "GodModeMITMRulesKey"

    private init() {
        loadRules()
    }

    public var allRules: [MITMRule] {
        return rules
    }

    public func addRule(_ rule: MITMRule) {
        rules.append(rule)
        saveRules()
    }

    public func removeRule(id: String) {
        rules.removeAll { $0.id == id }
        saveRules()
    }

    public func toggleRule(id: String, isEnabled: Bool) {
        if let idx = rules.firstIndex(where: { $0.id == id }) {
            rules[idx].isEnabled = isEnabled
            saveRules()
        }
    }

    public func buildScript() -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isNetworkMITMEnabled else { return nil }

        let activeRules = rules.filter { $0.isEnabled }
        guard let encoded = try? JSONEncoder().encode(activeRules),
              let jsonString = String(data: encoded, encoding: .utf8) else {
            return nil
        }

        let scriptSource = """
        (function() {
            var mitmRules = \(jsonString);
            if (!mitmRules || mitmRules.length === 0) return;

            function findMatchingRule(url, method) {
                for (var i = 0; i < mitmRules.length; i++) {
                    var r = mitmRules[i];
                    if (!r.isEnabled) continue;
                    if (r.method !== "ANY" && r.method.toUpperCase() !== (method || "GET").toUpperCase()) continue;
                    try {
                        var regex = new RegExp(r.urlRegex);
                        if (regex.test(url)) return r;
                    } catch(e) {}
                }
                return null;
            }

            var origFetch = window.fetch;
            window.fetch = function(resource, init) {
                var url = (typeof resource === 'string') ? resource : (resource ? resource.url : '');
                var method = (init && init.method) ? init.method : ((resource && resource.method) ? resource.method : 'GET');
                var rule = findMatchingRule(url, method);

                if (rule && rule.replaceResponseBody !== null && rule.replaceResponseBody !== undefined) {
                    var mockResponse = new Response(rule.replaceResponseBody, {
                        status: rule.replaceStatusCode || 200,
                        statusText: 'OK (GodMode MITM)',
                        headers: new Headers({
                            'Content-Type': rule.responseContentType || 'application/json',
                            'X-GodMode-MITM': 'Intercepted'
                        })
                    });
                    return Promise.resolve(mockResponse);
                }
                return origFetch.apply(this, arguments);
            };

            var origOpen = XMLHttpRequest.prototype.open;
            var origSend = XMLHttpRequest.prototype.send;

            XMLHttpRequest.prototype.open = function(method, url) {
                this.__godModeUrl = url;
                this.__godModeMethod = method;
                return origOpen.apply(this, arguments);
            };

            XMLHttpRequest.prototype.send = function(body) {
                var rule = findMatchingRule(this.__godModeUrl, this.__godModeMethod);
                if (rule && rule.replaceResponseBody !== null && rule.replaceResponseBody !== undefined) {
                    var self = this;
                    setTimeout(function() {
                        Object.defineProperty(self, 'status', { get: function() { return rule.replaceStatusCode || 200; }, configurable: true });
                        Object.defineProperty(self, 'readyState', { get: function() { return 4; }, configurable: true });
                        Object.defineProperty(self, 'responseText', { get: function() { return rule.replaceResponseBody; }, configurable: true });
                        Object.defineProperty(self, 'response', { get: function() { return rule.replaceResponseBody; }, configurable: true });

                        if (typeof self.onreadystatechange === 'function') self.onreadystatechange();
                        if (typeof self.onload === 'function') self.onload();
                        if (typeof self.onloadend === 'function') self.onloadend();
                    }, 10);
                    return;
                }
                return origSend.apply(this, arguments);
            };
        })();
        """

        return WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private func loadRules() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([MITMRule].self, from: data) {
            self.rules = saved
        }
    }

    private func saveRules() {
        if let encoded = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
