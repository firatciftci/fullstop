import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

private final class DemoWindow: NSWindow {
    @objc func hasKeyAppearance() -> Bool { true }
    @objc func hasMainAppearance() -> Bool { true }
}

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
                    .environment(BatteryMonitor.shared)
                    .environment(ChargeController.shared)
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
        add(L.tabCharging, symbol: "bolt.batteryblock", ChargingPane())
        add(L.tabAppearance, symbol: "menubar.rectangle", AppearancePane())
        add(L.tabAbout, symbol: "info.circle", AboutPane())
        let window = DemoData.isEnabled ? DemoWindow(contentViewController: tabs) : NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    func show(tab: Int? = nil) {
        guard let window else { return }
        if let tab, let tabs = contentViewController as? NSTabViewController, tabs.tabViewItems.indices.contains(tab) {
            tabs.selectedTabViewItemIndex = tab
        }
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

private struct GeneralPane: View {
    @Environment(Preferences.self) private var prefs
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var prefs = prefs
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
        }
        .formStyle(.grouped)
    }
}

private struct ChargingPane: View {
    @Environment(Preferences.self) private var prefs
    @Environment(HelperClient.self) private var helper
    @Environment(BatteryMonitor.self) private var battery
    @Environment(ChargeController.self) private var charge

    @State private var draftLimit: Double?

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                LabeledContent(L.chargeLimit) {
                    HStack(spacing: 12) {
                        Slider(
                            value: limitBinding,
                            in: Double(Preferences.limitRange.lowerBound)...Double(Preferences.limitRange.upperBound),
                            step: Double(Preferences.limitStep)
                        ) {
                            Text(L.chargeLimit)
                        } onEditingChanged: { editing in
                            guard !editing, let draftLimit else { return }
                            charge.setLimit(Int(draftLimit))
                            self.draftLimit = nil
                        }
                        .labelsHidden()
                        Text(limitText)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                    .frame(width: 260)
                }
            } footer: {
                footer(L.chargeLimitFooter)
            }
            Section {
                Toggle(L.heatProtection, isOn: $prefs.heatProtection)
                Picker(L.heatThreshold, selection: $prefs.heatThreshold) {
                    ForEach(Preferences.heatThresholds, id: \.self) { celsius in
                        Text(Double(celsius).temperatureText).tag(celsius)
                    }
                }
                .disabled(!prefs.heatProtection)
            } footer: {
                footer(helper.isReady ? L.heatFooter : [L.heatFooter, L.needsHelper].joined(separator: " "))
            }
            Section {
                Toggle(L.restToggle, isOn: $prefs.restEnabled)
                Picker(L.restLevel, selection: restDepthBinding) {
                    ForEach(restDepths, id: \.self) { depth in
                        Text((prefs.chargeLimit - depth).percentText).tag(depth)
                    }
                }
                .disabled(!prefs.restEnabled || restDepths.isEmpty)
            } footer: {
                footer(helper.isReady ? L.restFooter : [L.restFooter, L.needsHelper].joined(separator: " "))
            }
            .disabled(prefs.chargeLimit >= Preferences.limitRange.upperBound)
            if battery.hasMagSafeLight {
                Section {
                    Picker(L.magSafeLight, selection: $prefs.magSafeLight) {
                        Text(L.lightAutomatic).tag(MagSafeLight.system)
                        Text(L.lightOff).tag(MagSafeLight.off)
                    }
                    .disabled(!helper.isReady)
                } footer: {
                    footer(helper.isReady ? L.lightFooter : [L.lightFooter, L.needsHelper].joined(separator: " "))
                }
            }
            Section {
                LabeledContent {
                    switch helper.status {
                    case .enabled:
                        Button(L.helperRemove) { Task { await charge.removeHelper() } }
                    case .requiresApproval:
                        Button(L.helperApprove) { SMAppService.openSystemSettingsLoginItems() }
                    case .notRegistered, .notFound:
                        Button(L.helperInstall) { helper.install() }
                    @unknown default:
                        EmptyView()
                    }
                } label: {
                    Text(L.helperTitle)
                    Text(helper.installError ?? helperStatus)
                }
            } footer: {
                footer(L.helperFooter)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            helper.refresh()
        }
        .onAppear { helper.refresh() }
    }

    private var restDepths: Array<Int> {
        Preferences.restDepths.filter { prefs.chargeLimit - $0 >= Preferences.limitRange.lowerBound }
    }

    private var restDepthBinding: Binding<Int> {
        Binding {
            min(prefs.restDepth, restDepths.last ?? prefs.restDepth)
        } set: { depth in
            prefs.restDepth = depth
        }
    }

    private var limitBinding: Binding<Double> {
        Binding {
            draftLimit ?? Double(prefs.chargeLimit)
        } set: { value in
            draftLimit = value
        }
    }

    private var limitText: String {
        let limit = Int(draftLimit ?? Double(prefs.chargeLimit))
        return limit >= Preferences.limitRange.upperBound ? L.chargeLimitOff : limit.percentText
    }

    private var helperStatus: String {
        switch helper.status {
        case .enabled: L.helperEnabled
        case .requiresApproval: L.helperNeedsApproval
        default: L.helperNotInstalled
        }
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
