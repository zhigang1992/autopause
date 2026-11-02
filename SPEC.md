# Autopause — product spec

A macOS menu-bar utility that silences your music while you dictate.

**Problem.** The owner dictates with 豆包输入法 (DouBao Input Method,
bundle id `com.bytedance.inputmethod.doubaoime`). Music keeps playing while they
talk, so they manually stop it, dictate, then start it again. Autopause watches
for microphone activity and handles that automatically.

(Working name came from dictation: "autopose" == **Autopause**.)

## Platform / packaging

- macOS 14+ only, Swift + SwiftUI, Xcode project (not a Swift Package).
- Menu-bar app: `LSUIElement = YES` (no Dock icon). Settings window in SwiftUI.
- Product name `Autopause`, bundle id `app.reily.autopause`.
- Fully local: no network, no accounts, no telemetry, no audio capture.
- Goal order: (1) works great locally as a Developer ID / ad-hoc app,
  (2) keep the door open for the Mac App Store. Do not use private APIs in the
  default path. If something needs a private API or leaves the sandbox, isolate
  it behind a protocol and document it in the README.
- Entitlements file should be sandbox-ready even if the first build ships
  unsandboxed. Document which features survive the sandbox.

## Behaviour

State machine: `Idle -> Active -> Grace -> Idle`.

- **Active**: a monitored mic source is recording. Apply the chosen mode.
- **Grace**: the mic went idle; wait a configurable grace period (default 1.5 s)
  before restoring, so music does not bounce back between dictation phrases.
  If the mic becomes active again during grace, return to Active without
  re-applying.
- If the mic is already active at launch, apply immediately.
- Ignore blips shorter than a small minimum (~150 ms) so nothing flickers.
- Quitting while ducked must restore audio (`applicationWillTerminate`).

### Modes

1. **Pause** — pause whatever media is playing; resume afterwards **only if
   Autopause paused it** (never start something that was already paused, never
   fight a manual resume). Must work for Music, Spotify and browser media if at
   all possible. Put the backend behind a protocol so it can be swapped
   (public Now Playing / Apple Events / private MediaRemote). Prefer public
   APIs; if MediaRemote is the only thing that works for browsers, use it as a
   clearly-labelled fallback and say in the README that it blocks App Store.
2. **Mute** — media keeps playing, output is silenced via Core Audio on the
   default output device. Fade out over a configurable duration (default
   ~300 ms, slider 0–1500 ms, 0 = instant), fade back in on restore. Remember
   the pre-duck volume/mute state: if the user had it muted already, leave it
   alone; if the user changes volume mid-duck, adopt their value rather than
   forcing ours. Re-resolve the default output device if it changes mid-duck.

## Mic detection (no audio capture, no mic permission prompt)

- Device level: `kAudioDevicePropertyDeviceIsRunningSomewhere` on input devices,
  via Core Audio property listeners (event driven) plus a light 4–5 Hz poll as
  a safety net.
- Process level (macOS 14.2+): `kAudioHardwarePropertyProcessObjectList` with
  `kAudioProcessPropertyIsRunningInput`, bundle id, pid. This is the robust
  signal (some aggregate/virtual devices claim to be always running).
  Prefer it when available.

## Settings UI

- Master on/off toggle (also in the menu-bar menu).
- Mode picker: Pause | Mute. Fade-duration slider (Mute only). Grace period.
- **Which monitor to use**: checklist of input devices (default: all), with
  refresh. Plus an **App filter**: "Any app" (default) or a list of apps
  currently/recently using the mic (name, icon, bundle id) — the owner should
  be able to dictate once, see `DoubaoIme` appear, and pick "only this app" so
  Zoom calls etc. don't trigger it. Don't hardcode DouBao; do offer it as a
  hint when seen.
- Launch at login (`SMAppService`).
- Menu-bar icon: `mic` idle, `mic.slash`/tinted when ducking; a status line
  ("Listening" / "Ducking: DoubaoIme"). Menu: toggle, mode, Settings…, Quit.
- Persist everything in `UserDefaults`.

## Quality bar

- State machine is a pure type with injected clock/events; unit-test the
  transitions without hardware (Idle/Active/Grace, blips, re-activation during
  grace, already-active at launch).
- `xcodebuild -scheme Autopause -configuration Debug build` and tests pass.
- README: what it does, build/run, permissions required (none expected for
  mute; note anything asked for pause), sandbox / App Store notes per feature.

## Out of scope

iOS, per-app volume ducking, recording or analysing audio, speech recognition.
