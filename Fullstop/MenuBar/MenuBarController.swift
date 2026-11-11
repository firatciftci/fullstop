import AppKit

final class MenuBarController: NSObject {
    private let panel: PanelController
    private let item: NSStatusItem

    init(panel: PanelController) {
        self.panel = panel
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        item.autosaveName = "FullstopBattery"
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        panel.onVisibilityChange = { [weak self] visible in
            self?.item.button?.highlight(visible)
        }

        trackChanges { [weak self] in
            self?.refresh()
        }
    }

    func togglePanel() {
        panel.toggle(from: item.button)
    }

    private func refresh() {
        let state = BatteryMonitor.shared.state
        let charge = ChargeController.shared
        let prefs = Preferences.shared
        guard let button = item.button else { return }
        let status = charge.status
        let label = [state.percent.percentText, status.text].joined(separator: ", ")
        let image = BatteryGlyph.styled(percent: state.percent, limit: charge.displayLimit, status: status, label: label)
        button.image = image
        if prefs.showPercentage, !prefs.percentInside {
            button.imagePosition = image == nil ? .noImage : .imageTrailing
            button.attributedTitle = NSAttributedString(
                string: state.percent.percentText + (image == nil ? "" : " "),
                attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
        }
        button.setAccessibilityLabel(label)
        button.toolTip = label
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popUp(utilityMenu(), from: sender)
            return
        }
        panel.toggle(from: sender)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel()
    }

    private func utilityMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(action(L.about, #selector(openAbout), symbol: "info.circle"))
        menu.addItem(.separator())
        menu.addItem(action(L.settingsMenu, #selector(openSettings), symbol: "gearshape", key: ","))
        if Updater.shared.isAvailable {
            let update = NSMenuItem(title: L.checkForUpdatesMenu, action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "")
            update.target = Updater.shared
            update.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
            menu.addItem(update)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
        for entry in menu.items {
            entry.preferredImageVisibility = .visible
        }
        return menu
    }

    private func action(_ title: String, _ selector: Selector, symbol: String, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return entry
    }

    private func popUp(_ menu: NSMenu, from button: NSStatusBarButton) {
        guard let placement = button.menuBarPlacement else { return }
        button.highlight(true)
        menu.popUp(positioning: nil, at: NSPoint(x: placement.frame.minX - 5, y: placement.barBottom - 6), in: nil)
        button.highlight(panel.isVisible)
    }
}
