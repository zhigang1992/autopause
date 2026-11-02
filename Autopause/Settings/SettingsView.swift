import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Autopause", isOn: $settings.enabled)
                Picker("Mode", selection: $settings.mode) {
                    ForEach(DuckMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(modeCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.mode == .mute {
                    slider(
                        title: "Fade duration",
                        value: $settings.fadeDuration,
                        range: 0...1.5,
                        step: 0.05,
                        caption: fadeCaption
                    )
                }
                slider(
                    title: "Grace period",
                    value: $settings.gracePeriod,
                    range: 0...5,
                    step: 0.1,
                    caption: "Wait \(graceCaption) after the mic goes idle before restoring, so music does not bounce between phrases."
                )
            }

            Section {
                Toggle("All input devices", isOn: $settings.monitorAllDevices)
                if model.devices.isEmpty {
                    Text("No input devices found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.devices) { device in
                        Toggle(device.name, isOn: model.deviceBinding(device.uid))
                            .disabled(settings.monitorAllDevices)
                    }
                }
                Button("Refresh") {
                    model.refreshMic()
                }
            } header: {
                Text("Input devices")
            }

            Section {
                Picker("Trigger", selection: $settings.anyApp) {
                    Text("Any app").tag(true)
                    Text("Only these apps").tag(false)
                }
                if !model.processAPIAvailable && !settings.anyApp {
                    Text("The per-app mic list needs macOS 14.2 or later. Until then, only the device list is used.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !settings.anyApp {
                    if model.micApps.isEmpty {
                        Text("Dictate once. Apps using the mic will show up here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.micApps) { app in
                            Toggle(isOn: model.appBinding(app.bundleID)) {
                                HStack(spacing: 8) {
                                    if let icon = model.icon(for: app.bundleID) {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 18, height: 18)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.name)
                                        Text(app.bundleID)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if settings.allowedBundleIDs.isEmpty {
                            Text("Nothing is selected, so Autopause will not duck.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if model.showsDoubaoHint {
                    Text("豆包输入法 showed up on the mic. Choose Only these apps and select it if Zoom and other calls should not duck your music.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("App filter")
            }

            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                if let loginItemError = model.loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Text("Mute needs no permission. Pause asks to control Music and Spotify the first time; browsers use a private Now Playing fallback that cannot ship on the Mac App Store.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .padding(.vertical, 8)
    }

    private var modeCaption: String {
        switch settings.mode {
        case .pause:
            "Pauses Music, Spotify, and the current Now Playing app. Resumes only what Autopause paused."
        case .mute:
            "Fades the default output volume. Media keeps playing."
        }
    }

    private var fadeCaption: String {
        let milliseconds = Int((settings.fadeDuration * 1000).rounded())
        if milliseconds == 0 {
            return "Instant."
        }
        return "\(milliseconds) ms."
    }

    private var graceCaption: String {
        String(format: "%.1f s", settings.gracePeriod)
    }

    private func slider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        caption: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Slider(value: value, in: range, step: step)
            }
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
