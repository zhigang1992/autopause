import AppKit
import CoreAudio
import Foundation
import os

/// Watches input devices and (when the HAL provides it) client processes.
/// No input stream is opened, so macOS does not prompt for microphone access.
final class CoreAudioMicMonitor {
    private let log = Logger(subsystem: "app.reily.autopause", category: "mic")
    private let queue = DispatchQueue(label: "app.reily.autopause.mic")
    private let lock = NSLock()
    private var current = MicSnapshot.empty
    private var poll: DispatchSourceTimer?
    private var started = false

    private var systemListenersInstalled = false
    private var deviceListeners: Set<AudioObjectID> = []
    private var processListeners: Set<AudioObjectID> = []
    private lazy var listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] number, addresses in
        let copied = (0..<Int(number)).map { addresses[$0].mSelector }
        self?.queue.async {
            if copied.contains(kAudioHardwarePropertyServiceRestarted) {
                self?.systemListenersInstalled = false
                self?.deviceListeners = []
                self?.processListeners = []
                self?.installSystemListeners()
            }
            self?.refreshLocked()
        }
    }

    /// Called on the main queue.
    var onSnapshot: ((MicSnapshot) -> Void)?

    func start() {
        queue.sync {
            guard !started else { return }
            started = true
            installSystemListeners()
            refreshLocked()
            let timer = DispatchSource.makeTimerSource(queue: queue)
            // ~4.5 Hz safety net behind the property listeners.
            timer.schedule(deadline: .now() + 0.22, repeating: 0.22)
            timer.setEventHandler { [weak self] in
                self?.refreshLocked()
            }
            poll = timer
            timer.resume()
        }
    }

    func refreshNow() {
        queue.async { [weak self] in
            self?.refreshLocked()
        }
    }

    func snapshot() -> MicSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    private func installSystemListeners() {
        guard !systemListenersInstalled else { return }
        systemListenersInstalled = true
        let system = AudioObjectID(kAudioObjectSystemObject)
        addListener(system, CoreAudioProperty.address(kAudioHardwarePropertyDevices))
        addListener(system, CoreAudioProperty.address(kAudioHardwarePropertyProcessObjectList))
        addListener(system, CoreAudioProperty.address(kAudioHardwarePropertyServiceRestarted))
    }

    private func addListener(_ objectID: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        var address = address
        let status = AudioObjectAddPropertyListenerBlock(objectID, &address, queue, listenerBlock)
        if status != noErr {
            log.error("listener add failed: \(status) selector \(address.mSelector)")
        }
    }

    private func removeListener(_ objectID: AudioObjectID, _ address: AudioObjectPropertyAddress) {
        var address = address
        AudioObjectRemovePropertyListenerBlock(objectID, &address, queue, listenerBlock)
    }

    private func refreshLocked() {
        let devices = inputDevices()
        let processes = audioProcesses(deviceUIDByID: Dictionary(uniqueKeysWithValues: devices.map { ($0.objectID, $0.uid) }))
        let snapshot = MicSnapshot(
            processAPIAvailable: processes.available,
            processes: processes.list,
            devices: devices
        )
        syncDeviceListeners(devices)
        syncProcessListeners(processes.list)
        lock.lock()
        current = snapshot
        lock.unlock()
        let callback = onSnapshot
        DispatchQueue.main.async {
            callback?(snapshot)
        }
    }

    private func syncDeviceListeners(_ devices: [InputDevice]) {
        let ids = Set(devices.map(\.objectID))
        for id in deviceListeners.subtracting(ids) {
            removeListener(id, CoreAudioProperty.address(kAudioDevicePropertyDeviceIsRunningSomewhere))
        }
        for id in ids.subtracting(deviceListeners) {
            addListener(id, CoreAudioProperty.address(kAudioDevicePropertyDeviceIsRunningSomewhere))
        }
        deviceListeners = ids
    }

    private func syncProcessListeners(_ processes: [MicProcess]) {
        let ids = Set(processes.map(\.objectID))
        for id in processListeners.subtracting(ids) {
            removeListener(id, CoreAudioProperty.address(kAudioProcessPropertyIsRunningInput))
        }
        for id in ids.subtracting(processListeners) {
            addListener(id, CoreAudioProperty.address(kAudioProcessPropertyIsRunningInput))
        }
        processListeners = ids
    }

    private func inputDevices() -> [InputDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let ids = CoreAudioProperty.readObjectIDs(system, kAudioHardwarePropertyDevices) ?? []
        return ids.compactMap { id in
            guard CoreAudioProperty.inputChannelCount(id) > 0 else { return nil }
            let uid = CoreAudioProperty.readString(id, kAudioDevicePropertyDeviceUID) ?? "device-\(id)"
            let name = CoreAudioProperty.readString(id, kAudioObjectPropertyName) ?? uid
            let running = CoreAudioProperty.readUInt32(id, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
            return InputDevice(objectID: id, uid: uid, name: name, isRunning: running)
        }
    }

    private func audioProcesses(deviceUIDByID: [AudioObjectID: String]) -> (available: Bool, list: [MicProcess]) {
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard let ids = CoreAudioProperty.readObjectIDs(system, kAudioHardwarePropertyProcessObjectList) else {
            return (false, [])
        }
        let list = ids.compactMap { id -> MicProcess? in
            guard let pid = CoreAudioProperty.readPID(id) else { return nil }
            let bundleID = CoreAudioProperty.readString(id, kAudioProcessPropertyBundleID)
            let runningInput = CoreAudioProperty.readUInt32(id, kAudioProcessPropertyIsRunningInput) == 1
            let deviceIDs = CoreAudioProperty.readObjectIDs(
                id,
                kAudioProcessPropertyDevices,
                scope: kAudioObjectPropertyScopeInput
            ) ?? []
            let uids = deviceIDs.compactMap { deviceUIDByID[$0] }
            return MicProcess(
                objectID: id,
                pid: pid,
                bundleID: bundleID.flatMap { $0.isEmpty ? nil : $0 },
                name: displayName(pid: pid, bundleID: bundleID, processID: id),
                isRunningInput: runningInput,
                inputDeviceUIDs: uids
            )
        }
        return (true, list)
    }

    private func displayName(pid: pid_t, bundleID: String?, processID: AudioObjectID) -> String {
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName, !name.isEmpty {
            return name
        }
        if let name = CoreAudioProperty.readString(processID, kAudioObjectPropertyName), !name.isEmpty {
            return name
        }
        if let bundleID, let last = bundleID.split(separator: ".").last, !last.isEmpty {
            return String(last)
        }
        return "Process \(pid)"
    }
}
