// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

public struct ContentBlockerSubscription: Codable, Sendable {
    public let id: String
    public let name: String
    public let urlString: String
    public var isEnabled: Bool
}

@MainActor
public final class NativeContentBlockerEngine {
    public static let shared = NativeContentBlockerEngine()

    private let ruleStore = WKContentRuleListStore.default()
    private let defaultRuleListIdentifier = "org.mozilla.godmode.defaultBlockerList"
    private var compiledRuleList: WKContentRuleList?
    private var subscriptions: [ContentBlockerSubscription] = []

    private init() {
        compileBuiltInRules()
    }

    public var isCompiled: Bool {
        return compiledRuleList != nil
    }

    public func attachRules(to userContentController: WKUserContentController) {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isAdBlockerEnabled,
              let ruleList = compiledRuleList else { return }

        userContentController.add(ruleList)
    }

    private func compileBuiltInRules() {
        let rulesJSON = """
        [
            {
                "trigger": {
                    "url-filter": ".*(doubleclick\\\\.net|googlesyndication\\\\.com|adnxs\\\\.com|adservice\\\\.google\\\\.com|scorecardresearch\\\\.com|outbrain\\\\.com|taboola\\\\.com|criteo\\\\.net|popads\\\\.net).*"
                },
                "action": {
                    "type": "block"
                }
            },
            {
                "trigger": {
                    "url-filter": ".*",
                    "resource-type": ["image", "style-sheet", "script"],
                    "if-domain": ["*ads.*", "*analytics.*", "*tracker.*", "*telemetry.*"]
                },
                "action": {
                    "type": "block"
                }
            },
            {
                "trigger": {
                    "url-filter": ".*(coin-hive|cryptoloot|coinhive).*"
                },
                "action": {
                    "type": "block"
                }
            }
        ]
        """

        ruleStore.compileContentRuleList(
            forIdentifier: defaultRuleListIdentifier,
            encodedContentRuleList: rulesJSON
        ) { [weak self] ruleList, error in
            guard let self = self, let ruleList = ruleList else { return }
            self.compiledRuleList = ruleList
        }
    }

    public func compileCustomRules(identifier: String, jsonString: String, completion: @escaping @Sendable (Bool) -> Void) {
        ruleStore.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: jsonString
        ) { [weak self] ruleList, error in
            if let ruleList = ruleList {
                self?.compiledRuleList = ruleList
                completion(true)
            } else {
                completion(false)
            }
        }
    }
}
