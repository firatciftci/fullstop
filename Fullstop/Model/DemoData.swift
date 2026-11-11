import AppKit

enum DemoData {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-demo")

    static let appearance: NSAppearance.Name? = {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-dark") { return .darkAqua }
        if arguments.contains("-light") { return .aqua }
        return nil
    }()

    static let defaults: UserDefaults = {
        let name = "com.firatciftci.Fullstop.demo"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        defaults.set(80, forKey: "chargeLimit")
        defaults.set(true, forKey: "heatProtection")
        defaults.set(true, forKey: "restEnabled")
        return defaults
    }()

    static let battery = BatteryState(
        percent: 64,
        isCharging: true,
        isPluggedIn: true,
        isFullyCharged: false,
        cycleCount: 112,
        temperature: 31.4,
        voltage: 12.4,
        amperage: 2.9,
        maximumCapacity: 8_120,
        designCapacity: 8_579,
        adapterWatts: 96,
        powerIn: 58.4,
        systemLoad: 22.4,
        minutesToEmpty: nil
    )

    static func history(until now: Date = .now) -> Array<BatterySample> {
        let points: Array<(hours: Double, percent: Int)> = [
            (24, 80), (16, 80), (15, 77), (14, 71), (13, 64), (12, 58), (11, 51), (10, 47), (9.5, 44), (9, 42),
            (8.5, 48), (8, 55), (7.5, 62), (7, 69), (6.5, 75), (6, 80), (3, 80), (2.5, 76), (2, 70), (1.5, 66),
            (1, 61), (0.5, 62), (0, battery.percent),
        ]
        var samples = Array<BatterySample>()
        for point in points {
            samples.append(BatterySample(date: now.addingTimeInterval(-point.hours * 3_600), percent: point.percent))
        }
        return samples
    }
}
