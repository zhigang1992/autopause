import XCTest

final class DuckStateMachineTests: XCTestCase {
    private let config = DuckStateMachine.Config(grace: 1.5, minimumActive: 0.15)

    func testStaysIdleUntilTheMinimumActiveWindowElapses() {
        var machine = DuckStateMachine()

        XCTAssertEqual(machine.micBecameActive(now: 10, config: config), [])
        XCTAssertEqual(machine.phase, .pending)
        XCTAssertEqual(machine.tick(now: 10.149, config: config), [])
        XCTAssertEqual(machine.phase, .pending)

        XCTAssertEqual(machine.tick(now: 10.15, config: config), [.apply])
        XCTAssertEqual(machine.phase, .active)
        XCTAssertEqual(machine.tick(now: 12, config: config), [])
        XCTAssertTrue(machine.isDucked)
    }

    func testBlipShorterThanTheMinimumNeverApplies() {
        var machine = DuckStateMachine()

        XCTAssertEqual(machine.micBecameActive(now: 1, config: config), [])
        XCTAssertEqual(machine.micBecameIdle(now: 1.10, config: config), [])
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.tick(now: 5, config: config), [])
        XCTAssertFalse(machine.isDucked)
    }

    func testGraceDelaysRestoreAndThenReturnsToIdle() {
        var machine = activated(at: 0)

        XCTAssertEqual(machine.micBecameIdle(now: 5, config: config), [])
        XCTAssertEqual(machine.phase, .grace)
        XCTAssertTrue(machine.isDucked)
        XCTAssertEqual(machine.tick(now: 6.49, config: config), [])
        XCTAssertEqual(machine.phase, .grace)

        XCTAssertEqual(machine.tick(now: 6.5, config: config), [.restore])
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.tick(now: 9, config: config), [])
    }

    func testReactivationDuringGraceDoesNotReapply() {
        var machine = activated(at: 0)

        XCTAssertEqual(machine.micBecameIdle(now: 2, config: config), [])
        XCTAssertEqual(machine.phase, .grace)

        XCTAssertEqual(machine.micBecameActive(now: 2.4, config: config), [])
        XCTAssertEqual(machine.phase, .active)
        XCTAssertEqual(machine.tick(now: 4, config: config), [])

        XCTAssertEqual(machine.micBecameIdle(now: 4, config: config), [])
        XCTAssertEqual(machine.phase, .grace)
        XCTAssertEqual(machine.tick(now: 5.5, config: config), [.restore])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testAlreadyActiveAtLaunchAppliesImmediately() {
        var machine = DuckStateMachine()

        XCTAssertEqual(machine.launch(micActive: true, now: 0), [.apply])
        XCTAssertEqual(machine.phase, .active)
        XCTAssertEqual(machine.tick(now: 0.01, config: config), [])
    }

    func testLaunchWithIdleMicDoesNotApply() {
        var machine = DuckStateMachine()

        XCTAssertEqual(machine.launch(micActive: false, now: 0), [])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testZeroGraceRestoresAsSoonAsTheMicGoesIdle() {
        var machine = DuckStateMachine()
        let immediate = DuckStateMachine.Config(grace: 0, minimumActive: 0.15)
        XCTAssertEqual(machine.launch(micActive: true, now: 0), [.apply])

        XCTAssertEqual(machine.micBecameIdle(now: 3, config: immediate), [.restore])
        XCTAssertEqual(machine.phase, .idle)
    }

    func testDuplicateActiveAndIdleEventsDoNotRepeatEffects() {
        var machine = activated(at: 0)

        XCTAssertEqual(machine.micBecameActive(now: 1, config: config), [])
        XCTAssertEqual(machine.micBecameIdle(now: 2, config: config), [])
        XCTAssertEqual(machine.micBecameIdle(now: 2.2, config: config), [])
        XCTAssertEqual(machine.phase, .grace)
    }

    func testRealActivationStillWorksAfterABlip() {
        var machine = DuckStateMachine()

        _ = machine.micBecameActive(now: 0, config: config)
        _ = machine.micBecameIdle(now: 0.05, config: config)
        XCTAssertEqual(machine.phase, .idle)

        XCTAssertEqual(machine.micBecameActive(now: 1, config: config), [])
        XCTAssertEqual(machine.tick(now: 1 + config.minimumActive, config: config), [.apply])
        XCTAssertEqual(machine.phase, .active)
    }

    private func activated(at now: TimeInterval) -> DuckStateMachine {
        var machine = DuckStateMachine()
        _ = machine.micBecameActive(now: now, config: config)
        let effects = machine.tick(now: now + config.minimumActive, config: config)
        XCTAssertEqual(effects, [.apply])
        return machine
    }
}
