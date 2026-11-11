import AppKit
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        BatteryMonitor.shared.start()
        HelperClient.shared.refresh()
        _ = Updater.shared
        let menuBar = MenuBarController(panel: PanelController())
        self.menuBar = menuBar
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak menuBar] in
            menuBar?.togglePanel()
        }
        ChargeController.shared.apply(Preferences.shared.chargeLimit)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        menuBar?.togglePanel()
        return false
    }

    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L.settingsMenu, action: #selector(Self.openSettings), keyEquivalent: ",")
        if Updater.shared.isAvailable {
            appMenu.addItem(withTitle: L.checkForUpdatesMenu, action: #selector(Updater.checkForUpdates(_:)), keyEquivalent: "").target =
                Updater.shared
        }
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }

    @objc func openSettings() {
        SettingsWindowController.shared.show()
    }
}

func trackChanges(_ body: @escaping @MainActor @Sendable () -> Void) {
    withObservationTracking {
        body()
    } onChange: {
        Task { @MainActor in trackChanges(body) }
    }
}
