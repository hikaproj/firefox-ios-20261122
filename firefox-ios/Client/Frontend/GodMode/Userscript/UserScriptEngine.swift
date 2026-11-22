// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

public struct InstalledUserScript: Codable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var version: String
    public var matchPatterns: [String]
    public var runAt: String
    public var sourceCode: String
    public var isEnabled: Bool

    public init(id: String = UUID().uuidString,
                name: String,
                version: String = "1.0",
                matchPatterns: [String] = ["*"],
                runAt: String = "document-end",
                sourceCode: String,
                isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.version = version
        self.matchPatterns = matchPatterns
        self.runAt = runAt
        self.sourceCode = sourceCode
        self.isEnabled = isEnabled
    }
}

@MainActor
public final class UserScriptEngine {
    public static let shared = UserScriptEngine()

    private var scripts: [InstalledUserScript] = []
    private let storageKey = "GodModeInstalledUserScriptsKey"

    private init() {
        loadScripts()
    }

    public var allScripts: [InstalledUserScript] {
        return scripts
    }

    public func installScript(sourceCode: String) -> InstalledUserScript {
        let parsed = parseMetadata(from: sourceCode)
        scripts.append(parsed)
        saveScripts()
        return parsed
    }

    public func toggleScript(id: String, isEnabled: Bool) {
        if let idx = scripts.firstIndex(where: { $0.id == id }) {
            scripts[idx].isEnabled = isEnabled
            saveScripts()
        }
    }

    public func removeScript(id: String) {
        scripts.removeAll { $0.id == id }
        saveScripts()
    }

    public func injectScripts(into userContentController: WKUserContentController, for url: URL?) {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isUserscriptEngineEnabled else { return }

        for script in scripts where script.isEnabled {
            guard shouldRun(script: script, on: url) else { continue }

            let injectionTime: WKUserScriptInjectionTime = script.runAt == "document-start" ? .atDocumentStart : .atDocumentEnd
            let wkScript = WKUserScript(source: script.sourceCode, injectionTime: injectionTime, forMainFrameOnly: false)
            userContentController.addUserScript(wkScript)
        }
    }

    private func shouldRun(script: InstalledUserScript, on url: URL?) -> Bool {
        guard let urlString = url?.absoluteString else { return false }
        if script.matchPatterns.contains("*") || script.matchPatterns.contains("<all_urls>") {
            return true
        }

        for pattern in script.matchPatterns {
            let regexPattern = "^" + NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*") + "$"
            if let regex = try? NSRegularExpression(pattern: regexPattern, options: .caseInsensitive) {
                let range = NSRange(location: 0, length: urlString.utf16.count)
                if regex.firstMatch(in: urlString, options: [], range: range) != nil {
                    return true
                }
            }
        }
        return false
    }

    private func parseMetadata(from sourceCode: String) -> InstalledUserScript {
        var name = "Untitled Script"
        var version = "1.0"
        var matches: [String] = []
        var runAt = "document-end"

        let lines = sourceCode.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("// @name") {
                name = trimmed.replacingOccurrences(of: "// @name", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("// @version") {
                version = trimmed.replacingOccurrences(of: "// @version", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("// @match") {
                let match = trimmed.replacingOccurrences(of: "// @match", with: "").trimmingCharacters(in: .whitespaces)
                matches.append(match)
            } else if trimmed.hasPrefix("// @include") {
                let match = trimmed.replacingOccurrences(of: "// @include", with: "").trimmingCharacters(in: .whitespaces)
                matches.append(match)
            } else if trimmed.hasPrefix("// @run-at") {
                runAt = trimmed.replacingOccurrences(of: "// @run-at", with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        if matches.isEmpty {
            matches.append("<all_urls>")
        }

        return InstalledUserScript(
            name: name,
            version: version,
            matchPatterns: matches,
            runAt: runAt,
            sourceCode: sourceCode,
            isEnabled: true
        )
    }

    private func loadScripts() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([InstalledUserScript].self, from: data) {
            self.scripts = saved
        }
    }

    private func saveScripts() {
        if let encoded = try? JSONEncoder().encode(scripts) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
