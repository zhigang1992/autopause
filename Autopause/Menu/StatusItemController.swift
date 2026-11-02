import AppKit
import Combine

final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let menu = NSMenu()
    private var item: NSStatusItem?
    private var cancellable: AnyCancellable?

    private let onOpenSettings: () -> Void
    private let onCheckForUpdates: () -> Void

    init(model: AppModel, onOpenSettings: @escaping () -> Void, onCheckForUpdates: @escaping () -> Void) {
        self.model = model
        self.onOpenSettings = onOpenSettings
        self.onCheckForUpdates = onCheckForUpdates
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.menu = menu
        menu.delegate = self
        self.item = item
        cancellable = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.render()
            }
        }
        render()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: model.statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let enabled = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = model.settings.enabled ? .on : .off
        menu.addItem(enabled)

        let mode = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in DuckMode.allCases {
            let item = NSMenuItem(title: value.title, action: #selector(chooseMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value.rawValue
            item.state = model.settings.mode == value ? .on : .off
            submenu.addItem(item)
        }
        mode.submenu = submenu
        menu.addItem(mode)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Autopause", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func render() {
        guard let button = item?.button else { return }
        button.image = icon(ducking: model.menuIconIsDucking)
        button.toolTip = model.statusLine
        button.setAccessibilityLabel(model.statusLine)
        if menu.items.count > 0, let status = menu.item(at: 0), !status.isEnabled {
            status.title = model.statusLine
        }
    }

    private func icon(ducking: Bool) -> NSImage? {
        let symbol = ducking ? "mic.slash" : "mic"
        let pointSize = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: model.statusLine)?
            .withSymbolConfiguration(pointSize) else {
            return nil
        }
        if ducking {
            let tinted = base.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
            ) ?? base
            tinted.isTemplate = false
            return tinted
        }
        base.isTemplate = true
        return base
    }

    @objc private func toggleEnabled() {
        model.settings.enabled.toggle()
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = DuckMode(rawValue: raw) else {
            return
        }
        model.settings.mode = mode
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func checkForUpdates() {
        onCheckForUpdates()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
