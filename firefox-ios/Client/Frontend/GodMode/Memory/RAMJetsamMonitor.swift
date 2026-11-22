// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Darwin
import Foundation

public struct MemorySnapshot: Sendable, Equatable {
    public let footprintBytes: UInt64
    public let availableBytes: UInt64
    public let totalDeviceBytes: UInt64

    public var footprintMB: Double {
        return Double(footprintBytes) / (1024.0 * 1024.0)
    }

    public var availableMB: Double {
        return Double(availableBytes) / (1024.0 * 1024.0)
    }

    public var totalDeviceMB: Double {
        return Double(totalDeviceBytes) / (1024.0 * 1024.0)
    }

    public var isCritical: Bool {
        return availableMB < 60.0
    }

    public var isWarning: Bool {
        return availableMB < 120.0
    }
}

public final class RAMJetsamMonitor: @unchecked Sendable {
    public static let shared = RAMJetsamMonitor()
    public static let didUpdateMemoryNotification = Notification.Name("GodModeMemoryDidUpdateNotification")
    public static let memoryPressureNotification = Notification.Name("GodModeMemoryPressureNotification")

    private var pressureSource: DispatchSourceMemoryPressure?
    private var updateTimer: DispatchSourceTimer?
    private let monitorQueue = DispatchQueue(label: "org.mozilla.firefox.godmode.memoryMonitor", qos: .utility)
    private var isRunning: Bool = false

    private init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        setupPressureSource()
        startPolling()
    }

    public func stop() {
        isRunning = false
        updateTimer?.cancel()
        updateTimer = nil
        pressureSource?.cancel()
        pressureSource = nil
    }

    public func currentSnapshot() -> MemorySnapshot {
        let footprint = queryPhysicalFootprint()
        let available = os_proc_available_memory()
        let total = ProcessInfo.processInfo.physicalMemory

        return MemorySnapshot(
            footprintBytes: footprint,
            availableBytes: available,
            totalDeviceBytes: total
        )
    }

    private func queryPhysicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            return UInt64(info.phys_footprint)
        }
        return 0
    }

    private func setupPressureSource() {
        let source = DispatchSource.makeMemoryPressureSource(flags: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            let flags = source.data
            self?.handlePressureEvent(flags: flags)
        }
        source.resume()
        self.pressureSource = source
    }

    private func handlePressureEvent(flags: DispatchSource.MemoryPressureEvent) {
        BackgroundDietManager.shared.purgeCaches()

        NotificationCenter.default.post(
            name: Self.memoryPressureNotification,
            object: nil,
            userInfo: ["isCritical": flags.contains(.critical)]
        )
    }

    private func startPolling() {
        let timer = DispatchSource.makeTimerSource(queue: monitorQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1500))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            let snapshot = self.currentSnapshot()
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Self.didUpdateMemoryNotification,
                    object: nil,
                    userInfo: ["snapshot": snapshot]
                )
            }
        }
        timer.resume()
        self.updateTimer = timer
    }
}
