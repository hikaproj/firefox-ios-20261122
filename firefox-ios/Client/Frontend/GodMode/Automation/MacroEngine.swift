// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit
import os.lock

public enum MacroStepType: String, Codable, Sendable {
    case clickSelector
    case clickCoordinates
    case typeText
    case scroll
    case wait
}

public struct MacroStep: Codable, Sendable, Identifiable {
    public let id: UUID
    public let type: MacroStepType
    public let targetSelector: String?
    public let coordinateX: Double?
    public let coordinateY: Double?
    public let textValue: String?
    public let waitSeconds: Double?

    public init(
        id: UUID = UUID(),
        type: MacroStepType,
        targetSelector: String? = nil,
        coordinateX: Double? = nil,
        coordinateY: Double? = nil,
        textValue: String? = nil,
        waitSeconds: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.targetSelector = targetSelector
        self.coordinateX = coordinateX
        self.coordinateY = coordinateY
        self.textValue = textValue
        self.waitSeconds = waitSeconds
    }
}

public struct MacroScript: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var steps: [MacroStep]
    public var loopCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        steps: [MacroStep] = [],
        loopCount: Int = 1
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.loopCount = loopCount
    }
}

public final class MacroEngine: @unchecked Sendable {
    public static let shared = MacroEngine()

    private var lock = os_unfair_lock()
    private var scripts: [MacroScript] = []
    private var isExecuting: Bool = false
    private let storageKey = "GodModeMacroScriptsKey"

    public static let didChangeExecutionStatusNotification = Notification.Name("GodModeMacroDidChangeExecutionStatus")

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([MacroScript].self, from: data) {
            self.scripts = saved
        }
    }

    public func getAllScripts() -> [MacroScript] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return scripts
    }

    public func saveScript(_ script: MacroScript) {
        os_unfair_lock_lock(&lock)
        if let idx = scripts.firstIndex(where: { $0.id == script.id }) {
            scripts[idx] = script
        } else {
            scripts.append(script)
        }
        let copy = scripts
        os_unfair_lock_unlock(&lock)

        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public func deleteScript(id: UUID) {
        os_unfair_lock_lock(&lock)
        scripts.removeAll(where: { $0.id == id })
        let copy = scripts
        os_unfair_lock_unlock(&lock)

        if let data = try? JSONEncoder().encode(copy) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    public var isRunning: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return isExecuting
    }

    public func stopExecution() {
        os_unfair_lock_lock(&lock)
        isExecuting = false
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeExecutionStatusNotification, object: false)
        }
    }

    public func execute(script: MacroScript, in webView: WKWebView) {
        os_unfair_lock_lock(&lock)
        guard !isExecuting else {
            os_unfair_lock_unlock(&lock)
            return
        }
        isExecuting = true
        os_unfair_lock_unlock(&lock)

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeExecutionStatusNotification, object: true)
        }

        Task { [weak self, weak webView] in
            guard let self = self else { return }
            var iteration = 0
            let targetLoops = script.loopCount

            while self.isRunning && (targetLoops == 0 || iteration < targetLoops) {
                for step in script.steps {
                    guard self.isRunning, let wv = webView else { break }
                    await self.executeStep(step, in: wv)
                }
                iteration += 1
            }

            self.stopExecution()
        }
    }

    private func executeStep(_ step: MacroStep, in webView: WKWebView) async {
        switch step.type {
        case .clickSelector:
            if let selector = step.targetSelector {
                let escaped = selector.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function() {
                    var el = document.querySelector('\(escaped)');
                    if (el) {
                        el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                        el.click();
                        return true;
                    }
                    return false;
                })();
                """
                _ = try? await webView.evaluateJavaScript(js)
            }
        case .clickCoordinates:
            if let x = step.coordinateX, let y = step.coordinateY {
                let js = """
                (function() {
                    var el = document.elementFromPoint(\(x), \(y));
                    if (el) {
                        el.click();
                        return true;
                    }
                    return false;
                })();
                """
                _ = try? await webView.evaluateJavaScript(js)
            }
        case .typeText:
            if let selector = step.targetSelector, let text = step.textValue {
                let escapedSel = selector.replacingOccurrences(of: "'", with: "\\'")
                let escapedText = text.replacingOccurrences(of: "'", with: "\\'")
                let js = """
                (function() {
                    var el = document.querySelector('\(escapedSel)');
                    if (el) {
                        el.value = '\(escapedText)';
                        el.dispatchEvent(new Event('input', { bubbles: true }));
                        el.dispatchEvent(new Event('change', { bubbles: true }));
                        return true;
                    }
                    return false;
                })();
                """
                _ = try? await webView.evaluateJavaScript(js)
            }
        case .scroll:
            let x = step.coordinateX ?? 0
            let y = step.coordinateY ?? 300
            let js = "window.scrollBy({ left: \(x), top: \(y), behavior: 'smooth' });"
            _ = try? await webView.evaluateJavaScript(js)
        case .wait:
            let duration = step.waitSeconds ?? 1.0
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}
