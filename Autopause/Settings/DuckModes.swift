import Foundation

/// Which actions a duck performs. Mute and Pause are independent and can both
/// be on. At least one is always on.
struct DuckModes: Equatable {
    var mute: Bool
    var pause: Bool

    static let pauseOnly = DuckModes(mute: false, pause: true)
    static let muteOnly = DuckModes(mute: true, pause: false)
    static let both = DuckModes(mute: true, pause: true)

    /// What a duck does, in order. With both on, the pause waits for the fade
    /// out to finish, and the restore plays at the faded-out level before
    /// fading back in.
    enum Step: Equatable {
        case fadeOut
        case pause
        case play
        case fadeIn
    }

    var applySteps: [Step] {
        var steps: [Step] = []
        if mute { steps.append(.fadeOut) }
        if pause { steps.append(.pause) }
        return steps
    }

    var restoreSteps: [Step] {
        var steps: [Step] = []
        if pause { steps.append(.play) }
        if mute { steps.append(.fadeIn) }
        return steps
    }

    /// Settings before Mute and Pause were split stored one `mode` string,
    /// "pause" or "mute". Anything else falls back to the old default, Pause.
    static func migrating(legacyMode: String?) -> DuckModes {
        legacyMode == "mute" ? .muteOnly : .pauseOnly
    }

    /// Turning off the last mode would leave Autopause ducking with nothing,
    /// so that change is refused.
    func setting(mute: Bool? = nil, pause: Bool? = nil) -> DuckModes {
        let next = DuckModes(mute: mute ?? self.mute, pause: pause ?? self.pause)
        return next.mute || next.pause ? next : self
    }

    /// True when this mode is the only one on, so its control stays locked on.
    func isLastOn(mute: Bool) -> Bool {
        mute ? (self.mute && !pause) : (pause && !self.mute)
    }
}
