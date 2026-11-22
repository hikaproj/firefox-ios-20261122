// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit
import os.lock

public enum DevToolsLogLevel: String, Codable, Sendable {
    case log
    case info
    case warn
    case error
    case debug
}

public struct DevToolsConsoleEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: DevToolsLogLevel
    public let message: String
    public let source: String?
    public let lineNumber: Int?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: DevToolsLogLevel,
        message: String,
        source: String? = nil,
        lineNumber: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = String(message.prefix(65536))
        self.source = source
        self.lineNumber = lineNumber
    }
}

public struct DevToolsNetworkEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let method: String
    public let url: String
    public let statusCode: Int
    public let requestHeaders: [String: String]
    public let requestBody: String?
    public let responseHeaders: [String: String]
    public let responseBody: String?
    public let durationMs: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        method: String,
        url: String,
        statusCode: Int,
        requestHeaders: [String: String] = [:],
        requestBody: String? = nil,
        responseHeaders: [String: String] = [:],
        responseBody: String? = nil,
        durationMs: Double = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody.map { String($0.prefix(65536)) }
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody.map { String($0.prefix(65536)) }
        self.durationMs = durationMs
    }

    public var curlCommand: String {
        var parts: [String] = ["curl"]
        if method.uppercased() != "GET" {
            parts.append("-X \(method.uppercased())")
        }
        parts.append("\"\(url)\"")
        for (k, v) in requestHeaders {
            let escapedVal = v.replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("-H \"\(k): \(escapedVal)\"")
        }
        if let body = requestBody, !body.isEmpty {
            let escapedBody = body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("--data-raw '\(escapedBody)'")
        }
        return parts.joined(separator: " \\\n  ")
    }
}

public final class DevToolsEngine: @unchecked Sendable {
    public static let shared = DevToolsEngine()

    private var lock = os_unfair_lock()
    private var consoleRingBuffer: [DevToolsConsoleEntry] = []
    private var networkRingBuffer: [DevToolsNetworkEntry] = []
    private let maxEntries: Int = 100

    public static let didUpdateConsoleNotification = Notification.Name("GodModeDevToolsDidUpdateConsole")
    public static let didUpdateNetworkNotification = Notification.Name("GodModeDevToolsDidUpdateNetwork")

    private init() {}

