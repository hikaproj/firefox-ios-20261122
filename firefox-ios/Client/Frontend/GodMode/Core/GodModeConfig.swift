// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import os.lock

public enum GodModePreset: String, Codable, CaseIterable, Sendable {
    case balanced
    case coexistence
    case ultraSurvival
    case custom

    public var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .coexistence: return "Spotify+Discord"
        case .ultraSurvival: return "Ultra-Survival"
        case .custom: return "Custom"
        }
    }
}

public struct GodModeState: Codable, Sendable, Equatable {
    public var isEnabled: Bool = true
    public var preset: GodModePreset = .coexistence
    public var isHUDVisible: Bool = true
    public var hudPositionX: Double = 16.0
    public var hudPositionY: Double = 90.0
    public var backgroundDietEnabled: Bool = true
    public var urlCacheMemoryLimitMB: Int = 2
    public var isCrashGuardEnabled: Bool = true
    public var crashQuarantineThreshold: Int = 2
    public var isSideloadResilienceEnabled: Bool = true
    public var autoPurgeOnMemoryPressure: Bool = true

    public var singleProcessPoolEnabled: Bool = true
    public var tabHibernationTimeoutSeconds: Int = 10
    public var maxActiveWebViews: Int = 2
    public var blockWebFonts: Bool = false
    public var blockImages: Bool = false
    public var lazyLoadImages: Bool = true
    public var disableCSSAnimations: Bool = true
    public var stripHeavyGPUCSS: Bool = true
    public var stripAutoplayVideo: Bool = true
    public var domPruningEnabled: Bool = true
    public var textOnlyModeEnabled: Bool = false
    public var retinaScaleLimit: Double = 1.5
    public var thermalThrottlingEnabled: Bool = true
    public var allowsContentJavaScript: Bool = true
    public var isAdBlockerEnabled: Bool = true
    public var isUserscriptEngineEnabled: Bool = true
    public var isBackgroundMediaPlaybackEnabled: Bool = true
    public var isForcedPiPEnabled: Bool = true
    public var isNetworkMITMEnabled: Bool = true
    public var timeWarpSpeed: Double = 1.0
    public var isAntiAntiDebugEnabled: Bool = true
    public var isAntiAdblockDefusalEnabled: Bool = true
    public var isProfileIsolationEnabled: Bool = true
    public var activeProfileId: UUID? = nil
    public var userAgentPreset: String = "default"
    public var isTrackingParameterStrippingEnabled: Bool = true
    public var isCanvasAudioNoiseEnabled: Bool = true
    public var isReferrerStrippingEnabled: Bool = true
    public var isDevToolsEnabled: Bool = true
    public var isWebSocketMonitorEnabled: Bool = true
    public var isLocalHTTPServerEnabled: Bool = false
    public var localHTTPServerPort: UInt16 = 8080
    public var isSmartDarkModeEnabled: Bool = false
    public var aiProvider: String = "gemini"
    public var aiAPIKey: String = ""
    public var isFloatingDPadVisible: Bool = false

    public static let `default` = GodModeState()
}

public final class GodModeConfig: @unchecked Sendable {
    public static let shared = GodModeConfig()
    public static let didChangeNotification = Notification.Name("GodModeConfigDidChange")

    private var lock = os_unfair_lock()
    private var internalState: GodModeState
    private let userDefaultsKey = "GodModeConfigStateKey"

