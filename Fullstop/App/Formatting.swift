import AppKit

extension Int {
    var percentText: String { (Double(self) / 100).formatted(.percent) }

    var minutesText: String {
        Duration.seconds(self * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

extension Double {
    var temperatureText: String {
        Measurement(value: self, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    var wattsText: String {
        Measurement(value: self, unit: UnitPower.watts)
            .formatted(
                .measurement(
                    width: .abbreviated, usage: .asProvided,
                    numberFormatStyle: .number.precision(.fractionLength(abs(self) < 10 ? 1 : 0))))
    }

    var signedWattsText: String {
        switch self {
        case 0.05...: "+\(wattsText)"
        case ...(-0.05): "\u{2212}\(abs(self).wattsText)"
        default: 0.0.wattsText
        }
    }
}

extension ChargeStatus {
    var text: String {
        switch self {
        case let .charging(limit): limit >= Preferences.limitRange.upperBound ? L.statusChargingToFull : L.statusCharging(limit.percentText)
        case let .holding(limit): L.statusHolding(limit.percentText)
        case let .resting(level, _): L.statusResting(level.percentText)
        case let .draining(limit): L.statusDraining(limit.percentText)
        case let .usingBattery(limit): L.statusUsingBattery(limit.percentText)
        case .heatPaused: L.statusHeatPaused
        case .calibrating: L.statusCalibrating
        case .onBattery: L.statusOnBattery
        case .full: L.statusFull
        case .notCharging: L.statusNotCharging
        }
    }

    var symbol: String {
        switch self {
        case .charging: "bolt.fill"
        case .holding: "pause.fill"
        case .resting: "leaf.fill"
        case .draining, .usingBattery: "arrow.down"
        case .heatPaused: "flame.fill"
        case .calibrating: "arrow.clockwise"
        case .onBattery: "battery.100percent"
        case .full: "checkmark"
        case .notCharging: "powerplug.fill"
        }
    }

    var statusSymbol: StatusSymbol? {
        switch self {
        case .charging: .charging
        case .holding, .full, .notCharging: .limit
        case .resting: .resting
        case .draining, .usingBattery: .usingBattery
        case .heatPaused: .cooling
        case .calibrating: .calibrating
        case .onBattery: nil
        }
    }

    var tint: NSColor? {
        switch self {
        case .charging: .systemGreen
        case .resting: .systemTeal
        case .draining, .usingBattery: .systemYellow
        case .heatPaused: .systemOrange
        case .calibrating: .systemPurple
        default: nil
        }
    }

    var target: Int? {
        switch self {
        case let .charging(limit), let .draining(limit), let .usingBattery(limit): limit
        default: nil
        }
    }
}

extension StatusSymbol {
    var title: String {
        switch self {
        case .charging: L.symbolCharging
        case .limit: L.symbolLimit
        case .resting: L.symbolResting
        case .usingBattery: L.symbolUsingBattery
        case .cooling: L.symbolCooling
        case .calibrating: L.symbolCalibrating
        }
    }
}

extension EnergyMode {
    var title: String {
        switch self {
        case .automatic: L.energyAutomatic
        case .low: L.energyLow
        case .high: L.energyHigh
        }
    }
}
