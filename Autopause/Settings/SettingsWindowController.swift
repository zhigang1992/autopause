import AppKit
import SwiftUI

/// Owns the settings window directly. The SwiftUI `Settings` scene cannot be
/// opened reliably from an AppKit menu in an `LSUIElement` app.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let root = SettingsView()
                .environmentObject(model)
                .environmentObject(model.settings)
            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Autopause Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
