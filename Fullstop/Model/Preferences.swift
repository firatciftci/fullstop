import Foundation
import Observation

@Observable
final class Preferences {
    static let shared = Preferences()
    static let limitRange = 20...100
    static let limitStep = 5
    static let heatThresholds = Array(stride(from: 30, through: 45, by: 5))
    static let restDepths = Array(stride(from: 5, through: 20, by: 5))

    @ObservationIgnored private let defaults = DemoData.isEnabled ? DemoData.defaults : .standard

    var chargeLimit = 80 { didSet { store(chargeLimit, Key.chargeLimit) } }
    var heatProtection = false { didSet { store(heatProtection, Key.heatProtection) } }
    var heatThreshold = 35 { didSet { store(heatThreshold, Key.heatThreshold) } }
    var restEnabled = false { didSet { store(restEnabled, Key.restEnabled) } }
    var restDepth = 10 { didSet { store(restDepth, Key.restDepth) } }
    var magSafeLight = MagSafeLight.system { didSet { store(magSafeLight.rawValue, Key.magSafeLight) } }
    var iconStyle = IconStyle.modern { didSet { store(iconStyle.rawValue, Key.iconStyle) } }
    var showIcon = true { didSet { store(showIcon, Key.showIcon) } }
    var showPercentage = false { didSet { store(showPercentage, Key.showPercentage) } }
    var symbolsInside = true { didSet { store(symbolsInside, Key.symbolsInside) } }
    var statusSymbols = StatusSymbol.defaults { didSet { store(statusSymbols.map(\.rawValue).sorted(), Key.statusSymbols) } }
    var showLimitMarker = true { didSet { store(showLimitMarker, Key.showLimitMarker) } }
    var colorIcon = false { didSet { store(colorIcon, Key.colorIcon) } }

    var percentInside: Bool { iconStyle == .modern && showIcon }

    var hasStoredLimit: Bool { defaults.object(forKey: Key.chargeLimit) != nil }

    @ObservationIgnored private var loading = false

    private enum Key {
        static let chargeLimit = "chargeLimit"
        static let heatProtection = "heatProtection"
        static let heatThreshold = "heatThreshold"
        static let magSafeLight = "magSafeLight"
        static let restEnabled = "restEnabled"
        static let restDepth = "restDepth"
        static let iconStyle = "iconStyle"
        static let showIcon = "showIcon"
        static let showPercentage = "showPercentage"
        static let statusSymbols = "statusSymbols"
        static let symbolsInside = "symbolsInside"
        static let showLimitMarker = "showLimitMarker"
        static let colorIcon = "colorIcon"
    }

    private init() {
        load()
    }

    var restFloor: Int {
        max(Self.limitRange.lowerBound, chargeLimit - restDepth)
    }

    static func clamp(_ limit: Int) -> Int {
        min(max(limit, limitRange.lowerBound), limitRange.upperBound)
    }

    private func load() {
        loading = true
        defer { loading = false }
        chargeLimit = Self.clamp(defaults.object(forKey: Key.chargeLimit) as? Int ?? 80)
        heatProtection = defaults.bool(forKey: Key.heatProtection)
        let threshold = defaults.object(forKey: Key.heatThreshold) as? Int ?? 35
        heatThreshold = Self.heatThresholds.contains(threshold) ? threshold : 35
        restEnabled = defaults.bool(forKey: Key.restEnabled)
        let depth = defaults.object(forKey: Key.restDepth) as? Int ?? 10
        restDepth = Self.restDepths.contains(depth) ? depth : 10
        magSafeLight = (defaults.object(forKey: Key.magSafeLight) as? UInt8).flatMap(MagSafeLight.init) ?? .system
        iconStyle = defaults.string(forKey: Key.iconStyle).flatMap(IconStyle.init) ?? .modern
        showIcon = defaults.object(forKey: Key.showIcon) as? Bool ?? true
        showPercentage = defaults.bool(forKey: Key.showPercentage) || !showIcon
        symbolsInside = defaults.object(forKey: Key.symbolsInside) as? Bool ?? true
        statusSymbols =
            defaults.stringArray(forKey: Key.statusSymbols).map { Set($0.compactMap(StatusSymbol.init)) } ?? StatusSymbol.defaults
        showLimitMarker = defaults.object(forKey: Key.showLimitMarker) as? Bool ?? true
        colorIcon = defaults.bool(forKey: Key.colorIcon)
    }

    private func store(_ value: Any, _ key: String) {
        guard !loading else { return }
        defaults.set(value, forKey: key)
    }
}

nonisolated enum StatusSymbol: String, CaseIterable {
    case charging, limit, resting, usingBattery, cooling, calibrating

    static let defaults: Set<Self> = [.charging, .resting, .usingBattery, .cooling, .calibrating]

    var systemName: String {
        switch self {
        case .charging: "bolt.fill"
        case .limit: "powerplug.portrait.fill"
        case .resting: "leaf.fill"
        case .usingBattery: "arrowshape.down.fill"
        case .cooling: "flame.fill"
        case .calibrating: "arrow.clockwise"
        }
    }
}

nonisolated enum IconStyle: String {
    case modern, classic
}
