import Foundation

/// Pauses players on duck and resumes them afterwards only if this controller
/// paused them. A manual play during the duck is adopted: that player is not
/// paused again and is not sent a second play on restore.
final class PauseController {
    private let music = AppleEventsMediaBackend(
        id: "music",
        bundleID: "com.apple.Music",
        applicationName: "Music"
    )
    private let spotify = AppleEventsMediaBackend(
        id: "spotify",
        bundleID: "com.spotify.client",
        applicationName: "Spotify"
    )
    private let mediaRemote = MediaRemoteBackend()

    private var generation = 0
    private var pausedPublic: [AppleEventsMediaBackend] = []
    private var pausedPublicPIDs: [pid_t] = []
    private var confirmedPaused: Set<String> = []
    private var overriddenPublic: Set<String> = []
    private var pausedMediaRemote = false
    private var mediaRemotePID: pid_t = 0
    private var mediaRemoteConfirmedPaused = false
    private var mediaRemoteOverridden = false
    private var lastPoll = Date.distantPast
    private var pollInFlight = false
    private(set) var isDucking = false

    func apply() {
        generation += 1
        let generation = generation
        isDucking = true
        pausedPublic = []
        pausedPublicPIDs = []
        confirmedPaused = []
        overriddenPublic = []
        pausedMediaRemote = false
        mediaRemotePID = 0
        mediaRemoteConfirmedPaused = false
        mediaRemoteOverridden = false
        lastPoll = Date()

        for backend in [music, spotify] {
            if backend.pauseIfPlaying() {
                pausedPublic.append(backend)
                if let pid = backend.runningPID {
                    pausedPublicPIDs.append(pid)
                }
            }
        }

        guard mediaRemote.isAvailable else { return }
        mediaRemote.query { [weak self] playing, pid in
            guard let self, self.generation == generation, self.isDucking else { return }
            // Music/Spotify were already paused. A stale Now Playing pid for
            // one of them is not a second player.
            guard playing, !self.pausedPublicPIDs.contains(pid) else { return }
            guard self.mediaRemote.sendPauseCommand() else { return }
            guard self.generation == generation, self.isDucking else {
                self.mediaRemote.resume()
                return
            }
            self.pausedMediaRemote = true
            self.mediaRemotePID = pid
        }
    }

    /// Called often. Work is throttled to about once a second and never
    /// re-pauses a player the user has started again.
    func pollManualResume() {
        guard isDucking else { return }
        guard Date().timeIntervalSince(lastPoll) >= 1 else { return }
        lastPoll = Date()

        for backend in pausedPublic where !overriddenPublic.contains(backend.id) {
            if backend.isPlaying() {
                if confirmedPaused.contains(backend.id) {
                    overriddenPublic.insert(backend.id)
                }
            } else {
                confirmedPaused.insert(backend.id)
            }
        }

        guard pausedMediaRemote, !mediaRemoteOverridden, !pollInFlight else { return }
        pollInFlight = true
        let generation = generation
        mediaRemote.query { [weak self] playing, pid in
            guard let self else { return }
            self.pollInFlight = false
            guard self.generation == generation, self.isDucking, self.pausedMediaRemote else { return }
            guard pid == self.mediaRemotePID || pid == 0 else { return }
            if !playing {
                self.mediaRemoteConfirmedPaused = true
            } else if self.mediaRemoteConfirmedPaused {
                self.mediaRemoteOverridden = true
            }
        }
    }

    func restore() {
        generation += 1
        isDucking = false
        pollInFlight = false
        for backend in pausedPublic where !overriddenPublic.contains(backend.id) {
            if !backend.isPlaying() {
                backend.resume()
            }
        }
        if pausedMediaRemote, !mediaRemoteOverridden {
            mediaRemote.resume()
        }
        clear()
    }

    private func clear() {
        pausedPublic = []
        pausedPublicPIDs = []
        confirmedPaused = []
        overriddenPublic = []
        pausedMediaRemote = false
        mediaRemotePID = 0
        mediaRemoteConfirmedPaused = false
        mediaRemoteOverridden = false
    }
}
