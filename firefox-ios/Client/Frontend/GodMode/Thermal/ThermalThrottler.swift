// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

@MainActor
public final class ThermalThrottler {
    public static let shared = ThermalThrottler()

    private var currentFPS: Int = 60

    private init() {
        setupThermalObserver()
    }

    public var targetFPS: Int {
        let state = ProcessInfo.processInfo.thermalState
        switch state {
        case .nominal: return 60
        case .fair: return 30
        case .serious: return 15
        case .critical: return 15
        @unknown default: return 30
        }
    }

    private func setupThermalObserver() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyThermalState()
        }
    }

    private func applyThermalState() {
        guard GodModeConfig.shared.state.thermalThrottlingEnabled else { return }
        self.currentFPS = targetFPS
    }
}
