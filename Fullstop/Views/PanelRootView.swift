import SwiftUI

struct PanelRootView: View {
    @Environment(BatteryMonitor.self) private var battery
    @Environment(ChargeController.self) private var charge
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text((Double(battery.state.percent) / 100).formatted(.percent))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Text(status)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent(L.chargeLimit) {
                    Text(limitLabel)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: limitBinding,
                    in: Double(Preferences.limitRange.lowerBound)...Double(Preferences.limitRange.upperBound),
                    step: Double(Preferences.limitStep)
                ) {
                    Text(L.chargeLimit)
                } onEditingChanged: { editing in
                    if !editing { charge.apply(prefs.chargeLimit) }
                }
                .labelsHidden()
            }
            if let message = charge.errorMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }

    private var limitBinding: Binding<Double> {
        Binding {
            Double(prefs.chargeLimit)
        } set: { value in
            prefs.chargeLimit = Int(value)
        }
    }

    private var limitLabel: String {
        prefs.chargeLimit >= Preferences.limitRange.upperBound
            ? L.chargeLimitOff : (Double(prefs.chargeLimit) / 100).formatted(.percent)
    }

    private var status: String {
        let state = battery.state
        if !state.isPluggedIn { return L.stateOnBattery }
        if state.isCharging { return L.stateCharging }
        if state.isFullyCharged { return L.stateFull }
        return state.percent >= prefs.chargeLimit - 1 ? L.statePaused : L.stateNotCharging
    }
}
