import SwiftUI

struct PowerFlow: View {
    let state: BatteryState

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Metric(
                value: state.isPluggedIn ? state.powerIn.wattsText : "–",
                label: L.powerAdapter,
                symbol: "powerplug.portrait.fill"
            )
            .help(state.adapterWatts.map { Double($0).wattsText } ?? "")
            Metric(value: state.systemLoad.wattsText, label: L.powerSystem, symbol: "laptopcomputer")
            Metric(value: state.batteryPower.signedWattsText, label: L.powerBattery, symbol: "minus.plus.batteryblock.fill")
        }
    }
}

struct BatteryStats: View {
    let state: BatteryState

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Metric(value: state.health.map(\.percentText) ?? "–", label: L.health)
            Metric(value: state.cycleCount.formatted(), label: L.cycles)
            Metric(value: state.temperature?.temperatureText ?? "–", label: L.temperature)
            Metric(
                value: Measurement(value: Double(state.maximumCapacity), unit: UnitElectricCharge.milliampereHours)
                    .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.grouping(.automatic))),
                label: L.capacity
            )
        }
    }
}

private struct Metric: View {
    let value: String
    let label: String
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
