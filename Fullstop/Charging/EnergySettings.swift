import Foundation
import Observation

private nonisolated struct EnergySnapshot {
    var modes = Array<EnergyMode>()
    var adapter: EnergyMode?
    var battery: EnergyMode?
}

@Observable
final class EnergySettings {
    static let shared = EnergySettings()

    private(set) var modes = Array<EnergyMode>()
    private(set) var adapterMode: EnergyMode?
    private(set) var batteryMode: EnergyMode?
    private(set) var isLowPowerMode = !DemoData.isEnabled && ProcessInfo.processInfo.isLowPowerModeEnabled

    @ObservationIgnored private var pending = 0
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    private init() {
        observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Self.shared.isLowPowerMode = !DemoData.isEnabled && ProcessInfo.processInfo.isLowPowerModeEnabled
                Self.shared.refresh()
            }
        }
    }

    func mode(onBattery: Bool) -> EnergyMode? { onBattery ? batteryMode : adapterMode }

    func refresh() {
        if DemoData.isEnabled {
            modes = EnergyMode.allCases
            adapterMode = .automatic
            batteryMode = .automatic
            return
        }
        Task {
            let snapshot = await Self.read()
            guard pending == 0 else { return }
            modes = snapshot.modes
            adapterMode = snapshot.adapter
            batteryMode = snapshot.battery
        }
    }

    func set(_ mode: EnergyMode, onBattery: Bool) {
        let previous = self.mode(onBattery: onBattery)
        store(mode, onBattery: onBattery)
        pending += 1
        Task {
            defer { pending -= 1 }
            do {
                try await HelperClient.shared.send(.setEnergyMode(mode, onBattery: onBattery))
            } catch {
                store(previous, onBattery: onBattery)
            }
        }
    }

    private func store(_ mode: EnergyMode?, onBattery: Bool) {
        if onBattery {
            batteryMode = mode
        } else {
            adapterMode = mode
        }
    }

    @concurrent private nonisolated static func read() async -> EnergySnapshot {
        let custom = pmset("-g", "custom")
        let capabilities = Set(pmset("-g", "cap").split(whereSeparator: \.isWhitespace).map(String.init))
        guard capabilities.contains("lowpowermode") else { return EnergySnapshot() }
        var modes: Array<EnergyMode> = [.automatic, .low]
        if capabilities.contains("highpowermode") { modes.append(.high) }

        var section = ""
        var values = Dictionary<String, EnergyMode>()
        for line in custom.split(separator: "\n") {
            if line.hasSuffix(":") {
                section = String(line.dropLast())
                continue
            }
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count == 2, let value = Int(fields[1]) else { continue }
            switch fields[0] {
            case "powermode": values[section] = EnergyMode(rawValue: value)
            case "lowpowermode" where values[section] == nil: values[section] = value == 1 ? .low : .automatic
            default: break
            }
        }
        return EnergySnapshot(modes: modes, adapter: values["AC Power"], battery: values["Battery Power"])
    }

    private nonisolated static func pmset(_ arguments: String...) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return "" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
