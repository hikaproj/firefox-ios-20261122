// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

public struct ClonedCookie: Codable, Sendable {
    public let name: String
    public let value: String
    public let domain: String
    public let path: String
    public let isSecure: Bool
    public let isHTTPOnly: Bool
    public let expiresDate: Date?

    public init(from httpCookie: HTTPCookie) {
        self.name = httpCookie.name
        self.value = httpCookie.value
        self.domain = httpCookie.domain
        self.path = httpCookie.path
        self.isSecure = httpCookie.isSecure
        self.isHTTPOnly = httpCookie.isHTTPOnly
        self.expiresDate = httpCookie.expiresDate
    }

    public func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if isSecure { properties[.secure] = "TRUE" }
        if let expires = expiresDate { properties[.expires] = expires }

        return HTTPCookie(properties: properties)
    }
}

public struct ClonedSession: Codable, Sendable {
    public let domain: String
    public let exportedAt: Date
    public let cookies: [ClonedCookie]
    public let localStorage: [String: String]
    public let sessionStorage: [String: String]
}

@MainActor
public final class SessionCloneEngine {
    public static let shared = SessionCloneEngine()

    private init() {}

    public func exportSession(from webView: WKWebView) async -> String? {
        guard let url = webView.url, let host = url.host else { return nil }

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = await cookieStore.allCookies()
        let matchingCookies = allCookies.filter { cookie in
            host.contains(cookie.domain) || cookie.domain.contains(host)
        }.map { ClonedCookie(from: $0) }

        let storageScript = """
        (function() {
            var local = {};
            var session = {};
            try {
                for (var i = 0; i < localStorage.length; i++) {
                    var k = localStorage.key(i);
                    local[k] = localStorage.getItem(k);
                }
            } catch(e) {}
            try {
                for (var j = 0; j < sessionStorage.length; j++) {
                    var sk = sessionStorage.key(j);
                    session[sk] = sessionStorage.getItem(sk);
                }
            } catch(e) {}
            return JSON.stringify({ local: local, session: session });
        })();
        """

        let storageResult = try? await webView.evaluateJavaScript(storageScript) as? String
        var localStorageMap: [String: String] = [:]
        var sessionStorageMap: [String: String] = [:]

        if let storageJson = storageResult?.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: storageJson) as? [String: [String: String]] {
            localStorageMap = parsed["local"] ?? [:]
            sessionStorageMap = parsed["session"] ?? [:]
        }

        let session = ClonedSession(
            domain: host,
            exportedAt: Date(),
            cookies: matchingCookies,
            localStorage: localStorageMap,
            sessionStorage: sessionStorageMap
        )

        guard let encoded = try? JSONEncoder().encode(session),
              let jsonString = String(data: encoded, encoding: .utf8) else {
            return nil
        }

        return jsonString
    }

    public func importSession(jsonString: String, into webView: WKWebView) async -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let session = try? JSONDecoder().decode(ClonedSession.self, from: data) else {
            return false
        }

        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        for clonedCookie in session.cookies {
            if let httpCookie = clonedCookie.toHTTPCookie() {
                await cookieStore.setCookie(httpCookie)
            }
        }

        if let localData = try? JSONEncoder().encode(session.localStorage),
           let localJson = String(data: localData, encoding: .utf8),
           let sessionData = try? JSONEncoder().encode(session.sessionStorage),
           let sessionJson = String(data: sessionData, encoding: .utf8) {
            let injectScript = """
            (function() {
                try {
                    var local = \(localJson);
                    for (var k in local) {
                        localStorage.setItem(k, local[k]);
                    }
                } catch(e) {}
                try {
                    var sess = \(sessionJson);
                    for (var sk in sess) {
                        sessionStorage.setItem(sk, sess[sk]);
                    }
                } catch(e) {}
            })();
            """
            _ = try? await webView.evaluateJavaScript(injectScript)
        }

        return true
    }
}
