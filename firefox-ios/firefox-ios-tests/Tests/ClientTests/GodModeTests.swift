// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import XCTest
import WebKit
@testable import Client

final class GodModeTests: XCTestCase {

    // MARK: - Phase 1: Core & Memory Tests

    func testGodModeConfigPresets() {
        let config = GodModeConfig.shared
        config.applyPreset(.balanced)
        XCTAssertEqual(config.state.preset, .balanced)
        XCTAssertEqual(config.state.tabHibernationTimeoutSeconds, 30)
        XCTAssertFalse(config.state.blockWebFonts)

        config.applyPreset(.coexistence)
        XCTAssertEqual(config.state.preset, .coexistence)
        XCTAssertEqual(config.state.retinaScaleLimit, 1.5)
        XCTAssertEqual(config.state.tabHibernationTimeoutSeconds, 10)

        config.applyPreset(.ultraSurvival)
        XCTAssertEqual(config.state.preset, .ultraSurvival)
        XCTAssertEqual(config.state.retinaScaleLimit, 1.0)
        XCTAssertTrue(config.state.blockImages)
        XCTAssertTrue(config.state.blockWebFonts)
    }

    func testCrashGuardManagerQuarantine() {
        let manager = CrashGuardManager.shared
        manager.resetQuarantines()
        let domain = "crashy-test-domain-\(UUID().uuidString).com"

        XCTAssertFalse(manager.isDomainQuarantined(domain))
        manager.recordCrash(for: domain)
        XCTAssertFalse(manager.isDomainQuarantined(domain))
        manager.recordCrash(for: domain)
        XCTAssertTrue(manager.isDomainQuarantined(domain))

        manager.resetQuarantines()
        XCTAssertFalse(manager.isDomainQuarantined(domain))
    }

    func testRAMJetsamMonitorMetrics() {
        let monitor = RAMJetsamMonitor.shared
        let metrics = monitor.sampleCurrentMemory()
        XCTAssertGreaterThan(metrics.usedFootprintBytes, 0)
        XCTAssertGreaterThan(metrics.usedFootprintMB, 0)
        XCTAssertFalse(metrics.formattedFootprint.isEmpty)
    }

    // MARK: - Phase 2: Extreme Lite & Scripting Tests

    func testExtremeLiteScriptEngineGeneratesScripts() {
        var state = GodModeState()
        state.blockWebFonts = true
        state.blockImages = true
        state.disableCSSAnimations = true
        state.stripHeavyGPUCSS = true
        state.stripAutoplayVideo = true
        state.domPruningEnabled = true

        let scripts = ExtremeLiteScriptEngine.shared.buildUserScripts(for: state)
        XCTAssertEqual(scripts.count, 6)
    }

    func testRetinaLimiterScaleClamping() {
        let limiter = RetinaLimiter.shared
        XCTAssertEqual(limiter.clampedScale(for: 1.0), 1.0)
        XCTAssertEqual(limiter.clampedScale(for: 1.5), 1.5)
        XCTAssertEqual(limiter.clampedScale(for: 0.0), UIScreen.main.scale)
    }

    // MARK: - Phase 3: Blocker & Userscript Tests

