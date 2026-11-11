import CoreFoundation
import Foundation
import IOKit
import IOKit.pwr_mgt
import Synchronization

enum Hardware {
    private static let adapterKey = "CHIE"
    private static let adapterCut: UInt8 = 0x08
    private static let pulseDuration: TimeInterval = 2

    static func setAdapter(connected: Bool) throws {
        try SMC().write(adapterKey, [connected ? 0 : adapterCut])
    }

    static func pulseAdapter() throws {
        try setAdapter(connected: false)
        defer { restoreAdapter() }
        Thread.sleep(forTimeInterval: pulseDuration)
    }

    static func restoreAdapter() {
        try? setAdapter(connected: true)
    }

    static func setLight(_ light: MagSafeLight) throws {
        try SMC().write(HelperService.lightKey, [light.rawValue])
    }
}

enum TopOff {
    private static let domain = "com.apple.smartcharging.topoffprotection"
    private static let notification = "com.apple.smartcharging.defaultschanged"
    private static let clearedKeys = ["checkpoint", "currentState", "MCLTempDisabledUntilDate"]

    static func apply(limit: Int) throws {
        guard HelperService.topOffLimits.contains(limit) else {
            throw SMCError(description: "\(limit) is outside \(HelperService.topOffLimits)")
        }
        set("mclLimitValue", limit as CFNumber)
        set("MCLFeatureState", 1 as CFNumber)
        for key in clearedKeys {
            set(key, nil)
        }
        guard CFPreferencesSynchronize(domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw SMCError(description: "Couldn't save the charge limit")
        }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(notification as CFString), nil, nil, true)
    }

    private static func set(_ key: String, _ value: CFPropertyList?) {
        CFPreferencesSetValue(key as CFString, value, domain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
}

enum Energy {
    static func apply(_ mode: EnergyMode, onBattery: Bool) throws {
        let source = onBattery ? "-b" : "-c"
        if (try? pmset(source, "powermode", mode.rawValue)) != nil { return }
        guard mode != .high else { throw SMCError(description: "This Mac doesn't support High Power") }
        try pmset(source, "lowpowermode", mode == .low ? 1 : 0)
    }

    private static func pmset(_ source: String, _ key: String, _ value: Int) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = [source, key, String(value)]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw SMCError(description: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

enum SleepWatcher {
    private static let canSleep: natural_t = 0xE000_0270
    private static let willSleep: natural_t = 0xE000_0280
    private static let rootPort = Mutex<io_connect_t>(0)

    static func start() {
        var notifyPort: IONotificationPortRef?
        var notifier: io_object_t = 0
        let port = IORegisterForSystemPower(
            nil, &notifyPort,
            { _, _, message, argument in
                Self.handle(message, argument)
            }, &notifier)
        guard port != 0, let notifyPort else { return }
        rootPort.withLock { $0 = port }
        IONotificationPortSetDispatchQueue(notifyPort, .main)
    }

    private static func handle(_ message: natural_t, _ argument: UnsafeMutableRawPointer?) {
        guard message == canSleep || message == willSleep else { return }
        if message == willSleep { Hardware.restoreAdapter() }
        IOAllowPowerChange(rootPort.withLock { $0 }, Int(bitPattern: argument))
    }
}
