// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import UIKit

public final class BackgroundDietManager: @unchecked Sendable {
    public static let shared = BackgroundDietManager()

    private init() {
        setupLifecycleObservers()
    }

    public func applyDiet() {
        let config = GodModeConfig.shared.state
        guard config.isEnabled && config.backgroundDietEnabled else { return }

        let memoryLimitBytes = config.urlCacheMemoryLimitMB * 1024 * 1024
        let diskLimitBytes = 16 * 1024 * 1024

        URLCache.shared = URLCache(
            memoryCapacity: memoryLimitBytes,
            diskCapacity: diskLimitBytes,
            diskPath: "godmode_diet_cache"
        )
    }

    public func purgeCaches() {
        URLCache.shared.removeAllCachedResponses()
    }

    public var isBackgroundSuspensionActive: Bool {
        let config = GodModeConfig.shared.state
        return config.isEnabled && config.backgroundDietEnabled
    }

    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.purgeCaches()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.purgeCaches()
        }
    }
}
