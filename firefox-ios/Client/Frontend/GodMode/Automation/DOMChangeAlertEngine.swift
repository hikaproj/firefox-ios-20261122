// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit
import UserNotifications
import os.lock

public struct DOMAlertRule: Codable, Sendable, Identifiable {
    public let id: UUID
    public var targetURLPattern: String
    public var keyword: String?
    public var cssSelector: String?
    public var autoReloadIntervalSeconds: Double?

    public init(
        id: UUID = UUID(),
        targetURLPattern: String = "*",
        keyword: String? = nil,
        cssSelector: String? = nil,
        autoReloadIntervalSeconds: Double? = nil
    ) {
        self.id = id
        self.targetURLPattern = targetURLPattern
        self.keyword = keyword
        self.cssSelector = cssSelector
        self.autoReloadIntervalSeconds = autoReloadIntervalSeconds
    }
}

public final class DOMChangeAlertEngine: @unchecked Sendable {
    public static let shared = DOMChangeAlertEngine()

    private var lock = os_unfair_lock()
    private var rules: [DOMAlertRule] = []
    private let storageKey = "GodModeDOMAlertRulesKey"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([DOMAlertRule].self, from: data) {
            self.rules = saved
        }
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    public func getAllRules() -> [DOMAlertRule] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return rules
    }

    public func saveRule(_ rule: DOMAlertRule) {
        os_unfair_lock_lock(&lock)
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else {
            rules.append(rule)
        }
        let copy = rules
        os_unfair_lock_unlock(&lock)

        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public func deleteRule(id: UUID) {
        os_unfair_lock_lock(&lock)
        rules.removeAll(where: { $0.id == id })
        let copy = rules
        os_unfair_lock_unlock(&lock)

        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public func buildScript(for url: URL?) -> WKUserScript? {
        guard GodModeConfig.shared.state.isEnabled else { return nil }

        os_unfair_lock_lock(&lock)
        let activeRules = rules
        os_unfair_lock_unlock(&lock)

        guard !activeRules.isEmpty else { return nil }

        let keywords = activeRules.compactMap { $0.keyword }.filter { !$0.isEmpty }
        let selectors = activeRules.compactMap { $0.cssSelector }.filter { !$0.isEmpty }
        let minReload = activeRules.compactMap { $0.autoReloadIntervalSeconds }.filter { $0 > 0 }.min()

        let keywordsJSON = (try? String(data: JSONSerialization.data(withJSONObject: keywords), encoding: .utf8)) ?? "[]"
        let selectorsJSON = (try? String(data: JSONSerialization.data(withJSONObject: selectors), encoding: .utf8)) ?? "[]"
        let reloadMs = (minReload ?? 0) * 1000

        let js = """
        (function() {
            if (window.__godModeDOMAlertInjected) return;
            window.__godModeDOMAlertInjected = true;

            const keywords = \(keywordsJSON);
            const selectors = \(selectorsJSON);
            const reloadIntervalMs = \(reloadMs);

            function checkTriggers() {
                const bodyText = document.body ? document.body.innerText : '';
                for (let i = 0; i < keywords.length; i++) {
                    const kw = keywords[i];
                    if (kw && bodyText.includes(kw)) {
                        notify('Keyword found: ' + kw);
                        return;
                    }
                }
                for (let i = 0; i < selectors.length; i++) {
                    const sel = selectors[i];
                    if (sel && document.querySelector(sel)) {
                        notify('Element detected: ' + sel);
                        return;
                    }
                }
            }

            function notify(message) {
                try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.godModeDOMAlert) {
                        window.webkit.messageHandlers.godModeDOMAlert.postMessage({ message: message, title: document.title, url: window.location.href });
                    }
                } catch(e) {}
            }

            if (keywords.length > 0 || selectors.length > 0) {
                window.addEventListener('DOMContentLoaded', checkTriggers);
                const observer = new MutationObserver(function() {
                    checkTriggers();
                });
                observer.observe(document.documentElement || document.body, { childList: true, subtree: true });
            }

            if (reloadIntervalMs > 2000) {
                setTimeout(function() {
                    window.location.reload();
                }, reloadIntervalMs);
            }
        })();
        """

        return WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    public func handleMessage(_ message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let text = dict["message"] as? String else { return }

        let pageTitle = dict["title"] as? String ?? "Page Alert"

        let content = UNMutableNotificationContent()
        content.title = "GodMode DOM Alert"
        content.subtitle = pageTitle
        content.body = text
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

public final class DOMAlertScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var engine: DOMChangeAlertEngine?

    public init(engine: DOMChangeAlertEngine) {
        self.engine = engine
        super.init()
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "godModeDOMAlert" {
            engine?.handleMessage(message)
        }
    }
}
