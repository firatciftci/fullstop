import CoreFoundation
import Foundation

enum Hardware {
    private static let adapterKey = "CHIE"
    private static let lightKey = "ACLC"
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
        try SMC().write(lightKey, [light.rawValue])
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
