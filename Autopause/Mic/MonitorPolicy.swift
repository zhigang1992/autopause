import Foundation

struct ActivityDecision: Equatable {
    var active: Bool
    var sourceName: String?

    static let inactive = ActivityDecision(active: false, sourceName: nil)
}

/// Decides whether a monitored mic source is live.
///
/// Process-level `kAudioProcessPropertyIsRunningInput` is preferred. Some
/// aggregate and virtual devices report `DeviceIsRunningSomewhere` forever, so
/// a device-only signal is used only when the process list is unavailable.
enum MonitorPolicy {
    static func decide(
        snapshot: MicSnapshot,
        allDevices: Bool,
        deviceUIDs: Set<String>,
        anyApp: Bool,
        bundleIDs: Set<String>
    ) -> ActivityDecision {
        if snapshot.processAPIAvailable {
            return decideFromProcesses(
                snapshot,
                allDevices: allDevices,
                deviceUIDs: deviceUIDs,
                anyApp: anyApp,
                bundleIDs: bundleIDs
            )
        }
        return decideFromDevices(
            snapshot,
            allDevices: allDevices,
            deviceUIDs: deviceUIDs,
            anyApp: anyApp
        )
    }

    private static func decideFromProcesses(
        _ snapshot: MicSnapshot,
        allDevices: Bool,
        deviceUIDs: Set<String>,
        anyApp: Bool,
        bundleIDs: Set<String>
    ) -> ActivityDecision {
        let running = snapshot.processes.filter { process in
            guard process.isRunningInput else { return false }
            guard matchesApp(process, anyApp: anyApp, bundleIDs: bundleIDs) else { return false }
            return matchesDevice(process, snapshot: snapshot, allDevices: allDevices, deviceUIDs: deviceUIDs)
        }
        guard !running.isEmpty else { return .inactive }
        let name = running.prefix(3).map(\.name).joined(separator: ", ")
        return ActivityDecision(active: true, sourceName: name.isEmpty ? nil : name)
    }

    private static func matchesApp(_ process: MicProcess, anyApp: Bool, bundleIDs: Set<String>) -> Bool {
        if anyApp { return true }
        guard let bundleID = process.bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    private static func matchesDevice(
        _ process: MicProcess,
        snapshot: MicSnapshot,
        allDevices: Bool,
        deviceUIDs: Set<String>
    ) -> Bool {
        if allDevices { return true }
        if process.inputDeviceUIDs.isEmpty {
            // HAL gave us no per-process device. Count it only if a selected
            // device is actually running, so an always-idle selection stays idle.
            return snapshot.devices.contains { deviceUIDs.contains($0.uid) && $0.isRunning }
        }
        return process.inputDeviceUIDs.contains { deviceUIDs.contains($0) }
    }

    /// Without the process list we cannot know which app is using the mic.
    /// A specific app filter therefore matches nothing, rather than ducking
    /// every running device.
    private static func decideFromDevices(
        _ snapshot: MicSnapshot,
        allDevices: Bool,
        deviceUIDs: Set<String>,
        anyApp: Bool
    ) -> ActivityDecision {
        guard anyApp else { return .inactive }
        let running = snapshot.devices.filter { device in
            device.isRunning && (allDevices || deviceUIDs.contains(device.uid))
        }
        guard let first = running.first else { return .inactive }
        return ActivityDecision(active: true, sourceName: first.name)
    }
}
