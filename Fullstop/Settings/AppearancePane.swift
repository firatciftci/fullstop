import SwiftUI

struct AppearancePane: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var prefs = prefs
        Form {
            Section {
                Picker(L.iconStyle, selection: $prefs.iconStyle) {
                    Text(L.styleModern).tag(IconStyle.modern)
                    Text(L.styleClassic).tag(IconStyle.classic)
                }
                .disabled(!prefs.showIcon)
                Toggle(L.showIcon, isOn: $prefs.showIcon)
                    .disabled(prefs.showIcon && !prefs.showPercentage)
                Toggle(L.showPercentage, isOn: $prefs.showPercentage)
                    .disabled(prefs.showPercentage && !prefs.showIcon)
                Toggle(L.showLimitMarker, isOn: $prefs.showLimitMarker)
                    .disabled(!prefs.showIcon)
                Toggle(L.colorIcon, isOn: $prefs.colorIcon)
            }
            Section {
                Picker(L.symbolPosition, selection: $prefs.symbolsInside) {
                    Text(L.placementBeside).tag(false)
                    Text(L.placementInside).tag(true)
                }
                .disabled(!prefs.showIcon)
                ForEach(StatusSymbol.allCases, id: \.self) { symbol in
                    SymbolRow(symbol: symbol)
                }
            } header: {
                Text(L.symbolsHeader)
            } footer: {
                Text(L.symbolsFooter)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SymbolRow: View {
    let symbol: StatusSymbol

    @Environment(Preferences.self) private var prefs

    var body: some View {
        let sample = sample
        HStack(spacing: 16) {
            Image(systemName: symbol.systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(
                    sample.status.tint.map { Color(nsColor: $0) } ?? .gray, in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .padding(.trailing, -6)
                .accessibilityHidden(true)
            Text(symbol.title)
            Spacer()
            MenuBarSample(percent: sample.percent, limit: limit, status: sample.status)
            Toggle(symbol.title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private var limit: Int {
        prefs.chargeLimit < Preferences.limitRange.upperBound ? prefs.chargeLimit : 80
    }

    private var isOn: Binding<Bool> {
        Binding {
            prefs.statusSymbols.contains(symbol)
        } set: { enabled in
            if enabled {
                prefs.statusSymbols.insert(symbol)
            } else {
                prefs.statusSymbols.remove(symbol)
            }
        }
    }

    private var sample: (percent: Int, status: ChargeStatus) {
        switch symbol {
        case .charging: (max(limit - 15, 10), .charging(to: limit))
        case .limit: (limit, .holding(at: limit))
        case .resting: (max(limit - 4, 10), .resting(until: max(limit - 10, 10)))
        case .usingBattery: (min(limit + 10, 100), .usingBattery(to: limit))
        case .cooling: (max(limit - 30, 10), .heatPaused)
        case .calibrating: (max(limit - 20, 10), .calibrating)
        }
    }
}

private struct MenuBarSample: View {
    let percent: Int
    let limit: Int
    let status: ChargeStatus

    @Environment(Preferences.self) private var prefs

    var body: some View {
        HStack(spacing: 4) {
            if prefs.showPercentage, !prefs.percentInside {
                Text(percent.percentText)
                    .font(.system(size: 12))
                    .monospacedDigit()
            }
            if let image = BatteryGlyph.styled(percent: percent, limit: limit, status: status, label: status.text) {
                Image(nsImage: image)
                    .renderingMode(image.isTemplate ? .template : .original)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.primary)
        .frame(minWidth: 40, minHeight: 22)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .accessibilityHidden(true)
    }
}
