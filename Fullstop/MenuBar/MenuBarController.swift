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
        guard let button = item.button else { return }
        let symbol = state.isCharging ? "battery.100percent.bolt" : "battery.\(Self.bucket(state.percent))percent"
        let percent = (Double(state.percent) / 100).formatted(.percent)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: percent)
        button.setAccessibilityLabel(percent)
        button.toolTip = percent
    }

    private static func bucket(_ percent: Int) -> Int {
        switch percent {
        case ..<13: 0
        case ..<38: 25
        case ..<63: 50
        case ..<88: 75
        default: 100
        }
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
        let about = menu.addItem(withTitle: L.about, action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: L.settingsMenu, action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func popUp(_ menu: NSMenu, from button: NSStatusBarButton) {
        item.menu = menu
        button.performClick(nil)
        item.menu = nil
        button.highlight(panel.isVisible)
    }
}