    private init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(GodModeState.self, from: data) {
            self.internalState = saved
        } else {
            self.internalState = .default
        }
    }

    public var state: GodModeState {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return internalState
    }

    public func update(_ block: (inout GodModeState) -> Void) {
        os_unfair_lock_lock(&lock)
        block(&internalState)
        let stateCopy = internalState
        os_unfair_lock_unlock(&lock)

        if let encoded = try? JSONEncoder().encode(stateCopy) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }

        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    public func applyPreset(_ preset: GodModePreset) {
        update { state in
            state.preset = preset
            switch preset {
            case .balanced:
                state.backgroundDietEnabled = true
                state.urlCacheMemoryLimitMB = 4
                state.autoPurgeOnMemoryPressure = true
                state.crashQuarantineThreshold = 3
                state.singleProcessPoolEnabled = true
                state.tabHibernationTimeoutSeconds = 30
                state.maxActiveWebViews = 4
                state.blockWebFonts = false
                state.blockImages = false
                state.lazyLoadImages = true
                state.disableCSSAnimations = true
                state.stripHeavyGPUCSS = false
                state.stripAutoplayVideo = true
                state.domPruningEnabled = false
                state.textOnlyModeEnabled = false
                state.retinaScaleLimit = 0.0
                state.thermalThrottlingEnabled = true
                state.allowsContentJavaScript = true
                state.isAdBlockerEnabled = true
                state.isUserscriptEngineEnabled = true
                state.isBackgroundMediaPlaybackEnabled = true
                state.isForcedPiPEnabled = true
                state.isNetworkMITMEnabled = true
                state.timeWarpSpeed = 1.0
                state.isAntiAntiDebugEnabled = true
                state.isAntiAdblockDefusalEnabled = true
                state.isProfileIsolationEnabled = true
                state.isTrackingParameterStrippingEnabled = true
                state.isCanvasAudioNoiseEnabled = true
                state.isReferrerStrippingEnabled = true
            case .coexistence:
                state.backgroundDietEnabled = true
                state.urlCacheMemoryLimitMB = 2
                state.autoPurgeOnMemoryPressure = true
                state.crashQuarantineThreshold = 2
                state.singleProcessPoolEnabled = true
                state.tabHibernationTimeoutSeconds = 10
                state.maxActiveWebViews = 2
                state.blockWebFonts = false
                state.blockImages = false
                state.lazyLoadImages = true
                state.disableCSSAnimations = true
                state.stripHeavyGPUCSS = true
                state.stripAutoplayVideo = true
                state.domPruningEnabled = true
                state.textOnlyModeEnabled = false
                state.retinaScaleLimit = 1.5
                state.thermalThrottlingEnabled = true
                state.allowsContentJavaScript = true
                state.isAdBlockerEnabled = true
                state.isUserscriptEngineEnabled = true
                state.isBackgroundMediaPlaybackEnabled = true
                state.isForcedPiPEnabled = true
                state.isNetworkMITMEnabled = true
                state.timeWarpSpeed = 1.0
                state.isAntiAntiDebugEnabled = true
                state.isAntiAdblockDefusalEnabled = true
                state.isProfileIsolationEnabled = true
                state.isTrackingParameterStrippingEnabled = true
                state.isCanvasAudioNoiseEnabled = true
                state.isReferrerStrippingEnabled = true
            case .ultraSurvival:
                state.backgroundDietEnabled = true
                state.urlCacheMemoryLimitMB = 0
                state.autoPurgeOnMemoryPressure = true
                state.crashQuarantineThreshold = 1
                state.singleProcessPoolEnabled = true
                state.tabHibernationTimeoutSeconds = 0
                state.maxActiveWebViews = 1
                state.blockWebFonts = true
                state.blockImages = true
                state.lazyLoadImages = false
                state.disableCSSAnimations = true
                state.stripHeavyGPUCSS = true
                state.stripAutoplayVideo = true
                state.domPruningEnabled = true
                state.textOnlyModeEnabled = true
                state.retinaScaleLimit = 1.0
                state.thermalThrottlingEnabled = true
                state.allowsContentJavaScript = false
                state.isAdBlockerEnabled = true
                state.isUserscriptEngineEnabled = false
                state.isBackgroundMediaPlaybackEnabled = false
                state.isForcedPiPEnabled = false
                state.isNetworkMITMEnabled = false
                state.timeWarpSpeed = 1.0
                state.isAntiAntiDebugEnabled = true
                state.isAntiAdblockDefusalEnabled = true
                state.isProfileIsolationEnabled = true
                state.isTrackingParameterStrippingEnabled = true
                state.isCanvasAudioNoiseEnabled = true
                state.isReferrerStrippingEnabled = true
            case .custom:
                break
            }
        }
    }
}
