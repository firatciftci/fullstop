import AppIntents
import AppKit
import KeyboardShortcuts
import Observation

extension KeyboardShortcuts.Name {
    static let togglePanel = Self("togglePanel")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var quitting = false

    func applicationDidFinishLaunching(_: Notification) {
        if let appearance = DemoData.appearance { NSApp.appearance = NSAppearance(named: appearance) }
        NSApp.mainMenu = Self.makeMainMenu()
        BatteryMonitor.shared.start()
        HelperClient.shared.refresh()
        ChargeController.shared.start()
        EnergySettings.shared.refresh()
        FullstopShortcuts.updateAppShortcutParameters()
        _ = Updater.shared
        let menuBar = MenuBarController(panel: PanelController())
        self.menuBar = menuBar
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak menuBar] in
            menuBar?.togglePanel()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        menuBar?.togglePanel()
        return false
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await ChargeController.shared.prepareToQuit() }
                group.addTask { try? await Task.sleep(for: .seconds(5)) }
                await group.next()
                group.cancelAll()
            }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func application(_: NSApplication, open urls: Array<URL>) {
        for url in urls {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "fullstop" else { return }
        let charge = ChargeController.shared
        switch url.host() {
        case "limit":
            if let value = url.pathComponents.dropFirst().first.flatMap({ Int($0) }) {
                charge.setLimit(value)
            }
        case "full-charge":
            charge.setChargingToFull(true)
        case "use-battery":
            charge.setUsingBattery(true)
        case "settings":
            SettingsWindowController.shared.show(tab: url.pathComponents.dropFirst().first.flatMap { Int($0) })
        default:
            break
        }
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
