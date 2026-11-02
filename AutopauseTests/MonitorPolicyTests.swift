import CoreAudio
import XCTest

final class MonitorPolicyTests: XCTestCase {
    func testProcessInputIsPreferredOverAnAlwaysRunningDevice() {
        let decision = MonitorPolicy.decide(
            snapshot: MicSnapshot(
                processAPIAvailable: true,
                processes: [process(name: "DoubaoIme", bundleID: "com.example.ime", running: false)],
                devices: [device(uid: "virt", name: "Virtual", running: true)]
            ),
            allDevices: true,
            deviceUIDs: [],
            anyApp: true,
            bundleIDs: []
        )
        XCTAssertEqual(decision, .inactive)
    }

    func testRunningInputProcessActivatesAndNamesTheSource() {
        let decision = MonitorPolicy.decide(
            snapshot: MicSnapshot(
                processAPIAvailable: true,
                processes: [process(name: "DoubaoIme", bundleID: "com.example.ime", running: true)],
                devices: [device(uid: "mic", name: "Mic", running: true)]
            ),
            allDevices: true,
            deviceUIDs: [],
            anyApp: true,
            bundleIDs: []
        )
        XCTAssertEqual(decision, ActivityDecision(active: true, sourceName: "DoubaoIme"))
    }

    func testAppFilterMatchesOnlyTheSelectedBundle() {
        let snapshot = MicSnapshot(
            processAPIAvailable: true,
            processes: [
                process(name: "Zoom", bundleID: "us.zoom.xos", running: true),
                process(name: "DoubaoIme", bundleID: "com.example.ime", running: true),
            ],
            devices: []
        )
        let ignored = MonitorPolicy.decide(
            snapshot: snapshot,
            allDevices: true,
            deviceUIDs: [],
            anyApp: false,
            bundleIDs: ["com.example.ime"]
        )
        XCTAssertEqual(ignored.sourceName, "DoubaoIme")

        let none = MonitorPolicy.decide(
            snapshot: snapshot,
            allDevices: true,
            deviceUIDs: [],
            anyApp: false,
            bundleIDs: []
        )
        XCTAssertEqual(none, .inactive)
    }

    func testDeviceFilterDropsProcessesOnOtherDevices() {
        let snapshot = MicSnapshot(
            processAPIAvailable: true,
            processes: [
                process(
                    name: "DoubaoIme",
                    bundleID: "com.example.ime",
                    running: true,
                    deviceUIDs: ["other"]
                ),
            ],
            devices: [
                device(uid: "other", name: "Other", running: true),
                device(uid: "wanted", name: "Wanted", running: false),
            ]
        )
        let decision = MonitorPolicy.decide(
            snapshot: snapshot,
            allDevices: false,
            deviceUIDs: ["wanted"],
            anyApp: true,
            bundleIDs: []
        )
        XCTAssertEqual(decision, .inactive)
    }

    func testWithoutProcessAPIAnAppFilterMatchesNothing() {
        let decision = MonitorPolicy.decide(
            snapshot: MicSnapshot(
                processAPIAvailable: false,
                processes: [],
                devices: [device(uid: "mic", name: "Mic", running: true)]
            ),
            allDevices: true,
            deviceUIDs: [],
            anyApp: false,
            bundleIDs: ["com.example.ime"]
        )
        XCTAssertEqual(decision, .inactive)
    }

    func testWithoutProcessAPIDeviceRunningStateIsUsed() {
        let decision = MonitorPolicy.decide(
            snapshot: MicSnapshot(
                processAPIAvailable: false,
                processes: [],
                devices: [device(uid: "mic", name: "Mic", running: true)]
            ),
            allDevices: true,
            deviceUIDs: [],
            anyApp: true,
            bundleIDs: []
        )
        XCTAssertEqual(decision, ActivityDecision(active: true, sourceName: "Mic"))
    }

    private func process(
        name: String,
        bundleID: String,
        running: Bool,
        deviceUIDs: [String] = []
    ) -> MicProcess {
        MicProcess(
            objectID: 1,
            pid: 10,
            bundleID: bundleID,
            name: name,
            isRunningInput: running,
            inputDeviceUIDs: deviceUIDs
        )
    }

    private func device(uid: String, name: String, running: Bool) -> InputDevice {
        InputDevice(objectID: 2, uid: uid, name: name, isRunning: running)
    }
}
