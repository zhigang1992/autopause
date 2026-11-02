import AppKit
import Foundation
import ServiceManagement
import SwiftUI

/// Wires the mic monitor, the state machine, and the pause/mute backends.
final class AppModel: ObservableObject {
    let settings = SettingsStore()

    @Published private(set) var phase: DuckStateMachine.Phase = .idle
    @Published private(set) var statusLine = "Listening"
    @Published private(set) var menuIconIsDucking = false
    @Published private(set) var devices: [InputDevice] = []
    @Published private(set) var micApps: [RecentMicApp] = []
    @Published private(set) var processAPIAvailable = true
    @Published var loginItemError: String?

    private let mic = CoreAudioMicMonitor()
    private let ducker = OutputDucker()
    private let pause = PauseController()
    private var machine = DuckStateMachine()
    private var ticker: Timer?
    private var lastSnapshot = MicSnapshot.empty
    private var sourceName: String?
    private var appliedMode: DuckMode?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        settings.onChange = { [weak self] field in
            self?.handleSettings(field)
        }
        refreshLoginItemStatus()
        mic.onSnapshot = { [weak self] snapshot in
            self?.ingest(snapshot)
        }
        mic.start()
        lastSnapshot = mic.snapshot()
        devices = lastSnapshot.devices
        noteRunningApps(lastSnapshot)
        if settings.enabled {
            let decision = decision(for: lastSnapshot)
            sourceName = decision.sourceName
            perform(machine.launch(micActive: decision.active, now: now()))
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        publish()
    }

    func restoreOnQuit() {
        ticker?.invalidate()
        ticker = nil
        // Both backends no-op unless they are the ones currently ducked.
        pause.restore()
        ducker.restoreImmediately()
        machine.reset()
    }

    func refreshMic() {
        mic.refreshNow()
    }

    var showsDoubaoHint: Bool {
        micApps.contains { $0.bundleID == MicHints.doubaoBundleID }
    }

