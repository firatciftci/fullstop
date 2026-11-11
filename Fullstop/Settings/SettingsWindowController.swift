import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

private final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        Task { [weak self] in self?.view.window?.makeFirstResponder(nil) }
    }
}

final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        func add(_ title: String, symbol: String, _ pane: some View) {
            let host = NSHostingController(
                rootView:
                    pane
                    .environment(Preferences.shared)
                    .environment(HelperClient.shared)
                    .environment(Updater.shared)
                    .frame(width: 500)
                    .fixedSize(horizontal: false, vertical: true))
            host.sizingOptions = .preferredContentSize
            host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add(L.tabGeneral, symbol: "gearshape", GeneralPane())
        add(L.tabAbout, symbol: "info.circle", AboutPane())
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct GeneralPane: View {
    @Environment(HelperClient.self) private var helper
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle(L.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        if enabled {
                            try? SMAppService.mainApp.register()
                        } else {
                            try? SMAppService.mainApp.unregister()
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                KeyboardShortcuts.Recorder(L.shortcut, name: .togglePanel)
            }
            Section {
                LabeledContent {
                    switch helper.status {
                    case .enabled:
                        EmptyView()
                    case .requiresApproval:
                        Button(L.helperApprove) { SMAppService.openSystemSettingsLoginItems() }
                    default:
                        Button(L.helperInstall) { helper.install() }
                    }
                } label: {
                    Text(L.helperTitle)
                    Text(helperStatus)
                }
            } footer: {
                Text(L.helperFooter)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            helper.refresh()
        }
        .onAppear { helper.refresh() }
    }

    private var helperStatus: String {
        switch helper.status {
        case .enabled: L.helperEnabled
        case .requiresApproval: L.helperNeedsApproval
        case .notFound: L.helperUnavailable
        default: L.helperNotInstalled
        }
    }
}
