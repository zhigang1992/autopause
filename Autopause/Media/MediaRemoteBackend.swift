import Foundation
import os

/// Private fallback for the system's current Now Playing session.
///
/// Music and Spotify are paused through Apple Events. Browsers (and anything
/// else that only publishes Now Playing) are not scriptable, and there is no
/// public macOS API that can pause them. This type `dlopen`s
/// `/System/Library/PrivateFrameworks/MediaRemote.framework` and calls:
///
/// - `MRMediaRemoteGetNowPlayingApplicationIsPlaying`
/// - `MRMediaRemoteGetNowPlayingApplicationPID`
/// - `MRMediaRemoteSendCommand` (0 = play, 1 = pause)
///
/// That framework is private. These calls do not work in the App Sandbox and a
/// build that ships them cannot go on the Mac App Store. If the symbols are
/// missing, `isAvailable` is false and Pause simply skips this backend.
final class MediaRemoteBackend: MediaBackend {
    let id = "mediaremote"
    let usesPrivateAPI = true

    private let log = Logger(subsystem: "app.reily.autopause", category: "mediaremote")
    private let handle: UnsafeMutableRawPointer?
    private let queue = DispatchQueue(label: "app.reily.autopause.mediaremote")

    private typealias IsPlayingFunction = @convention(c) (DispatchQueue, @convention(block) (Bool) -> Void) -> Void
    private typealias PIDFunction = @convention(c) (DispatchQueue, @convention(block) (Int32) -> Void) -> Void
    private typealias SendFunction = @convention(c) (UInt32, CFDictionary?) -> Bool

    private let isPlayingFunction: IsPlayingFunction?
    private let pidFunction: PIDFunction?
    private let sendFunction: SendFunction?

    private let playCommand: UInt32 = 0
    private let pauseCommand: UInt32 = 1

    var isAvailable: Bool { isPlayingFunction != nil && sendFunction != nil }

    init() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        handle = dlopen(path, RTLD_NOW)
        if let handle {
            isPlayingFunction = Self.load(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying")
            pidFunction = Self.load(handle, "MRMediaRemoteGetNowPlayingApplicationPID")
            sendFunction = Self.load(handle, "MRMediaRemoteSendCommand")
        } else {
            isPlayingFunction = nil
            pidFunction = nil
            sendFunction = nil
            log.error("MediaRemote failed to load; browser pause is unavailable")
        }
    }

    func isPlaying() -> Bool {
        var playing = false
        let semaphore = DispatchSemaphore(value: 0)
        query { value, _ in
            playing = value
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 1)
        return playing
    }

    func pauseIfPlaying() -> Bool {
        guard isPlaying() else { return false }
        return send(pauseCommand)
    }

    /// Pause without asking again. Used after `query` already reported playback.
    func sendPauseCommand() -> Bool {
        send(pauseCommand)
    }

    func resume() {
        _ = send(playCommand)
    }

    /// Whether Now Playing is active, and which pid owns it. Completion is on the main queue.
    func query(completion: @escaping (_ playing: Bool, _ pid: pid_t) -> Void) {
        guard let isPlayingFunction else {
            DispatchQueue.main.async { completion(false, 0) }
            return
        }
        let playingBlock: @convention(block) (Bool) -> Void = { [weak self] playing in
            guard let self else {
                DispatchQueue.main.async { completion(false, 0) }
                return
            }
            guard let pidFunction = self.pidFunction else {
                DispatchQueue.main.async { completion(playing, 0) }
                return
            }
            let pidBlock: @convention(block) (Int32) -> Void = { pid in
                DispatchQueue.main.async { completion(playing, pid) }
            }
            pidFunction(self.queue, pidBlock)
        }
        isPlayingFunction(queue, playingBlock)
    }

    private func send(_ command: UInt32) -> Bool {
        guard let sendFunction else { return false }
        return sendFunction(command, nil)
    }

    private static func load<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}
