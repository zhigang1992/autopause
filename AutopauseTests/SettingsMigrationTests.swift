import XCTest

final class SettingsMigrationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "autopause.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testMuteUserStaysOnMute() {
        defaults.set("mute", forKey: "mode")
        XCTAssertEqual(SettingsStore(defaults: defaults).modes, .muteOnly)
        XCTAssertEqual(defaults.object(forKey: "muteEnabled") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "pauseEnabled") as? Bool, false)
    }

    func testPauseUserStaysOnPause() {
        defaults.set("pause", forKey: "mode")
        XCTAssertEqual(SettingsStore(defaults: defaults).modes, .pauseOnly)
    }

    func testFreshInstallDefaultsToPause() {
        XCTAssertEqual(SettingsStore(defaults: defaults).modes, .pauseOnly)
    }

    func testCombinedSettingPersistsAcrossLaunches() {
        defaults.set("mute", forKey: "mode")
        let store = SettingsStore(defaults: defaults)
        store.setPause(true)
        XCTAssertEqual(store.modes, .both)
        XCTAssertEqual(SettingsStore(defaults: defaults).modes, .both)
    }

    func testLastModeCannotBeTurnedOff() {
        let store = SettingsStore(defaults: defaults)
        var changes = 0
        store.onChange = { if case .mode = $0 { changes += 1 } }
        store.setPause(false)
        XCTAssertEqual(store.modes, .pauseOnly)
        XCTAssertEqual(changes, 0)
    }

    func testBothOffOnDiskFallsBackToTheLegacyMode() {
        defaults.set("mute", forKey: "mode")
        defaults.set(false, forKey: "muteEnabled")
        defaults.set(false, forKey: "pauseEnabled")
        XCTAssertEqual(SettingsStore(defaults: defaults).modes, .muteOnly)
    }

    func testLegacyKeyTracksForDowngrade() {
        let store = SettingsStore(defaults: defaults)
        store.setMute(true)
        store.setPause(false)
        XCTAssertEqual(defaults.string(forKey: "mode"), "mute")
    }
}
