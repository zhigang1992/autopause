import Foundation

/// Pure Idle → Active → Grace → Idle machine. The clock and mic events are
/// injected so transitions can be tested without hardware.
struct DuckStateMachine: Equatable {
    enum Phase: Equatable {
        /// Mic is idle and audio is at the user's level.
        case idle
        /// Mic just went active. Waiting out `Config.minimumActive` before ducking,
        /// so a short blip never applies.
        case pending
        /// Duck is applied.
        case active
        /// Mic went idle. Duck stays applied until `grace` elapses.
        case grace
    }

    enum Effect: Equatable {
        case apply
        case restore
    }

    struct Config: Equatable {
        var grace: TimeInterval = 1.5
        /// Ignore activations shorter than this. Default ~150 ms.
        var minimumActive: TimeInterval = 0.15
    }

    private(set) var phase: Phase = .idle
    private var pendingSince: TimeInterval?
    private var graceDeadline: TimeInterval?
    /// Keeps a timestamp that lands on the threshold from comparing short
    /// because of binary rounding.
    private let timeEpsilon: TimeInterval = 0.000_1

    /// True once a duck has been applied and not yet restored (Active or Grace).
    var isDucked: Bool {
        phase == .active || phase == .grace
    }

    /// Mic already active at launch: duck immediately, with no blip delay.
    mutating func launch(micActive: Bool, now: TimeInterval) -> [Effect] {
        pendingSince = nil
        graceDeadline = nil
        if micActive {
            phase = .active
            return [.apply]
        }
        phase = .idle
        return []
    }

    mutating func micBecameActive(now: TimeInterval, config: Config) -> [Effect] {
        switch phase {
        case .idle:
            phase = .pending
            pendingSince = now
            return []
        case .pending, .active:
            return []
        case .grace:
            // Already ducked. Come back without applying a second time.
            phase = .active
            graceDeadline = nil
            return []
        }
    }

    mutating func micBecameIdle(now: TimeInterval, config: Config) -> [Effect] {
        switch phase {
        case .idle, .grace:
            return []
        case .pending:
            phase = .idle
            pendingSince = nil
            return []
        case .active:
            if config.grace <= 0 {
                phase = .idle
                graceDeadline = nil
                return [.restore]
            }
            phase = .grace
            graceDeadline = now + config.grace
            return []
        }
    }

    /// Advances the blip window and the grace deadline. Call on a timer.
    mutating func tick(now: TimeInterval, config: Config) -> [Effect] {
        switch phase {
        case .pending:
            guard let pendingSince else { return [] }
            if now + timeEpsilon >= pendingSince + config.minimumActive {
                phase = .active
                self.pendingSince = nil
                return [.apply]
            }
            return []
        case .grace:
            guard let graceDeadline else { return [] }
            if now + timeEpsilon >= graceDeadline {
                phase = .idle
                self.graceDeadline = nil
                return [.restore]
            }
            return []
        case .idle, .active:
            return []
        }
    }

    /// Drop to idle without emitting restore. The caller restores hardware itself
    /// (master switch off, or quit).
    mutating func reset() {
        phase = .idle
        pendingSince = nil
        graceDeadline = nil
    }
}