    public func addConsoleEntry(_ entry: DevToolsConsoleEntry) {
        os_unfair_lock_lock(&lock)
        if consoleRingBuffer.count >= maxEntries {
            consoleRingBuffer.removeFirst()
        }
        consoleRingBuffer.append(entry)
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didUpdateConsoleNotification, object: entry)
        }
    }

    public func addNetworkEntry(_ entry: DevToolsNetworkEntry) {
        os_unfair_lock_lock(&lock)
        if networkRingBuffer.count >= maxEntries {
            networkRingBuffer.removeFirst()
        }
        networkRingBuffer.append(entry)
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didUpdateNetworkNotification, object: entry)
        }
    }

    public func getConsoleEntries() -> [DevToolsConsoleEntry] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return consoleRingBuffer
    }

    public func getNetworkEntries() -> [DevToolsNetworkEntry] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return networkRingBuffer
    }

    public func clearAll() {
        os_unfair_lock_lock(&lock)
        consoleRingBuffer.removeAll()
        networkRingBuffer.removeAll()
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didUpdateConsoleNotification, object: nil)
            NotificationCenter.default.post(name: Self.didUpdateNetworkNotification, object: nil)
        }
    }

    public func buildScript() -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isDevToolsEnabled else { return nil }

        let js = """
        (function() {
            if (window.__godModeDevToolsInjected) return;
            window.__godModeDevToolsInjected = true;

            const originalConsole = {
                log: console.log,
                info: console.info,
                warn: console.warn,
                error: console.error,
                debug: console.debug
            };

            function safeStringify(args) {
                return Array.from(args).map(arg => {
                    if (arg === null) return 'null';
                    if (arg === undefined) return 'undefined';
                    if (typeof arg === 'object') {
                        try {
                            const seen = new WeakSet();
                            return JSON.stringify(arg, (key, value) => {
                                if (typeof value === 'object' && value !== null) {
                                    if (seen.has(value)) return '[Circular]';
                                    seen.add(value);
                                }
                                return value;
                            });
                        } catch(e) {
                            return String(arg);
                        }
                    }
                    return String(arg);
                }).join(' ');
            }

            ['log', 'info', 'warn', 'error', 'debug'].forEach(level => {
                console[level] = function() {
                    originalConsole[level].apply(console, arguments);
                    try {
                        const msg = safeStringify(arguments).substring(0, 65536);
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.godModeDevToolsConsole) {
                            window.webkit.messageHandlers.godModeDevToolsConsole.postMessage({
                                level: level,
                                message: msg
                            });
                        }
                    } catch(e) {}
                };
            });

            const origFetch = window.fetch;
            if (origFetch) {
                window.fetch = async function(...args) {
                    const startTime = Date.now();
                    let url = '';
                    let method = 'GET';
                    let reqHeaders = {};
                    let reqBody = '';

                    try {
                        if (typeof args[0] === 'string') {
                            url = args[0];
                        } else if (args[0] instanceof Request) {
                            url = args[0].url;
                            method = args[0].method || 'GET';
                        }
                        if (args[1]) {
                            if (args[1].method) method = args[1].method;
                            if (args[1].headers) {
                                if (args[1].headers instanceof Headers) {
                                    args[1].headers.forEach((v, k) => { reqHeaders[k] = v; });
                                } else if (typeof args[1].headers === 'object') {
                                    reqHeaders = args[1].headers;
                                }
                            }
                            if (args[1].body) {
                                reqBody = String(args[1].body).substring(0, 65536);
                            }
                        }
                    } catch(e) {}

                    try {
                        const response = await origFetch.apply(this, args);
                        const duration = Date.now() - startTime;
                        const clone = response.clone();
                        let respBody = '';
                        let respHeaders = {};
                        try {
                            clone.headers.forEach((v, k) => { respHeaders[k] = v; });
                            const text = await clone.text();
                            respBody = text.substring(0, 65536);
                        } catch(e) {}

                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.godModeDevToolsNetwork) {
                            window.webkit.messageHandlers.godModeDevToolsNetwork.postMessage({
                                method: method,
                                url: url,
                                statusCode: response.status,
                                requestHeaders: reqHeaders,
                                requestBody: reqBody,
                                responseHeaders: respHeaders,
                                responseBody: respBody,
                                durationMs: duration
                            });
                        }
                        return response;
                    } catch(err) {
                        const duration = Date.now() - startTime;
                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.godModeDevToolsNetwork) {
                            window.webkit.messageHandlers.godModeDevToolsNetwork.postMessage({
                                method: method,
                                url: url,
                                statusCode: 0,
                                requestHeaders: reqHeaders,
                                requestBody: reqBody,
                                responseHeaders: {},
                                responseBody: String(err),
                                durationMs: duration
                            });
                        }
                        throw err;
                    }
                };
            }

            const origXOpen = XMLHttpRequest.prototype.open;
            const origXSend = XMLHttpRequest.prototype.send;
            const origXSetHeader = XMLHttpRequest.prototype.setRequestHeader;

            XMLHttpRequest.prototype.open = function(method, url) {
                this.__gmMethod = method;
                this.__gmUrl = url;
                this.__gmReqHeaders = {};
                this.__gmStartTime = Date.now();
                return origXOpen.apply(this, arguments);
            };

            XMLHttpRequest.prototype.setRequestHeader = function(header, value) {
                if (this.__gmReqHeaders) {
                    this.__gmReqHeaders[header] = value;
                }
                return origXSetHeader.apply(this, arguments);
            };

            XMLHttpRequest.prototype.send = function(body) {
                if (body) {
                    this.__gmReqBody = String(body).substring(0, 65536);
                }
                this.addEventListener('loadend', () => {
                    try {
                        const duration = Date.now() - (this.__gmStartTime || Date.now());
                        let respHeaders = {};
                        try {
                            const rawHeaders = this.getAllResponseHeaders();
                            if (rawHeaders) {
                                rawHeaders.trim().split(/[\\r\\n]+/).forEach(line => {
                                    const parts = line.split(': ');
                                    const key = parts.shift();
                                    const val = parts.join(': ');
                                    if (key) respHeaders[key] = val;
                                });
                            }
                        } catch(e) {}

                        let respBody = '';
                        try {
                            respBody = (this.responseText || '').substring(0, 65536);
                        } catch(e) {}

                        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.godModeDevToolsNetwork) {
                            window.webkit.messageHandlers.godModeDevToolsNetwork.postMessage({
                                method: this.__gmMethod || 'GET',
                                url: this.__gmUrl || '',
                                statusCode: this.status || 0,
                                requestHeaders: this.__gmReqHeaders || {},
                                requestBody: this.__gmReqBody || '',
                                responseHeaders: respHeaders,
                                responseBody: respBody,
                                durationMs: duration
                            });
                        }
                    } catch(e) {}
                });
                return origXSend.apply(this, arguments);
            };

            window.__godModeGetStorageData = function() {
                try {
                    const local = {};
                    for (let i = 0; i < localStorage.length; i++) {
                        const k = localStorage.key(i);
                        if (k) local[k] = localStorage.getItem(k);
                    }
                    const session = {};
                    for (let i = 0; i < sessionStorage.length; i++) {
                        const k = sessionStorage.key(i);
                        if (k) session[k] = sessionStorage.getItem(k);
                    }
                    return JSON.stringify({
                        localStorage: local,
                        sessionStorage: session,
                        cookie: document.cookie || ''
                    });
                } catch(e) {
                    return JSON.stringify({ error: String(e) });
                }
            };
        })();
        """

        return WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    public func handleConsoleMessage(_ message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let levelStr = dict["level"] as? String,
              let level = DevToolsLogLevel(rawValue: levelStr),
              let text = dict["message"] as? String else { return }

        let entry = DevToolsConsoleEntry(
            level: level,
            message: text,
            source: dict["source"] as? String,
            lineNumber: dict["lineNumber"] as? Int
        )
        addConsoleEntry(entry)
    }

    public func handleNetworkMessage(_ message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let method = dict["method"] as? String,
              let url = dict["url"] as? String,
              let status = dict["statusCode"] as? Int else { return }

        let reqHeaders = dict["requestHeaders"] as? [String: String] ?? [:]
        let reqBody = dict["requestBody"] as? String
        let respHeaders = dict["responseHeaders"] as? [String: String] ?? [:]
        let respBody = dict["responseBody"] as? String
        let duration = dict["durationMs"] as? Double ?? 0

        let entry = DevToolsNetworkEntry(
            method: method,
            url: url,
            statusCode: status,
            requestHeaders: reqHeaders,
            requestBody: reqBody,
            responseHeaders: respHeaders,
            responseBody: respBody,
            durationMs: duration
        )
        addNetworkEntry(entry)
    }
}

public final class DevToolsScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var engine: DevToolsEngine?

    public init(engine: DevToolsEngine) {
        self.engine = engine
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "godModeDevToolsConsole" {
            engine?.handleConsoleMessage(message)
        } else if message.name == "godModeDevToolsNetwork" {
            engine?.handleNetworkMessage(message)
        }
    }
}
