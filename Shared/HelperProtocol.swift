nonisolated enum HelperService {
    static let label = "com.firatciftci.Fullstop.helper"
    static let appIdentifier = "com.firatciftci.Fullstop"
    static let topOffLimits = 20...100
    static let lightKey = "ACLC"
}

nonisolated enum MagSafeLight: UInt8, Codable, Sendable, CaseIterable {
    case system = 0
    case off = 1
}

nonisolated enum EnergyMode: Int, Codable, Sendable, CaseIterable {
    case automatic = 0
    case low = 1
    case high = 2
}

nonisolated enum HelperRequest: Codable, Sendable {
    case setAdapter(connected: Bool)
    case pulseAdapter
    case setLight(MagSafeLight)
    case setTopOffLimit(Int)
    case setEnergyMode(EnergyMode, onBattery: Bool)
}

nonisolated struct HelperReply: Codable, Sendable {
    var error: String?
}
