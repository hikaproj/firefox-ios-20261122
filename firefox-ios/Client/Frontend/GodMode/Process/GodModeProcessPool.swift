// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation
import WebKit

public final class GodModeProcessPool: @unchecked Sendable {
    public static let shared = GodModeProcessPool()

    public let processPool: WKProcessPool

    private init() {
        self.processPool = WKProcessPool()
    }
}
