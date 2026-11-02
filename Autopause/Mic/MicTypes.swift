import CoreAudio
import Foundation

struct InputDevice: Equatable, Identifiable {
    var objectID: AudioObjectID
    var uid: String
    var name: String
    var isRunning: Bool
    var id: String { uid }
}

struct MicProcess: Equatable, Identifiable {
    var objectID: AudioObjectID
    var pid: pid_t
    var bundleID: String?
    var name: String
    var isRunningInput: Bool
    /// UIDs of devices this process is using for input, when the HAL reports them.
    var inputDeviceUIDs: [String]
    var id: String { bundleID ?? "pid:\(pid)" }
}

struct MicSnapshot: Equatable {
    /// False when `kAudioHardwarePropertyProcessObjectList` cannot be read
    /// (older than macOS 14.2, or the property failed). Device running-state
    /// is the fallback in that case.
    var processAPIAvailable: Bool
    var processes: [MicProcess]
    var devices: [InputDevice]

    static let empty = MicSnapshot(processAPIAvailable: false, processes: [], devices: [])
}

enum MicHints {
    /// Offered as a hint when it shows up. Never selected automatically.
    static let doubaoBundleID = "com.bytedance.inputmethod.doubaoime"
}
