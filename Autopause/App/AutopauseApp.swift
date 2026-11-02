import AppKit
import SwiftUI

@main
struct AutopauseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.model.settings)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var status: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = StatusItemController(model: model)
        status.install()
        self.status = status
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.restoreOnQuit()
    }
}
