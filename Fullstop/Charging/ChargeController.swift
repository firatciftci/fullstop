import AppKit
import Observation
import notify

enum ChargeStatus: Equatable {
    case charging(to: Int)
    case holding(at: Int)
    case resting(at: Int, until: Int)
    case draining(to: Int)
    case usingBattery(to: Int)
    case heatPaused
    case calibrating
    case onBattery
    case full
    case notCharging
}

@Observable
final class ChargeController {
    static let shared = ChargeController()

    private(set) var isChargingToFull = false
    private(set) var isUsingBattery = false
    private(set) var heatPauseLimit: Int?
    private(set) var restLimit: Int?
    private(set) var isCalibrating = false
    private(set) var errorMessage: String?
    private(set) var appliedLimit: Int?

    @ObservationIgnored private var appliedLight = MagSafeLight.system
    @ObservationIgnored private var adapterCut = false
    @ObservationIgnored private var wasPluggedIn = false
    @ObservationIgnored private var restRecharging = false
    @ObservationIgnored private var running = false
    @ObservationIgnored private var rerun = false
    @ObservationIgnored private var calibrationToken: Int32 = -1
    @ObservationIgnored private var observers = Array<any NSObjectProtocol>()

    private static let calibrationNotification = "com.apple.system.powersources.chargingtofulloverride"
    static let heatHysteresis = 3
    private static let pendingLimitDelay = Duration.seconds(3)

    private init() {}

    private var battery: BatteryState { BatteryMonitor.shared.state }
    private var prefs: Preferences { Preferences.shared }
    private var helper: HelperClient { HelperClient.shared }

    var activeLimit: Int { appliedLimit ?? effectiveLimit }

    var effectiveLimit: Int {
        if isChargingToFull { return Preferences.limitRange.upperBound }
        return heatPauseLimit ?? restLimit ?? prefs.chargeLimit
    }

    var displayLimit: Int { restLimit == nil ? activeLimit : prefs.chargeLimit }

    var restFloor: Int? {
        guard prefs.restEnabled, helper.isReady, prefs.chargeLimit < Preferences.limitRange.upperBound else { return nil }
        return prefs.restFloor
    }

    var canUseBattery: Bool {
        isUsingBattery || (helper.isReady && battery.isPluggedIn && battery.percent > prefs.chargeLimit && !isCalibrating)
    }

    var status: ChargeStatus {
        let state = battery
        if isCalibrating, state.isPluggedIn { return .calibrating }
        if isUsingBattery { return .usingBattery(to: prefs.chargeLimit) }
        if !state.isPluggedIn { return .onBattery }
        let limit = activeLimit
        let isCharging = state.isCharging && state.percent < limit
        if heatPauseLimit != nil, !isCharging { return .heatPaused }
        if restLimit != nil, let restFloor, !isCharging, state.percent <= prefs.chargeLimit {
            return .resting(at: state.percent, until: restFloor)
        }
        if isCharging { return .charging(to: limit) }
        if !state.isCharging, state.percent > limit { return .draining(to: limit) }
        if state.isFullyCharged || state.percent >= Preferences.limitRange.upperBound { return .full }
        if limit < Preferences.limitRange.upperBound, state.percent >= limit - 2 { return .holding(at: limit) }
        return .notCharging
    }

    var minutesRemaining: Int? {
        switch status {
        case .onBattery: battery.minutesToEmpty
        case let .charging(limit), let .draining(limit), let .usingBattery(limit): battery.minutes(to: limit)
        default: nil
        }
    }

    func start() {
        if !prefs.hasStoredLimit, let native = try? PowerUI.shared.limit() {
            prefs.chargeLimit = Preferences.clamp(native)
        }
        helper.onDisconnect = { [weak self] in self?.helperDisconnected() }
        watchCalibration()
        watchSleep()
        trackChanges { [weak self] in
            guard let self else { return }
            _ = (
                battery, prefs.chargeLimit, prefs.heatProtection, prefs.heatThreshold, prefs.restEnabled, prefs.restDepth,
                prefs.magSafeLight, helper.status
            )
            schedule()
        }
    }

    func setLimit(_ limit: Int) {
        prefs.chargeLimit = Preferences.clamp(limit)
        isChargingToFull = false
        restLimit = nil
        restRecharging = false
        schedule()
    }

    func setChargingToFull(_ enabled: Bool) {
        isChargingToFull = enabled
        if enabled {
            isUsingBattery = false
            try? PowerUI.shared.overrideOptimizedCharging()
        }
        wasPluggedIn = battery.isPluggedIn
        schedule()
    }

    func setUsingBattery(_ enabled: Bool) {
        isUsingBattery = enabled && canUseBattery
        if isUsingBattery { isChargingToFull = false }
        schedule()
    }

    func prepareToQuit() async {
        isChargingToFull = false
        await settle()
        if let appliedLimit, appliedLimit != prefs.chargeLimit {
            try? await write(prefs.chargeLimit)
        }
        await releaseHardware()
        helper.disconnect()
    }

    func removeHelper() async {
        await settle()
        let target = max(prefs.chargeLimit, PowerUI.limits.lowerBound)
        if !isChargingToFull, appliedLimit != target, (try? await write(target)) != nil {
            appliedLimit = target
        }
        prefs.chargeLimit = target
        await releaseHardware()
        await helper.uninstall()
    }

