// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit
import WebKit

@MainActor
public final class GodMode {
    public static let shared = GodMode()

    private init() {}

    public static func bootstrap() {
        _ = SideloadResiliencePatcher.shared
        _ = ThermalThrottler.shared
        _ = TabHibernationManager.shared
        _ = NativeContentBlockerEngine.shared
        MediaPlaybackPiPEngine.shared.configureAudioSession()
        BackgroundDietManager.shared.applyDiet()
        RAMJetsamMonitor.shared.start()
    }

    public static func configureConfiguration(_ configuration: WKWebViewConfiguration) {
        let state = GodModeConfig.shared.state
        guard state.isEnabled else { return }

        if state.singleProcessPoolEnabled {
            configuration.processPool = GodModeProcessPool.shared.processPool
        }

        let userContentController = configuration.userContentController
        for script in ExtremeLiteScriptEngine.shared.buildUserScripts(for: state) {
            userContentController.addUserScript(script)
        }

        for script in MediaPlaybackPiPEngine.shared.buildMediaScripts() {
            userContentController.addUserScript(script)
        }

        NativeContentBlockerEngine.shared.attachRules(to: userContentController)
        UserScriptEngine.shared.injectScripts(into: userContentController, for: nil)

        if let mitmScript = NetworkMITMEngine.shared.buildScript() {
            userContentController.addUserScript(mitmScript)
        }

        if let timeWarpScript = JSTimeWarpEngine.shared.buildScript() {
            userContentController.addUserScript(timeWarpScript)
        }

        if let antiDebugScript = AntiAntiDebugEngine.shared.buildScript() {
            userContentController.addUserScript(antiDebugScript)
        }

        if let antiAdblockScript = AntiAdblockDefusalEngine.shared.buildScript() {
            userContentController.addUserScript(antiAdblockScript)
        }

        if let antiFingerprintScript = AntiFingerprintingEngine.shared.buildScript() {
            userContentController.addUserScript(antiFingerprintScript)
        }

        if let devToolsScript = DevToolsEngine.shared.buildScript() {
            userContentController.addUserScript(devToolsScript)
            userContentController.add(DevToolsScriptMessageHandler(engine: DevToolsEngine.shared), name: "godModeDevToolsConsole")
            userContentController.add(DevToolsScriptMessageHandler(engine: DevToolsEngine.shared), name: "godModeDevToolsNetwork")
        }

        if let wsScript = WebSocketMonitorEngine.shared.buildScript() {
            userContentController.addUserScript(wsScript)
            userContentController.add(WebSocketScriptMessageHandler(engine: WebSocketMonitorEngine.shared), name: "godModeWebSocket")
        }

        if let darkModeScript = SmartDarkModeEngine.shared.buildSmartDarkModeScript() {
            userContentController.addUserScript(darkModeScript)
        }

        if let customCSSScript = SmartDarkModeEngine.shared.buildCustomCSSScript(for: nil) {
            userContentController.addUserScript(customCSSScript)
        }

        if let domAlertScript = DOMChangeAlertEngine.shared.buildScript(for: nil) {
            userContentController.addUserScript(domAlertScript)
            userContentController.add(DOMAlertScriptMessageHandler(engine: DOMChangeAlertEngine.shared), name: "godModeDOMAlert")
        }

        let prefs = configuration.defaultWebpagePreferences ?? WKWebpagePreferences()
        DynamicJSEngineKiller.shared.configure(preferences: prefs, for: nil)
        configuration.defaultWebpagePreferences = prefs
    }

    static func configureWebView(_ webView: WKWebView, for tab: Tab) {
        guard GodModeConfig.shared.state.isEnabled else { return }
        RetinaLimiter.shared.applyScale(to: webView)

        if let profileId = GodModeConfig.shared.state.activeProfileId,
           let profile = ProfileIsolationManager.shared.allProfiles.first(where: { $0.id == profileId }),
           let ua = profile.userAgentOverride {
            webView.customUserAgent = ua
        }
    }

    public static func cleanURL(_ url: URL) -> URL {
        return AntiFingerprintingEngine.shared.cleanURL(url)
    }

    static func didSelectTab(_ tab: Tab, in bvc: BrowserViewController) {
        VirtualTabManager.shared.didSelectTab(tab, in: bvc)
    }

    static func attachHUD(to bvc: BrowserViewController) {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isHUDVisible else { return }

        let hud = RAMJetsamHUDView()
        hud.bvc = bvc

        let state = GodModeConfig.shared.state
        hud.frame = CGRect(x: state.hudPositionX, y: state.hudPositionY, width: 220, height: 28)

        bvc.view.addSubview(hud)
    }

    static func presentDevTools(from bvc: BrowserViewController) {
        let devToolsVC = DevToolsViewController()
        devToolsVC.activeWebView = bvc.tabManager.selectedTab?.webView
        let nav = UINavigationController(rootViewController: devToolsVC)
        nav.modalPresentationStyle = .pageSheet
        bvc.present(nav, animated: true)
    }

    static func showDualView(in bvc: BrowserViewController, url: URL? = nil) {
        let dualVC = FloatingDualWebViewController()
        bvc.addChild(dualVC)
        bvc.view.addSubview(dualVC.view)
        dualVC.view.frame = bvc.view.bounds
        dualVC.didMove(toParent: bvc)
        if let targetURL = url ?? URL(string: "https://www.google.com") {
            dualVC.load(url: targetURL)
        }
    }

    static func attachFloatingDPad(to bvc: BrowserViewController) {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.isFloatingDPadVisible else { return }

        let dpad = FloatingDPadView(frame: CGRect(x: 20, y: 200, width: 48, height: 48))
        dpad.bvc = bvc
        bvc.view.addSubview(dpad)
    }

    static func presentSettings(from bvc: BrowserViewController) {
        let settingsVC = GodModeSettingsViewController()
        settingsVC.bvc = bvc
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .formSheet
        bvc.present(nav, animated: true)
    }

    static func handleMemoryPressure(windowManager: WindowManager) {
        guard GodModeConfig.shared.state.isEnabled,
              GodModeConfig.shared.state.autoPurgeOnMemoryPressure else { return }

        BackgroundDietManager.shared.purgeCaches()

        Task { @MainActor in
            for uuid in windowManager.allWindowUUIDs(includingReserved: false) {
                await windowManager.tabManager(for: uuid)?.offloadBackgroundWebViews()
            }
        }
    }
}
