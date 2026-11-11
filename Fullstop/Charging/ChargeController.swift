import Observation

@Observable
final class ChargeController {
    static let shared = ChargeController()

    private(set) var appliedLimit: Int?
    private(set) var errorMessage: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    private init() {}

    func apply(_ limit: Int) {
        task?.cancel()
        task = Task { await self.set(limit) }
    }

    private func set(_ limit: Int) async {
        do {
            if PowerUI.limits.contains(limit) {
                try PowerUI.shared.setLimit(limit)
            } else {
                try await HelperClient.shared.send(.setTopOffLimit(limit))
                try await Task.sleep(for: .seconds(3))
                BatteryMonitor.shared.refresh()
                if BatteryMonitor.shared.state.isCharging {
                    try await HelperClient.shared.send(.pulseAdapter)
                }
            }
            appliedLimit = limit
            errorMessage = nil
        } catch is CancellationError {
            return
        } catch HelperError.notInstalled {
            errorMessage = L.helperRequired
        } catch PowerUIError.unavailable {
            errorMessage = L.powerUIUnavailable
        } catch {
            errorMessage = L.limitFailed(String(describing: error))
        }
    }
}
