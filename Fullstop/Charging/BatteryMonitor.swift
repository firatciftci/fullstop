import Foundation
import IOKit
import IOKit.ps
import Observation

struct BatteryState: Equatable {
    var percent = 0
    var isCharging = false
    var isPluggedIn = false
    var isFullyCharged = false
    var cycleCount = 0
    var temperature: Double?
    var voltage = 0.0
    var amperage = 0.0
    var maximumCapacity = 0
    var designCapacity = 0
    var adapterWatts: Int?
    var powerIn = 0.0
    var systemLoad = 0.0
    var minutesToEmpty: Int?

    var batteryPower: Double { voltage * amperage }

    var health: Int? {
        guard designCapacity > 0, maximumCapacity > 0 else { return nil }
        return min(100, Int((Double(maximumCapacity) / Double(designCapacity) * 100).rounded()))
    }

    func minutes(to limit: Int) -> Int? {
        let milliamps = abs(amperage) * 1_000
        guard milliamps > 50, maximumCapacity > 0, limit != percent else { return nil }
        let milliampHours = Double(abs(limit - percent)) / 100 * Double(maximumCapacity)
        return Int((milliampHours / milliamps * 60).rounded())
    }
}

@Observable
final class BatteryMonitor {
    static let shared = BatteryMonitor()

    private(set) var state = BatteryState()
    private(set) var hasMagSafeLight = false

    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let smc = try? SMC()
    @ObservationIgnored private var temperatureKeys = Array<String>()

    private init() {}

    func start() {
        if DemoData.isEnabled {
            state = DemoData.battery
            hasMagSafeLight = true
            return
        }
        if let smc {
            temperatureKeys = ["TB0T", "TB1T", "TB2T"].filter(smc.hasKey)
            hasMagSafeLight = smc.hasKey(HelperService.lightKey)
        }
        refresh()
        guard source == nil else { return }
        if let source = IOPSNotificationCreateRunLoopSource(powerSourceChanged, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = source
        }
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated {
                Self.shared.refresh()
                HelperClient.shared.refresh()
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard !DemoData.isEnabled else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let values = properties?.takeRetainedValue() as? [String: Any]
        else { return }
        let data = values["BatteryData"] as? [String: Any] ?? [:]
        let telemetry = values["PowerTelemetryData"] as? [String: Any] ?? [:]
        let adapter = values["AdapterDetails"] as? [String: Any]
        func int(_ key: String, in dictionary: [String: Any] = values) -> Int { dictionary[key] as? Int ?? 0 }
        func bool(_ key: String) -> Bool { values[key] as? Bool ?? false }
        let pluggedIn = bool("ExternalConnected")
        let timeToEmpty = int("AvgTimeToEmpty")
        let next = BatteryState(
            percent: int("CurrentCapacity"),
            isCharging: bool("IsCharging"),
            isPluggedIn: pluggedIn,
            isFullyCharged: bool("FullyCharged"),
            cycleCount: int("CycleCount"),
            temperature: readTemperature(),
            voltage: Double(int("Voltage")) / 1_000,
            amperage: Double(int("InstantAmperage")) / 1_000,
            maximumCapacity: int("AppleRawMaxCapacity", in: data),
            designCapacity: int("DesignCapacity", in: data),
            adapterWatts: pluggedIn ? adapter?["Watts"] as? Int : nil,
            powerIn: Double(int("SystemPowerIn", in: telemetry)) / 1_000,
            systemLoad: Double(int("SystemLoad", in: telemetry)) / 1_000,
            minutesToEmpty: !pluggedIn && timeToEmpty > 0 && timeToEmpty < 65_535 ? timeToEmpty : nil
        )
        if next != state { state = next }
        BatteryHistory.shared.record(next.percent)
    }

    private func readTemperature() -> Double? {
        guard let smc else { return nil }
        var hottest: Double?
        for key in temperatureKeys {
            guard let value = try? smc.float(key), value > 0, value < 100 else { continue }
            hottest = max(hottest ?? 0, (Double(value) * 10).rounded() / 10)
        }
        return hottest
    }
}

nonisolated private func powerSourceChanged(_: UnsafeMutableRawPointer?) {
    MainActor.assumeIsolated { BatteryMonitor.shared.refresh() }
}
