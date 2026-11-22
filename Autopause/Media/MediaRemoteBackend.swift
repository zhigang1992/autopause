import Foundation
import os

/// Private fallback for the system's current Now Playing session.
///
/// Music and Spotify are paused through Apple Events. Browsers and other
/// players (汽水音乐 / Soda Music, Electron apps, anything the play/pause media
/// key reaches) only publish Now Playing, and there is no public macOS API that
/// can pause them. This type `dlopen`s
/// `/System/Library/PrivateFrameworks/MediaRemote.framework` and:
///
/// - sends `MRMediaRemoteSendCommand` (0 = play, 1 = pause) in-process. These
///   are explicit commands, not a toggle, and are what the media key uses.
/// - reads whether Now Playing is playing, and its pid, with
///   `MRMediaRemoteGetNowPlayingApplicationIsPlaying` /
///   `MRMediaRemoteGetNowPlayingApplicationPID`. Since macOS 15.4 those getters
///   answer only Apple-signed processes and report "not playing, pid 0" to
///   everyone else, so the fallback would never pause anything. When they come
///   back empty, the state is read through `/usr/bin/osascript` (an Apple
///   binary) using `MRNowPlayingRequest` instead.
///
/// That framework is private. These calls do not work in the App Sandbox and a
/// build that ships them cannot go on the Mac App Store. If the symbols are
/// missing, `isAvailable` is false and Pause simply skips this backend.
final class MediaRemoteBackend: MediaBackend {
    struct State {
        var playing: Bool
        var pid: pid_t
    }

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

    var isAvailable: Bool { sendFunction != nil }

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
            log.error("MediaRemote failed to load; Now Playing pause is unavailable")
        }
    }

    func isPlaying() -> Bool {
        currentState().playing
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
        queue.async { [weak self] in
            let state = self?.currentState() ?? State(playing: false, pid: 0)
            DispatchQueue.main.async { completion(state.playing, state.pid) }
        }
    }

    /// Synchronous read of Now Playing. Blocks for at most about two seconds.
    /// Safe on any thread.
    func currentState() -> State {
        let direct = directState()
        if direct.pid != 0 {
            return direct
        }
        // pid 0 is what the entitlement-gated getters return on macOS 15.4+,
        // and also what they return when nothing is playing. Ask osascript.
        return scriptState() ?? direct
    }

    // MARK: - In-process getters (macOS 15.3 and earlier)

    private func directState() -> State {
        guard let isPlayingFunction else { return State(playing: false, pid: 0) }
        final class Box: @unchecked Sendable {
            var playing = false
            var pid: pid_t = 0
        }
        let box = Box()
        let callbackQueue = DispatchQueue.global(qos: .userInitiated)
        let group = DispatchGroup()

        // The callbacks escape, so they are stored as block values first.
        group.enter()
        let playingBlock: @convention(block) (Bool) -> Void = { value in
            box.playing = value
            group.leave()
        }
        isPlayingFunction(callbackQueue, playingBlock)
        if let pidFunction {
            group.enter()
            let pidBlock: @convention(block) (Int32) -> Void = { value in
                box.pid = value
                group.leave()
            }
            pidFunction(callbackQueue, pidBlock)
        }
        guard group.wait(timeout: .now() + 0.5) == .success else {
            return State(playing: false, pid: 0)
        }
        return State(playing: box.playing, pid: box.pid)
    }

    // MARK: - osascript (macOS 15.4 and later)

    /// JXA run by `/usr/bin/osascript`. Prints `<playing 0|1> <pid>`.
    private static let nowPlayingScript = """
    ObjC.import('Foundation');
    $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
    const R = $.NSClassFromString('MRNowPlayingRequest');
    if (R.isNil()) { '0 0'; } else {
      const player = R.localNowPlayingPlayerPath;
      const pid = player.isNil() || player.client.isNil() ? 0 : player.client.processIdentifier;
      (R.localIsPlaying ? '1 ' : '0 ') + pid;
    }
    """

    private func scriptState() -> State? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", Self.nowPlayingScript]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            log.error("osascript failed to launch: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        if finished.wait(timeout: .now() + 2) == .timedOut {
            process.terminate()
            log.error("osascript Now Playing query timed out")
            return nil
        }
        guard process.terminationStatus == 0 else {
            log.error("osascript Now Playing query exited \(process.terminationStatus)")
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = text.split(separator: " ")
        guard fields.count == 2, let pid = Int32(fields[1]) else {
            log.error("osascript Now Playing query returned \(text, privacy: .public)")
            return nil
        }
        return State(playing: fields[0] == "1", pid: pid)
    }

    // MARK: -

    private func send(_ command: UInt32) -> Bool {
        guard let sendFunction else { return false }
        return sendFunction(command, nil)
    }

    private static func load<T>(_ handle: UnsafeMutableRawPointer, _ name: String) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}
