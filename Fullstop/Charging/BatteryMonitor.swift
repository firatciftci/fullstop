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
    var temperature = 0.0
    var voltage = 0.0
    var amperage = 0.0
    var maximumCapacity = 0
    var designCapacity = 0
    var adapterWatts: Int?
}

@Observable
final class BatteryMonitor {
    static let shared = BatteryMonitor()

    private(set) var state = BatteryState()

    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var timer: Timer?

    private init() {}

    func start() {
        refresh()
        guard source == nil else { return }
        if let source = IOPSNotificationCreateRunLoopSource(powerSourceChanged, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = source
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { Self.shared.refresh() }
        }
    }

    func refresh() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let values = properties?.takeRetainedValue() as? [String: Any]
        else { return }
        func int(_ key: String) -> Int { values[key] as? Int ?? 0 }
        func bool(_ key: String) -> Bool { values[key] as? Bool ?? false }
        let adapter = values["AdapterDetails"] as? [String: Any]
        let next = BatteryState(
            percent: int("CurrentCapacity"),
            isCharging: bool("IsCharging"),
            isPluggedIn: bool("ExternalConnected"),
            isFullyCharged: bool("FullyCharged"),
            cycleCount: int("CycleCount"),
            temperature: Double(int("Temperature")) / 100,
            voltage: Double(int("Voltage")) / 1_000,
            amperage: Double(int("InstantAmperage")) / 1_000,
            maximumCapacity: int("AppleRawMaxCapacity"),
            designCapacity: int("DesignCapacity"),
            adapterWatts: adapter?["Watts"] as? Int
        )
        if next != state { state = next }
    }
}

nonisolated private func powerSourceChanged(_: UnsafeMutableRawPointer?) {
    MainActor.assumeIsolated { BatteryMonitor.shared.refresh() }
}
