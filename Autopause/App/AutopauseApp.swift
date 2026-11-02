import AppKit
import SwiftUI

@main
struct AutopauseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // The real settings window is `SettingsWindowController`. SwiftUI needs
        // at least one scene.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var settingsWindow = SettingsWindowController(model: model)
    private var status: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = StatusItemController(model: model) { [weak self] in
            self?.settingsWindow.show()
        }
        status.install()
        self.status = status
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.restoreOnQuit()
    }
}
