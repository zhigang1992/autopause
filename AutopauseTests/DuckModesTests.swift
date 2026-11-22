import XCTest

final class DuckModesTests: XCTestCase {
    func testLegacyModeMigratesToTheSameBehaviour() {
        XCTAssertEqual(DuckModes.migrating(legacyMode: "mute"), .muteOnly)
        XCTAssertEqual(DuckModes.migrating(legacyMode: "pause"), .pauseOnly)
    }

    func testMissingOrUnknownLegacyModeFallsBackToPause() {
        XCTAssertEqual(DuckModes.migrating(legacyMode: nil), .pauseOnly)
        XCTAssertEqual(DuckModes.migrating(legacyMode: "bogus"), .pauseOnly)
    }

    func testBothModesCanBeOn() {
        XCTAssertEqual(DuckModes.pauseOnly.setting(mute: true), .both)
        XCTAssertEqual(DuckModes.muteOnly.setting(pause: true), .both)
    }

    func testTurningOffTheLastModeIsRefused() {
        XCTAssertEqual(DuckModes.pauseOnly.setting(pause: false), .pauseOnly)
        XCTAssertEqual(DuckModes.muteOnly.setting(mute: false), .muteOnly)
        XCTAssertEqual(DuckModes.both.setting(mute: false, pause: false), .both)
    }

    func testEitherModeCanBeTurnedOffWhenBothAreOn() {
        XCTAssertEqual(DuckModes.both.setting(mute: false), .pauseOnly)
        XCTAssertEqual(DuckModes.both.setting(pause: false), .muteOnly)
    }

    func testLastOnLocksOnlyTheSoleMode() {
        XCTAssertTrue(DuckModes.pauseOnly.isLastOn(mute: false))
        XCTAssertFalse(DuckModes.pauseOnly.isLastOn(mute: true))
        XCTAssertTrue(DuckModes.muteOnly.isLastOn(mute: true))
        XCTAssertFalse(DuckModes.both.isLastOn(mute: true))
        XCTAssertFalse(DuckModes.both.isLastOn(mute: false))
    }

    func testSingleModesKeepTheirSteps() {
        XCTAssertEqual(DuckModes.pauseOnly.applySteps, [.pause])
        XCTAssertEqual(DuckModes.pauseOnly.restoreSteps, [.play])
        XCTAssertEqual(DuckModes.muteOnly.applySteps, [.fadeOut])
        XCTAssertEqual(DuckModes.muteOnly.restoreSteps, [.fadeIn])
    }

    func testCombinedFadesBeforePausingAndPlaysBeforeFadingIn() {
        XCTAssertEqual(DuckModes.both.applySteps, [.fadeOut, .pause])
        XCTAssertEqual(DuckModes.both.restoreSteps, [.play, .fadeIn])
    }
}
