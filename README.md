# Autopause

macOS menu-bar app that pauses or mutes your music while a microphone is in use.
Built for dictation (for example 豆包输入法) so you don't have to stop and start
playback by hand.

Nothing is recorded. Autopause never opens an input stream, never sends audio
anywhere, and has no account or network code.

## Build and run

Xcode, macOS 14 or later.

```sh
xcodebuild -scheme Autopause -configuration Debug build
xcodebuild -scheme Autopause -configuration Debug test -destination 'platform=macOS'
```

Run the `Autopause` scheme from Xcode, or open the built app from DerivedData.
It is a menu-bar item (`LSUIElement`): no Dock icon. The icon is a mic, and a
slashed mic while audio is ducked. The menu shows Listening or
`Ducking: <app>`, plus the on/off toggle, mode, Settings…, and Quit.

`project.yml` regenerates the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`xcodegen generate`). The checked-in `Autopause.xcodeproj` is what `xcodebuild` uses.

## Behaviour

`Idle → Active → Grace → Idle`.

- **Active** — a monitored mic source is in use. The selected mode is applied.
- **Grace** — the mic went idle. Autopause waits (default 1.5 s, slider 0–5 s) before restoring, so playback does not bounce between phrases. Activity during grace returns to Active and does not apply again.
- A blip shorter than about 150 ms never applies.
- If the mic is already active at launch, Autopause ducks immediately.
- Quitting while ducked restores audio.

### Pause

Pauses what is playing and resumes it afterwards only if Autopause paused it.
Something that was already paused is left alone. If you press play yourself
during the duck, that player is not paused again and is not sent another play
on restore.

Backends sit behind `MediaBackend`:

1. **Music** and **Spotify** — Apple Events (public). The app is not launched if it isn't already running.
2. **`MediaRemoteBackend`** — private fallback for the current Now Playing session, which is what actually pauses browser media. It `dlopen`s `/System/Library/PrivateFrameworks/MediaRemote.framework` and calls `MRMediaRemoteGetNowPlayingApplicationIsPlaying`, `MRMediaRemoteGetNowPlayingApplicationPID`, and `MRMediaRemoteSendCommand`. There is no public API that can do this. **This fallback blocks the Mac App Store** and does not work in the App Sandbox. If the symbols are missing, Pause still covers Music and Spotify.

Now Playing is a single session. Two players that are not Music or Spotify are not controlled independently.

### Mute

Fades the default output device's scalar volume with Core Audio (default
300 ms, slider 0–1500 ms, 0 = instant) and fades back on restore. Playback
itself keeps going.

- If the output was already muted, it is left alone.
- If you change the volume (or mute) mid-duck, Autopause adopts your level and stops forcing its own.
- If the default output device changes mid-duck, the previous device is restored and the duck follows the new one.
- A device with no scalar volume falls back to the hardware mute switch, instantly. If it has neither, Mute does nothing.

## Mic detection

No microphone permission, because no stream is opened.

- **Device** — `kAudioDevicePropertyDeviceIsRunningSomewhere` on input devices, via property listeners, plus a ~4.5 Hz poll.
- **Process** (preferred, macOS 14.2+) — `kAudioHardwarePropertyProcessObjectList` with `kAudioProcessPropertyIsRunningInput`, bundle id, and pid. Some aggregate and virtual devices report themselves as always running; the process signal is what avoids that. It is used whenever the property can be read.

The device checklist defaults to all input devices. The app filter defaults to any app. Dictate once, then pick **Only these apps** (name, icon, bundle id). 豆包输入法 (`com.bytedance.inputmethod.doubaoime`) is not hardcoded as a trigger; when that bundle id shows up, Settings offers it as a hint.

Launch at login uses `SMAppService`. A Developer ID build that isn't in `/Applications` may fail to register; the error is shown on the toggle.

Everything in Settings is stored in `UserDefaults`.

## Permissions

| Action | Prompt |
| --- | --- |
| Mic detection | None. Microphone access is not requested. |
| Mute | None. |
| Pause of Music or Spotify | Automation, the first time each app is controlled. Deny it and Pause can't drive that app; Mute still works. |
| Pause of browsers (MediaRemote) | None, but it is a private API. See below. |
| Launch at login | macOS may ask you to approve the login item. |

## Sandbox and the Mac App Store

`Autopause.entitlements` ships with `com.apple.security.app-sandbox` set to **false** so a Developer ID or ad-hoc build can pause other apps. Flip it to true for a sandboxed build.

| Feature | Sandboxed / App Store build |
| --- | --- |
| Mic detection (device and process properties, no stream opened) | Works. No microphone entitlement. |
| Mute (public Core Audio output volume) | Works. |
| Launch at login (`SMAppService.mainApp`) | Works. |
| Pause via Apple Events (Music, Spotify) | Needs `com.apple.security.automation.apple-events` plus a scripting target per app. Those temporary exceptions are not accepted on the Mac App Store, so this path does not survive review. |
| Pause via `MediaRemoteBackend` | Private API. Unavailable in the sandbox and rejected on the App Store. Remove that type, or stop calling it, for a store build. Music and Spotify do not use it. |

## Tests

`DuckStateMachine` is pure: Idle, Active, Grace, blips, re-activation during grace, and already-active at launch are covered without hardware. `MonitorPolicy` is covered the same way (process signal over an always-running device, app filter, device filter).

## Out of scope

iOS, per-app volume ducking, recording or analysing audio, speech recognition.
