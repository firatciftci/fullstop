import ServiceManagement
import SwiftUI

struct PanelRootView: View {
    @Environment(BatteryMonitor.self) private var battery
    @Environment(ChargeController.self) private var charge
    @Environment(HelperClient.self) private var helper
    @Environment(Preferences.self) private var prefs
    @Environment(EnergySettings.self) private var energy

    @State private var draftLimit: Int?

    private var limit: Int { draftLimit ?? prefs.chargeLimit }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)
            limitControl
            if needsHelper {
                HelperBanner(status: helper.status) { helper.install() }
                    .padding(.top, 12)
            }
            modes
                .padding(.top, 14)
            Divider()
                .padding(.vertical, 14)
            PowerFlow(state: battery.state)
            if let mode = energy.mode(onBattery: !battery.state.isPluggedIn), energy.modes.count > 1 {
                energyControl(mode)
                    .padding(.top, 16)
            }
            Divider()
                .padding(.vertical, 14)
            BatteryStats(state: battery.state)
            HistoryChart(samples: BatteryHistory.shared.samples, current: battery.state.percent, limit: prefs.chargeLimit)
                .padding(.top, 14)
            if let message = charge.errorMessage, !needsHelper {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .padding(16)
        .onChange(of: battery.state.isPluggedIn) { energy.refresh() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(battery.state.percent.percentText)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(battery.state.percent)))
                    .animation(.smooth, value: battery.state.percent)
                Label {
                    Text(charge.status.text)
                } icon: {
                    Image(systemName: charge.status.symbol)
                        .foregroundStyle(statusColor)
                }
                .font(.headline)
                Text(detail ?? " ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .opacity(detail == nil ? 0 : 1)
                    .accessibilityHidden(detail == nil)
                    .animation(.smooth(duration: 0.2), value: detail == nil)
            }
            .accessibilityElement(children: .combine)
            .help(charge.status == .calibrating ? L.calibratingHelp : "")
            Spacer()
            Button {
                SettingsWindowController.shared.show()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.borderless)
            .help(L.settings)
            .accessibilityLabel(L.settings)
        }
    }

    private var limitControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.chargeLimit)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(limit >= Preferences.limitRange.upperBound ? L.chargeLimitOff : limit.percentText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(limit)))
                    .animation(.snappy, value: limit)
            }
            .accessibilityHidden(true)
            ChargeTrack(
                level: battery.state.percent, limit: limit, restDepth: charge.restFloor == nil ? nil : prefs.restDepth,
                fill: statusColor
            ) { value in
                draftLimit = value
            } onCommit: { value in
                draftLimit = nil
                charge.setLimit(value)
            }
        }
    }

    private var modes: some View {
        HStack(spacing: 8) {
            ModeButton(title: L.chargeToFull, symbol: "bolt.fill", isOn: charge.isChargingToFull, tint: .green) {
                charge.setChargingToFull(!charge.isChargingToFull)
            }
            .help(L.chargeToFullHelp)
            .disabled(prefs.chargeLimit >= Preferences.limitRange.upperBound && !charge.isChargingToFull)
            ModeButton(title: L.useBattery, symbol: "arrow.down", isOn: charge.isUsingBattery, tint: .yellow) {
                charge.setUsingBattery(!charge.isUsingBattery)
            }
            .help(charge.isCalibrating ? L.useBatteryCalibrating : helper.isReady ? L.useBatteryHelp : L.needsHelper)
            .disabled(!charge.canUseBattery)
        }
    }

    private func energyControl(_ mode: EnergyMode) -> some View {
        let onBattery = !battery.state.isPluggedIn
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.energyMode)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(L.batterySettings) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .pointerStyle(.link)
            }
            EnergyPicker(modes: energy.modes, selection: mode) { energy.set($0, onBattery: onBattery) }
                .disabled(!helper.isReady)
                .help(helper.isReady ? (onBattery ? L.energyHelpBattery : L.energyHelpAdapter) : L.needsHelper)
        }
    }

    private var needsHelper: Bool {
        !helper.isReady && (helper.status == .requiresApproval || charge.errorMessage == L.helperRequired)
    }

    private var statusColor: Color {
        if let tint = charge.status.tint { return Color(nsColor: tint) }
        return battery.state.percent <= 10 ? .red : .secondary
    }

    private var detail: String? {
        switch charge.status {
        case let .resting(_, floor): return L.restingDetail(floor.percentText)
        case .calibrating: return L.calibratingDetail
        case .heatPaused: return L.heatResumes(Double(prefs.heatThreshold - ChargeController.heatHysteresis).temperatureText)
        default: break
        }
        guard let minutes = charge.minutesRemaining, minutes > 0 else { return nil }
        if let target = charge.status.target {
            return L.timeToLimit(minutes.minutesText, target.percentText)
        }
        return L.timeRemaining(minutes.minutesText)
    }
}

private struct ModeButton: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        if isOn {
            button.buttonStyle(.glassProminent).tint(tint)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct HelperBanner: View {
    let status: SMAppService.Status
    let install: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(status == .requiresApproval ? L.helperBannerApprove : L.helperBannerInstall)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(status == .requiresApproval ? L.helperApprove : L.helperInstall) {
                if status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else {
                    install()
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct EnergyPicker: NSViewRepresentable {
    let modes: Array<EnergyMode>
    let selection: EnergyMode
    let onSelect: (EnergyMode) -> Void

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: [], trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        control.setAccessibilityLabel(L.energyMode)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.picker = self
        control.isEnabled = context.environment.isEnabled
        control.segmentCount = modes.count
        for (index, mode) in modes.enumerated() {
            control.setLabel(mode.title, forSegment: index)
        }
        control.selectedSegment = modes.firstIndex(of: selection) ?? -1
    }

    func makeCoordinator() -> Coordinator { Coordinator(picker: self) }

    final class Coordinator: NSObject {
        var picker: EnergyPicker

        init(picker: EnergyPicker) {
            self.picker = picker
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard picker.modes.indices.contains(sender.selectedSegment) else { return }
            picker.onSelect(picker.modes[sender.selectedSegment])
        }
    }
}
