nonisolated enum HelperService {
    static let label = "com.firatciftci.Fullstop.helper"
    static let appIdentifier = "com.firatciftci.Fullstop"
    static let topOffLimits = 20...100
}

nonisolated enum MagSafeLight: UInt8, Codable, Sendable, CaseIterable {
    case system = 0
    case off = 1
    case green = 3
    case orange = 4
}

nonisolated enum HelperRequest: Codable, Sendable {
    case setAdapter(connected: Bool)
    case pulseAdapter
    case setLight(MagSafeLight)
    case setTopOffLimit(Int)
}

nonisolated struct HelperReply: Codable, Sendable {
    var error: String?
}