    private func settle() async {
        isUsingBattery = false
        heatPauseLimit = nil
        restLimit = nil
        restRecharging = false
        while running {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func releaseHardware() async {
        if adapterCut, (try? await helper.send(.setAdapter(connected: true))) != nil {
            adapterCut = false
        }
        if appliedLight != .system, (try? await helper.send(.setLight(.system))) != nil {
            appliedLight = .system
        }
    }

    private func schedule() {
        guard !DemoData.isEnabled else { return }
        guard !running else {
            rerun = true
            return
        }
        running = true
        Task {
            repeat {
                rerun = false
                await reconcile()
            } while rerun
            running = false
        }
    }

    private func reconcile() async {
        let state = battery
        updateModes(for: state)
        adoptExternalLimit()
        do {
            try await applyLimit(for: state)
            try await applyAdapter(for: state)
            try await applyLight()
            if errorMessage != nil { errorMessage = nil }
        } catch {
            if appliedLimit == nil { appliedLimit = try? PowerUI.shared.limit() }
            errorMessage = Self.message(for: error)
        }
    }

    private func updateModes(for state: BatteryState) {
        if !isUsingBattery {
            if isChargingToFull, wasPluggedIn, !state.isPluggedIn { isChargingToFull = false }
            wasPluggedIn = state.isPluggedIn
        }
        if isUsingBattery, state.percent <= prefs.chargeLimit || !helper.isReady || isCalibrating {
            isUsingBattery = false
        }
        updateHeat(for: state)
        updateRest(for: state)
    }

    private func updateHeat(for state: BatteryState) {
        guard prefs.heatProtection, helper.isReady, !isChargingToFull, !isCalibrating, let temperature = state.temperature else {
            heatPauseLimit = nil
            return
        }
        let threshold = Double(prefs.heatThreshold)
        if let paused = heatPauseLimit {
            if temperature <= threshold - Double(Self.heatHysteresis) || !state.isPluggedIn || paused >= prefs.chargeLimit {
                heatPauseLimit = nil
            }
        } else if temperature >= threshold, state.isPluggedIn, state.percent < prefs.chargeLimit {
            heatPauseLimit = max(Preferences.limitRange.lowerBound, state.percent)
        }
    }

    private func updateRest(for state: BatteryState) {
        guard let floor = restFloor, !isChargingToFull, !isUsingBattery, !isCalibrating, heatPauseLimit == nil else {
            restLimit = nil
            restRecharging = false
            return
        }
        guard state.isPluggedIn else {
            restRecharging = false
            return
        }
        let limit = prefs.chargeLimit
        if restRecharging {
            guard state.percent >= limit else { return }
            restRecharging = false
        } else if state.percent <= floor {
            restRecharging = true
            restLimit = nil
            return
        }
        restLimit = min(restLimit ?? limit, state.percent, limit)
    }

    private func adoptExternalLimit() {
        guard !isChargingToFull, heatPauseLimit == nil, restLimit == nil, let appliedLimit, let native = try? PowerUI.shared.limit(),
            native != appliedLimit, Preferences.limitRange.contains(native)
        else { return }
        self.appliedLimit = native
        prefs.chargeLimit = native
    }

    private func applyLimit(for state: BatteryState) async throws {
        let target = effectiveLimit
        guard target != appliedLimit else { return }
        if appliedLimit == nil, (try? PowerUI.shared.limit()) == target {
            appliedLimit = target
            return
        }
        try await write(target)
        appliedLimit = target
        guard helper.isReady, state.isPluggedIn, state.percent >= target, target < Preferences.limitRange.upperBound else { return }
        try await Task.sleep(for: Self.pendingLimitDelay)
        BatteryMonitor.shared.refresh()
        if battery.isCharging {
            try await helper.send(.pulseAdapter)
        }
    }

    private func applyAdapter(for state: BatteryState) async throws {
        let cut = isUsingBattery
        guard cut != adapterCut || (cut && state.amperage > -0.1) else { return }
        try await helper.send(.setAdapter(connected: !cut))
        adapterCut = cut
    }

    private func applyLight() async throws {
        let light = BatteryMonitor.shared.hasMagSafeLight && helper.isReady ? prefs.magSafeLight : .system
        guard light != appliedLight else { return }
        try await helper.send(.setLight(light))
        appliedLight = light
    }

    private func write(_ limit: Int) async throws {
        if PowerUI.steps.contains(limit) {
            try PowerUI.shared.setLimit(limit)
        } else {
            try await helper.send(.setTopOffLimit(limit))
        }
    }

    private func helperDisconnected() {
        adapterCut = false
        isUsingBattery = false
        appliedLight = .system
        schedule()
    }

    private func watchCalibration() {
        let status = notify_register_dispatch(Self.calibrationNotification, &calibrationToken, .main) { token in
            MainActor.assumeIsolated { Self.shared.readCalibration(token) }
        }
        if status == NOTIFY_STATUS_OK { readCalibration(calibrationToken) }
    }

    private func readCalibration(_ token: Int32) {
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else { return }
        let calibrating = state != 0
        guard calibrating != isCalibrating else { return }
        isCalibrating = calibrating
        schedule()
    }

    private func watchSleep() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Self.shared.setUsingBattery(false) }
            })
        observers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    Self.shared.appliedLight = .system
                    BatteryMonitor.shared.refresh()
                    Self.shared.schedule()
                }
            })
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case HelperError.notInstalled: L.helperRequired
        case PowerUIError.unavailable: L.powerUIUnavailable
        case let HelperError.failed(reason), let PowerUIError.failed(reason): L.limitFailed(reason)
        default: L.limitFailed(error.localizedDescription)
        }
    }
}
