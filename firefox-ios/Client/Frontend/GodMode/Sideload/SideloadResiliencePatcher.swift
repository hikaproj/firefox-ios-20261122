// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import Security

public final class SideloadResiliencePatcher: Sendable {
    public static let shared = SideloadResiliencePatcher()

    private let fallbackDirectoryName = "SideloadShared"

    private init() {}

    public var isSideloadedEnvironment: Bool {
        let testIdentifier = "group.org.mozilla.ios.firefox"
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: testIdentifier)
        return container == nil
    }

    public func safeContainerURL(forSecurityApplicationGroupIdentifier identifier: String) -> URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return containerURL
        }

        let fileManager = FileManager.default
        let documentPaths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let baseDir = documentPaths.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let fallbackDir = baseDir.appendingPathComponent(fallbackDirectoryName).appendingPathComponent(identifier)

        if !fileManager.fileExists(atPath: fallbackDir.path) {
            try? fileManager.createDirectory(at: fallbackDir, withIntermediateDirectories: true, attributes: nil)
        }

        return fallbackDir
    }

    public func safeUserDefaults(suiteName: String?) -> UserDefaults {
        guard let suiteName = suiteName, !suiteName.isEmpty else {
            return .standard
        }

        if let suiteDefaults = UserDefaults(suiteName: suiteName) {
            return suiteDefaults
        }

        return .standard
    }

    public func performSafeKeychainQuery<T>(_ operation: () throws -> T, fallback: T) -> T {
        do {
            return try operation()
        } catch {
            return fallback
        }
    }
}
