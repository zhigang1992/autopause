import Foundation

enum SettingsField {
    case enabled
    case mode
    case launchAtLogin
    case monitorAllDevices
    case filters
    case passive
    case recent
}

struct RecentMicApp: Codable, Equatable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// Everything the spec asks to persist, in UserDefaults.
final class SettingsStore: ObservableObject {
    @Published var enabled: Bool { didSet { commit(.enabled) } }
    /// Always has at least one of Mute and Pause on. Write through
    /// `setMute` / `setPause`, which refuse to turn off the last one.
    @Published private(set) var modes: DuckModes { didSet { commit(.mode) } }
    @Published var fadeDuration: Double { didSet { commit(.passive) } }
    @Published var gracePeriod: Double { didSet { commit(.passive) } }
    @Published var monitorAllDevices: Bool { didSet { commit(.monitorAllDevices) } }
    @Published var monitoredDeviceUIDs: [String] { didSet { commit(.filters) } }
    @Published var anyApp: Bool { didSet { commit(.filters) } }
    @Published var allowedBundleIDs: [String] { didSet { commit(.filters) } }
    @Published var launchAtLogin: Bool { didSet { commit(.launchAtLogin) } }
    @Published var recentApps: [RecentMicApp] { didSet { commitRecent() } }

    var onChange: ((SettingsField) -> Void)?

    private let defaults: UserDefaults
    private var suppress = false

    private enum Key {
        static let enabled = "enabled"
        /// Up to 1.1.1 there was one `mode` string. Read once to migrate, and
        /// still written so a downgrade keeps the closest behaviour.
        static let legacyMode = "mode"
        static let muteEnabled = "muteEnabled"
        static let pauseEnabled = "pauseEnabled"
        static let fadeDuration = "fadeDuration"
        static let gracePeriod = "gracePeriod"
        static let monitorAllDevices = "monitorAllDevices"
        static let monitoredDeviceUIDs = "monitoredDeviceUIDs"
        static let anyApp = "anyApp"
        static let allowedBundleIDs = "allowedBundleIDs"
        static let launchAtLogin = "launchAtLogin"
        static let recentApps = "recentApps"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.fadeDuration: 0.3,
            Key.gracePeriod: 1.5,
            Key.monitorAllDevices: true,
            Key.anyApp: true,
            Key.launchAtLogin: false,
        ])
        enabled = defaults.object(forKey: Key.enabled) as? Bool ?? true
        modes = Self.loadModes(defaults)
        fadeDuration = min(1.5, max(0, defaults.double(forKey: Key.fadeDuration)))
        gracePeriod = min(5, max(0, defaults.double(forKey: Key.gracePeriod)))
        monitorAllDevices = defaults.object(forKey: Key.monitorAllDevices) as? Bool ?? true
        monitoredDeviceUIDs = defaults.stringArray(forKey: Key.monitoredDeviceUIDs) ?? []
        anyApp = defaults.object(forKey: Key.anyApp) as? Bool ?? true
        allowedBundleIDs = defaults.stringArray(forKey: Key.allowedBundleIDs) ?? []
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        if let data = defaults.data(forKey: Key.recentApps),
           let decoded = try? JSONDecoder().decode([RecentMicApp].self, from: data) {
            recentApps = decoded
        } else {
            recentApps = []
        }
    }

    func setMute(_ on: Bool) {
        let next = modes.setting(mute: on)
        if next != modes { modes = next }
    }

    func setPause(_ on: Bool) {
        let next = modes.setting(pause: on)
        if next != modes { modes = next }
    }

    private static func loadModes(_ defaults: UserDefaults) -> DuckModes {
        let mute = defaults.object(forKey: Key.muteEnabled) as? Bool
        let pause = defaults.object(forKey: Key.pauseEnabled) as? Bool
        if let mute, let pause, mute || pause {
            return DuckModes(mute: mute, pause: pause)
        }
        // First launch after upgrade (or a fresh install): keep what the old
        // single `mode` did, and save it in the new keys.
        let migrated = DuckModes.migrating(legacyMode: defaults.string(forKey: Key.legacyMode))
        defaults.set(migrated.mute, forKey: Key.muteEnabled)
        defaults.set(migrated.pause, forKey: Key.pauseEnabled)
        return migrated
    }

    /// Reflect the real login-item status without registering or unregistering.
    func setLaunchAtLoginSilently(_ value: Bool) {
        suppress = true
        launchAtLogin = value
        defaults.set(value, forKey: Key.launchAtLogin)
        suppress = false
    }

    private func commit(_ field: SettingsField) {
        guard !suppress else { return }
        switch field {
        case .enabled:
            defaults.set(enabled, forKey: Key.enabled)
        case .mode:
            defaults.set(modes.mute, forKey: Key.muteEnabled)
            defaults.set(modes.pause, forKey: Key.pauseEnabled)
            defaults.set(modes.pause ? "pause" : "mute", forKey: Key.legacyMode)
        case .launchAtLogin:
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        case .monitorAllDevices:
            defaults.set(monitorAllDevices, forKey: Key.monitorAllDevices)
        case .filters, .passive:
            defaults.set(min(1.5, max(0, fadeDuration)), forKey: Key.fadeDuration)
            defaults.set(min(5, max(0, gracePeriod)), forKey: Key.gracePeriod)
            defaults.set(monitoredDeviceUIDs, forKey: Key.monitoredDeviceUIDs)
            defaults.set(anyApp, forKey: Key.anyApp)
            defaults.set(allowedBundleIDs, forKey: Key.allowedBundleIDs)
        case .recent:
            break
        }
        onChange?(field)
    }

    private func commitRecent() {
        guard !suppress else { return }
        if let data = try? JSONEncoder().encode(recentApps) {
            defaults.set(data, forKey: Key.recentApps)
        }
        onChange?(.recent)
    }
}
