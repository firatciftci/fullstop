import AppIntents

struct SetChargeLimitIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Charge Limit"
    static let description: IntentDescription? = IntentDescription("Sets the highest charge your battery reaches while plugged in.")

    @Parameter(title: "Limit", inclusiveRange: (20, 100))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set charge limit to \(\.$limit)")
    }

    @MainActor func perform() -> some IntentResult & ProvidesDialog {
        ChargeController.shared.setLimit(limit)
        let text = Preferences.shared.chargeLimit.percentText
        return .result(dialog: "Charge limit set to \(text).")
    }
}

struct ChargeToFullIntent: AppIntent {
    static let title: LocalizedStringResource = "Charge to Full"
    static let description: IntentDescription? = IntentDescription("Charges to 100% once. Your limit comes back when you unplug.")

    @MainActor func perform() -> some IntentResult & ProvidesDialog {
        ChargeController.shared.setChargingToFull(true)
        return .result(dialog: "Charging to 100%.")
    }
}

struct BatteryStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Battery Status"
    static let description: IntentDescription? = IntentDescription("Returns the battery level and what Fullstop is doing.")

    @MainActor func perform() -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        BatteryMonitor.shared.refresh()
        let percent = BatteryMonitor.shared.state.percent
        let summary = [percent.percentText, ChargeController.shared.status.text].joined(separator: ", ")
        return .result(value: percent, dialog: "\(summary)")
    }
}

nonisolated struct FullstopShortcuts: AppShortcutsProvider {
    static var appShortcuts: Array<AppShortcut> {
        AppShortcut(
            intent: SetChargeLimitIntent(),
            phrases: ["Set the charge limit in \(.applicationName)"],
            shortTitle: "Set Charge Limit",
            systemImageName: "battery.75percent"
        )
        AppShortcut(
            intent: ChargeToFullIntent(),
            phrases: ["Charge to Full with \(.applicationName)"],
            shortTitle: "Charge to Full",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: BatteryStatusIntent(),
            phrases: ["Get the battery status from \(.applicationName)"],
            shortTitle: "Get Battery Status",
            systemImageName: "battery.100percent"
        )
    }
}
