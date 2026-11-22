// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Network
import WebKit

public struct GodModeProxyConfig: Codable, Sendable {
    public var host: String
    public var port: UInt16
    public var isSOCKS5: Bool
    public var isEnabled: Bool

    public init(host: String, port: UInt16, isSOCKS5: Bool = false, isEnabled: Bool = true) {
        self.host = host
        self.port = port
        self.isSOCKS5 = isSOCKS5
        self.isEnabled = isEnabled
    }
}

public struct GodModeProfile: Codable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var userAgentOverride: String?
    public var proxyConfig: GodModeProxyConfig?
    public var createdAt: Date

    public init(id: UUID = UUID(),
                name: String,
                userAgentOverride: String? = nil,
                proxyConfig: GodModeProxyConfig? = nil,
                createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.userAgentOverride = userAgentOverride
        self.proxyConfig = proxyConfig
        self.createdAt = createdAt
    }
}

@MainActor
public final class ProfileIsolationManager {
    public static let shared = ProfileIsolationManager()

    public static let desktopMacUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
    public static let windowsChromeUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    public static let androidFirefoxUserAgent = "Mozilla/5.0 (Android 14; Mobile; rv:125.0) Gecko/125.0 Firefox/125.0"

    private var profiles: [GodModeProfile] = []
    private let storageKey = "GodModeProfilesKey"

    private init() {
        loadProfiles()
    }

    public var allProfiles: [GodModeProfile] {
        return profiles
    }

    public func createProfile(name: String, userAgent: String? = nil, proxy: GodModeProxyConfig? = nil) -> GodModeProfile {
        let profile = GodModeProfile(name: name, userAgentOverride: userAgent, proxyConfig: proxy)
        profiles.append(profile)
        saveProfiles()
        return profile
    }

    public func removeProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        saveProfiles()
    }

    public func dataStore(for profile: GodModeProfile) -> WKWebsiteDataStore {
        if #available(iOS 17.0, *) {
            let store = WKWebsiteDataStore(forIdentifier: profile.id)
            applyProxy(profile.proxyConfig, to: store)
            return store
        } else {
            return .default()
        }
    }

    public func applyProxy(_ proxy: GodModeProxyConfig?, to store: WKWebsiteDataStore) {
        guard let proxy = proxy, proxy.isEnabled, #available(iOS 17.0, *) else { return }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: NWEndpoint.Port(rawValue: proxy.port)!)
        let config: ProxyConfiguration
        if proxy.isSOCKS5 {
            config = ProxyConfiguration(socksv5Proxy: endpoint)
        } else {
            config = ProxyConfiguration(httpCONNECTProxy: endpoint)
        }
        store.proxyConfigurations = [config]
    }

    private func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([GodModeProfile].self, from: data) {
            self.profiles = saved
        }
    }

    private func saveProfiles() {
        if let encoded = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }
}
