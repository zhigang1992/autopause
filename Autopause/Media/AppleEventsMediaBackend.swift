import AppKit
import Foundation
import os

/// Public pause/resume for a scriptable player (Music, Spotify).
/// Does nothing when the app is not already running, so a duck never launches it.
final class AppleEventsMediaBackend: MediaBackend {
    let id: String
    let usesPrivateAPI = false
    let bundleID: String
    let applicationName: String
    private let log = Logger(subsystem: "app.reily.autopause", category: "apple-events")

    init(id: String, bundleID: String, applicationName: String) {
        self.id = id
        self.bundleID = bundleID
        self.applicationName = applicationName
    }

    var runningPID: pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .processIdentifier
    }

    func isPlaying() -> Bool {
        guard runningPID != nil else { return false }
        return run(
            """
            tell application "\(applicationName)"
                with timeout of 2 seconds
                    if player state is playing then
                        return "yes"
                    else
                        return "no"
                    end if
                end timeout
            end tell
            """
        )?.stringValue == "yes"
    }

    func pauseIfPlaying() -> Bool {
        guard isPlaying() else { return false }
        let paused = run(
            """
            tell application "\(applicationName)"
                with timeout of 2 seconds
                    pause
                end timeout
            end tell
            """
        ) != nil
        if !paused {
            log.error("pause failed for \(self.applicationName, privacy: .public)")
        }
        return paused
    }

    func resume() {
        guard runningPID != nil else { return }
        _ = run(
            """
            tell application "\(applicationName)"
                with timeout of 2 seconds
                    play
                end timeout
            end tell
            """
        )
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            log.error("AppleEvent \(self.applicationName, privacy: .public): \(error)")
            return nil
        }
        return result
    }
}