    func testUserScriptMetadataParser() {
        let scriptContent = """
        // ==UserScript==
        // @name         Test Script
        // @namespace    http://example.com/
        // @version      1.0
        // @description  A test script
        // @match        *://*.example.com/*
        // @run-at       document-start
        // ==/UserScript==
        console.log('Hello');
        """

        let parsed = UserScriptEngine.shared.parseMetadata(from: scriptContent)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.name, "Test Script")
        XCTAssertEqual(parsed?.version, "1.0")
        XCTAssertEqual(parsed?.matches.count, 1)
        XCTAssertEqual(parsed?.matches.first, "*://*.example.com/*")
    }

    func testUserScriptWildcardMatcher() {
        let pattern = "*://*.google.com/*"
        let matchingURL = URL(string: "https://news.google.com/search")!
        let nonMatchingURL = URL(string: "https://yahoo.com")!

        XCTAssertTrue(UserScriptEngine.shared.matchesURL(matchingURL, pattern: pattern))
        XCTAssertFalse(UserScriptEngine.shared.matchesURL(nonMatchingURL, pattern: pattern))
    }

    // MARK: - Phase 4: Network & Cheats Tests

    func testNetworkMITMEngineRuleManagement() {
        let engine = NetworkMITMEngine.shared
        let rule = MITMRule(
            name: "Mock API",
            urlPattern: "^https://api\\.example\\.com/v1/user",
            action: .mockResponse(statusCode: 200, responseBody: "{\"id\":\"mock\"}", headers: ["Content-Type": "application/json"])
        )

        engine.saveRule(rule)
        let all = engine.getAllRules()
        XCTAssertTrue(all.contains(where: { $0.id == rule.id }))

        engine.deleteRule(id: rule.id)
        let afterDelete = engine.getAllRules()
        XCTAssertFalse(afterDelete.contains(where: { $0.id == rule.id }))
    }

    func testJSTimeWarpSpeedClamping() {
        let engine = JSTimeWarpEngine.shared
        engine.currentSpeed = 2.5
        XCTAssertEqual(engine.currentSpeed, 2.5)

        engine.currentSpeed = 0.05
        XCTAssertEqual(engine.currentSpeed, 0.1)

        engine.currentSpeed = 100.0
        XCTAssertEqual(engine.currentSpeed, 50.0)
    }

    // MARK: - Phase 5: Privacy & Anti-Fingerprinting Tests

    func testAntiFingerprintingURLCleansing() {
        let engine = AntiFingerprintingEngine.shared
        let dirtyURL = URL(string: "https://example.com/product?item=123&utm_source=facebook&fbclid=abcdef&gclid=987654")!
        let cleanURL = engine.cleanURL(dirtyURL)

        XCTAssertTrue(cleanURL.absoluteString.contains("item=123"))
        XCTAssertFalse(cleanURL.absoluteString.contains("utm_source"))
        XCTAssertFalse(cleanURL.absoluteString.contains("fbclid"))
        XCTAssertFalse(cleanURL.absoluteString.contains("gclid"))
    }

    // MARK: - Phase 6: DevTools & WebSocket & HTTP Server Tests

    func testDevToolsRingBufferCappedAt100() {
        let engine = DevToolsEngine.shared
        engine.clearAll()

        for i in 1...150 {
            engine.addConsoleEntry(DevToolsConsoleEntry(level: .log, message: "Log \(i)"))
            engine.addNetworkEntry(DevToolsNetworkEntry(method: "GET", url: "https://example.com/\(i)", statusCode: 200))
        }

        XCTAssertEqual(engine.getConsoleEntries().count, 100)
        XCTAssertEqual(engine.getNetworkEntries().count, 100)
        XCTAssertEqual(engine.getConsoleEntries().last?.message, "Log 150")
    }

    func testDevToolsCurlCommandGeneration() {
        let entry = DevToolsNetworkEntry(
            method: "POST",
            url: "https://api.example.com/login",
            statusCode: 200,
            requestHeaders: ["Authorization": "Bearer 12345", "Content-Type": "application/json"],
            requestBody: "{\"user\":\"admin\"}"
        )

        let curl = entry.curlCommand
        XCTAssertTrue(curl.contains("curl"))
        XCTAssertTrue(curl.contains("-X POST"))
        XCTAssertTrue(curl.contains("https://api.example.com/login"))
        XCTAssertTrue(curl.contains("Authorization: Bearer 12345"))
        XCTAssertTrue(curl.contains("--data-raw '{\"user\":\"admin\"}'"))
    }

    func testWebSocketRingBufferCappedAt100() {
        let engine = WebSocketMonitorEngine.shared
        engine.clearFrames()

        for i in 1...150 {
            engine.addFrame(WebSocketFrameEntry(socketId: "ws_1", url: "wss://echo.websocket.org", direction: .incoming, payload: "Frame \(i)"))
        }

        XCTAssertEqual(engine.getFrames().count, 100)
    }

    // MARK: - Phase 7: AI & Dark Mode Tests

    func testSmartDarkModeScriptGeneration() {
        let script = SmartDarkModeEngine.shared.buildSmartDarkModeScript()
        XCTAssertNotNil(script)
        XCTAssertEqual(script?.injectionTime, .atDocumentStart)
    }

    func testDomainCustomCSSStore() {
        let engine = SmartDarkModeEngine.shared
        engine.setCustomCSS("body { background: black !important; }", for: "example.org")

        let css = engine.getCustomCSS(for: "example.org")
        XCTAssertEqual(css, "body { background: black !important; }")

        engine.removeCustomCSS(for: "example.org")
        XCTAssertNil(engine.getCustomCSS(for: "example.org"))
    }

    // MARK: - Phase 8: Automation & Knowledge DB Tests

    func testMacroScriptSerialization() {
        let engine = MacroEngine.shared
        let step1 = MacroStep(type: .scroll, coordinateX: 0, coordinateY: 500)
        let step2 = MacroStep(type: .wait, waitSeconds: 2.0)
        let script = MacroScript(name: "Test Automation", steps: [step1, step2], loopCount: 3)

        engine.saveScript(script)
        let retrieved = engine.getAllScripts().first(where: { $0.id == script.id })
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.steps.count, 2)
        XCTAssertEqual(retrieved?.loopCount, 3)

        engine.deleteScript(id: script.id)
        XCTAssertNil(engine.getAllScripts().first(where: { $0.id == script.id }))
    }

    func testOfflineKnowledgeDBIndexingAndSearch() {
        let db = OfflineKnowledgeDBEngine.shared
        db.clearDatabase()

        let title = "Firefox iOS GodMode"
        let url = "https://mozilla.org/godmode"
        let content = "The GodMode zero footprint edition runs on low memory devices without Jetsam termination."

        db.indexPage(title: title, url: url, content: content)

        let searchHits = db.search(query: "Jetsam")
        XCTAssertGreaterThanOrEqual(searchHits.count, 1)
        XCTAssertEqual(searchHits.first?.title, title)
        XCTAssertEqual(searchHits.first?.url, url)

        let noHits = db.search(query: "UnicornXYZ987")
        XCTAssertEqual(noHits.count, 0)
    }
}
