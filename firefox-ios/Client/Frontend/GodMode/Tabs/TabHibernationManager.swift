// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import CoreGraphics
import Foundation
import ImageIO
import UIKit

@MainActor
public final class TabHibernationManager {
    public static let shared = TabHibernationManager()

    private var checkTimer: Timer?
    private var lastActiveTime: [String: Date] = [:]

    private init() {
        startTimer()
    }

    public func markTabActive(_ tab: Tab) {
        lastActiveTime[tab.tabUUID] = Date()
    }

    public func startTimer() {
        checkTimer?.invalidate()
        checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkInactiveTabs()
        }
    }

    public func checkInactiveTabs() {
        let config = GodModeConfig.shared.state
        guard config.isEnabled, config.tabHibernationTimeoutSeconds >= 0 else { return }

        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              let bvc = window.rootViewController as? BrowserViewController else {
            return
        }

        let currentTab = bvc.tabManager.selectedTab
        let now = Date()
        let timeout = TimeInterval(config.tabHibernationTimeoutSeconds)

        for tab in bvc.tabManager.tabs {
            guard tab !== currentTab, tab.webView != nil else { continue }

            let lastActive = lastActiveTime[tab.tabUUID] ?? .distantPast
            if now.timeIntervalSince(lastActive) >= timeout {
                hibernateTab(tab)
            }
        }
    }

    public func hibernateTab(_ tab: Tab) {
        guard tab.webView != nil else { return }

        if let screenshot = tab.screenshot {
            tab.screenshot = downsampleImage(screenshot, maxPixelSize: 180)
        }

        Task { @MainActor [weak tab] in
            await tab?.offloadWebView()
        }
    }

    public func downsampleImage(_ image: UIImage, maxPixelSize: Int = 180) -> UIImage? {
        guard let data = image.jpegData(compressionQuality: 0.5),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
