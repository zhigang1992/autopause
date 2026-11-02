import AppKit
import Sparkle

/// Wraps Sparkle's standard updater. Autopause is an `LSUIElement` app, so a
/// scheduled update prompt would otherwise appear behind other windows; the
/// delegate brings the app forward when Sparkle is about to show one.
final class UpdateController: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if handleShowingUpdate {
            NSApp.activate()
        }
    }
}
