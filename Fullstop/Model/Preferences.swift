import Foundation
import Observation

@Observable
final class Preferences {
    static let shared = Preferences()
    static let limitRange = 20...100
    static let limitStep = 5

    @ObservationIgnored private let defaults = UserDefaults.standard

    var chargeLimit = 80 { didSet { store(chargeLimit, "chargeLimit") } }

    @ObservationIgnored private var loading = false

    private init() {
        load()
    }

    private func load() {
        loading = true
        defer { loading = false }
        let stored = defaults.object(forKey: "chargeLimit") as? Int ?? 80
        chargeLimit = min(max(stored, Self.limitRange.lowerBound), Self.limitRange.upperBound)
    }

    private func store(_ value: Any?, _ key: String) {
        guard !loading else { return }
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
