// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit
import os.lock

public enum WebSocketFrameDirection: String, Codable, Sendable {
    case incoming
    case outgoing
    case open
    case close
    case error
}

public struct WebSocketFrameEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let socketId: String
    public let url: String
    public let direction: WebSocketFrameDirection
    public let timestamp: Date
    public let payload: String

    public init(
        id: UUID = UUID(),
        socketId: String,
        url: String,
        direction: WebSocketFrameDirection,
        timestamp: Date = Date(),
        payload: String
    ) {
        self.id = id
        self.socketId = socketId
        self.url = url
        self.direction = direction
        self.timestamp = timestamp
        self.payload = String(payload.prefix(65536))
    }
}

public final class WebSocketMonitorEngine: @unchecked Sendable {
    public static let shared = WebSocketMonitorEngine()

    private var lock = os_unfair_lock()
    private var ringBuffer: [WebSocketFrameEntry] = []
    private let maxEntries: Int = 100

    public static let didUpdateFramesNotification = Notification.Name("GodModeWebSocketDidUpdateFrames")

    private init() {}

    public func addFrame(_ frame: WebSocketFrameEntry) {
        os_unfair_lock_lock(&lock)
        if ringBuffer.count >= maxEntries {
            ringBuffer.removeFirst()
        }
        ringBuffer.append(frame)
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didUpdateFramesNotification, object: frame)
        }
    }

    public func getFrames() -> [WebSocketFrameEntry] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return ringBuffer
    }

    public func clearFrames() {
        os_unfair_lock_lock(&lock)
        ringBuffer.removeAll()
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didUpdateFramesNotification, object: nil)
        }
    }

    public func buildScript() -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isWebSocketMonitorEnabled else { return nil }

        let js = """
        (function() {
            if (window.__godModeWSInjected) return;
            window.__godModeWSInjected = true;
            window.__godModeSockets = window.__godModeSockets || {};
            let socketCounter = 0;

            const OrigWebSocket = window.WebSocket;
            if (OrigWebSocket) {
                window.WebSocket = function(url, protocols) {
                    const ws = protocols ? new OrigWebSocket(url, protocols) : new OrigWebSocket(url);
                    const socketId = 'ws_' + (++socketCounter) + '_' + Math.random().toString(36).substring(2, 7);
                    window.__godModeSockets[socketId] = ws;

                    function notify(direction, payload) {
                        try {
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.godModeWebSocket) {
                                window.webkit.messageHandlers.godModeWebSocket.postMessage({
                                    socketId: socketId,
                                    url: String(url),
                                    direction: direction,
                                    payload: String(payload || '').substring(0, 65536)
                                });
                            }
                        } catch(e) {}
                    }

                    notify('open', 'Connection initiating: ' + url);

                    const origSend = ws.send;
                    ws.send = function(data) {
                        notify('outgoing', typeof data === 'string' ? data : '[Binary ' + (data.byteLength || data.size || 0) + ' bytes]');
                        return origSend.apply(this, arguments);
                    };

                    ws.addEventListener('message', function(event) {
                        notify('incoming', typeof event.data === 'string' ? event.data : '[Binary ' + (event.data.byteLength || event.data.size || 0) + ' bytes]');
                    });

                    ws.addEventListener('close', function(event) {
                        notify('close', 'Code: ' + event.code + ', Reason: ' + event.reason);
                        delete window.__godModeSockets[socketId];
                    });

                    ws.addEventListener('error', function(event) {
                        notify('error', 'WebSocket Error');
                    });

                    return ws;
                };
                window.WebSocket.prototype = OrigWebSocket.prototype;
            }

            const OrigEventSource = window.EventSource;
            if (OrigEventSource) {
                window.EventSource = function(url, config) {
                    const es = config ? new OrigEventSource(url, config) : new OrigEventSource(url);
                    const socketId = 'sse_' + (++socketCounter) + '_' + Math.random().toString(36).substring(2, 7);

                    function notify(direction, payload) {
                        try {
                            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.godModeWebSocket) {
                                window.webkit.messageHandlers.godModeWebSocket.postMessage({
                                    socketId: socketId,
                                    url: String(url),
                                    direction: direction,
                                    payload: String(payload || '').substring(0, 65536)
                                });
                            }
                        } catch(e) {}
                    }

                    notify('open', 'SSE Connection initiating: ' + url);

                    es.addEventListener('message', function(event) {
                        notify('incoming', String(event.data || ''));
                    });

                    es.addEventListener('error', function() {
                        notify('error', 'SSE Error');
                    });

                    return es;
                };
                window.EventSource.prototype = OrigEventSource.prototype;
            }

            window.__godModeInjectWebSocketFrame = function(socketId, payload) {
                const s = window.__godModeSockets[socketId];
                if (s && s.readyState === 1) {
                    s.send(payload);
                    return true;
                }
                return false;
            };
        })();
        """

        return WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    public func handleMessage(_ message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let socketId = dict["socketId"] as? String,
              let url = dict["url"] as? String,
              let directionStr = dict["direction"] as? String,
              let direction = WebSocketFrameDirection(rawValue: directionStr) else { return }

        let payload = dict["payload"] as? String ?? ""
        let frame = WebSocketFrameEntry(
            socketId: socketId,
            url: url,
            direction: direction,
            payload: payload
        )
        addFrame(frame)
    }

    public func sendFrame(socketId: String, payload: String, in webView: WKWebView?, completion: ((Bool) -> Void)? = nil) {
        guard let webView = webView else {
            completion?(false)
            return
        }

        let escapedSocketId = socketId.replacingOccurrences(of: "'", with: "\\'")
        let escapedPayload = payload
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")

        let js = "window.__godModeInjectWebSocketFrame('\(escapedSocketId)', '\(escapedPayload)');"
        webView.evaluateJavaScript(js) { result, _ in
            let success = (result as? Bool) ?? false
            completion?(success)
        }
    }
}

public final class WebSocketScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var engine: WebSocketMonitorEngine?

    public init(engine: WebSocketMonitorEngine) {
        self.engine = engine
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "godModeWebSocket" {
            engine?.handleMessage(message)
        }
    }
}