    func icon(for bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    func deviceBinding(_ uid: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                guard let self else { return false }
                return self.settings.monitorAllDevices || self.settings.monitoredDeviceUIDs.contains(uid)
            },
            set: { [weak self] on in
                guard let self, !self.settings.monitorAllDevices else { return }
                var uids = self.settings.monitoredDeviceUIDs
                if on {
                    if !uids.contains(uid) { uids.append(uid) }
                } else {
                    uids.removeAll { $0 == uid }
                }
                self.settings.monitoredDeviceUIDs = uids
            }
        )
    }

    func appBinding(_ bundleID: String) -> Binding<Bool> {
        Binding(
            get: { [weak self] in
                self?.settings.allowedBundleIDs.contains(bundleID) ?? false
            },
            set: { [weak self] on in
                guard let self else { return }
                var ids = self.settings.allowedBundleIDs
                if on {
                    if !ids.contains(bundleID) { ids.append(bundleID) }
                } else {
                    ids.removeAll { $0 == bundleID }
                }
                self.settings.allowedBundleIDs = ids
            }
        )
    }

    private func handleSettings(_ field: SettingsField) {
        switch field {
        case .enabled:
            if settings.enabled {
                let decision = decision(for: lastSnapshot)
                sourceName = decision.sourceName
                perform(machine.launch(micActive: decision.active, now: now()))
            } else {
                if machine.isDucked {
                    restoreApplied(fade: 0)
                }
                machine.reset()
                sourceName = nil
            }
        case .mode:
            guard machine.isDucked else { break }
            restoreApplied(fade: 0)
            apply(settings.mode)
        case .launchAtLogin:
            applyLaunchAtLogin()
        case .monitorAllDevices:
            if !settings.monitorAllDevices && settings.monitoredDeviceUIDs.isEmpty {
                settings.monitoredDeviceUIDs = devices.map(\.uid)
            }
            reevaluate()
        case .filters:
            reevaluate()
        case .passive, .recent:
            break
        }
        publish()
    }

    private func ingest(_ snapshot: MicSnapshot) {
        lastSnapshot = snapshot
        if devices != snapshot.devices {
            devices = snapshot.devices
        }
        if processAPIAvailable != snapshot.processAPIAvailable {
            processAPIAvailable = snapshot.processAPIAvailable
        }
        noteRunningApps(snapshot)
        guard settings.enabled else {
            publish()
            return
        }
        let decision = decision(for: snapshot)
        let effects: [DuckStateMachine.Effect]
        if decision.active {
            if let name = decision.sourceName {
                sourceName = name
            }
            effects = machine.micBecameActive(now: now(), config: machineConfig)
        } else {
            effects = machine.micBecameIdle(now: now(), config: machineConfig)
        }
        perform(effects)
    }

    private func tick() {
        guard settings.enabled else { return }
        let effects = machine.tick(now: now(), config: machineConfig)
        if !effects.isEmpty {
            perform(effects)
        } else if machine.isDucked, appliedMode == .pause {
            pause.pollManualResume()
        }
        publish()
    }

    private func reevaluate() {
        guard settings.enabled else { return }
        let decision = decision(for: lastSnapshot)
        let effects: [DuckStateMachine.Effect]
        if decision.active {
            sourceName = decision.sourceName ?? sourceName
            effects = machine.micBecameActive(now: now(), config: machineConfig)
        } else {
            effects = machine.micBecameIdle(now: now(), config: machineConfig)
        }
        perform(effects)
    }

    private func perform(_ effects: [DuckStateMachine.Effect]) {
        for effect in effects {
            switch effect {
            case .apply:
                apply(settings.mode)
            case .restore:
                restoreApplied(fade: settings.fadeDuration)
                sourceName = nil
            }
        }
        publish()
    }

    private func apply(_ mode: DuckMode) {
        appliedMode = mode
        switch mode {
        case .pause:
            ducker.restore(fade: 0)
            pause.apply()
        case .mute:
            pause.restore()
            ducker.duck(fade: settings.fadeDuration)
        }
    }

    private func restoreApplied(fade: TimeInterval) {
        let mode = appliedMode ?? settings.mode
        appliedMode = nil
        switch mode {
        case .pause:
            pause.restore()
        case .mute:
            ducker.restore(fade: fade)
        }
    }

    private func decision(for snapshot: MicSnapshot) -> ActivityDecision {
        MonitorPolicy.decide(
            snapshot: snapshot,
            allDevices: settings.monitorAllDevices,
            deviceUIDs: Set(settings.monitoredDeviceUIDs),
            anyApp: settings.anyApp,
            bundleIDs: Set(settings.allowedBundleIDs)
        )
    }

    private var machineConfig: DuckStateMachine.Config {
        DuckStateMachine.Config(grace: settings.gracePeriod, minimumActive: 0.15)
    }

    private func now() -> TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }

    private func noteRunningApps(_ snapshot: MicSnapshot) {
        var apps = settings.recentApps
        var changed = false
        for process in snapshot.processes where process.isRunningInput {
            guard let bundleID = process.bundleID else { continue }
            if let index = apps.firstIndex(where: { $0.bundleID == bundleID }) {
                if apps[index].name != process.name {
                    apps[index].name = process.name
                    changed = true
                }
            } else {
                apps.insert(RecentMicApp(bundleID: bundleID, name: process.name), at: 0)
                changed = true
            }
        }
        if apps.count > 12 {
            apps = Array(apps.prefix(12))
            changed = true
        }
        if changed {
            settings.recentApps = apps
        }
        if micApps != apps {
            micApps = apps
        }
    }

    private func publish() {
        let ducking = settings.enabled && machine.isDucked
        let line: String
        if !settings.enabled {
            line = "Off"
        } else if ducking {
            if let sourceName, !sourceName.isEmpty {
                line = "Ducking: \(sourceName)"
            } else {
                line = "Ducking"
            }
        } else {
            line = "Listening"
        }
        if menuIconIsDucking != ducking { menuIconIsDucking = ducking }
        if statusLine != line { statusLine = line }
        if phase != machine.phase { phase = machine.phase }
    }

    private func refreshLoginItemStatus() {
        let enabled = SMAppService.mainApp.status == .enabled
        if settings.launchAtLogin != enabled {
            settings.setLaunchAtLoginSilently(enabled)
        }
        if SMAppService.mainApp.status == .requiresApproval {
            loginItemError = "Approve Autopause in System Settings → General → Login Items."
        }
    }

    private func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if settings.launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
            loginItemError = service.status == .requiresApproval
                ? "Approve Autopause in System Settings → General → Login Items."
                : nil
        } catch {
            loginItemError = error.localizedDescription
            settings.setLaunchAtLoginSilently(service.status == .enabled)
        }
    }
}
