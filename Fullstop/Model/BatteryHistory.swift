import Foundation
import Observation

struct BatterySample: Codable, Equatable, Identifiable {
    var date: Date
    var percent: Int

    var id: Date { date }
}

@Observable
final class BatteryHistory {
    static let shared = BatteryHistory()
    static let window: TimeInterval = 24 * 60 * 60

    private(set) var samples = Array<BatterySample>()

    @ObservationIgnored private let interval: TimeInterval = 5 * 60
    @ObservationIgnored private let url: URL? = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
        .appending(path: "Fullstop", directoryHint: .isDirectory)
        .appending(path: "history.json")

    private init() {
        if DemoData.isEnabled {
            samples = DemoData.history()
            return
        }
        guard let url, let data = try? Data(contentsOf: url),
            let stored = try? JSONDecoder().decode(Array<BatterySample>.self, from: data)
        else { return }
        samples = stored.filter { $0.date.timeIntervalSinceNow > -Self.window }
    }

    func record(_ percent: Int, at date: Date = .now) {
        guard percent > 0, !DemoData.isEnabled else { return }
        if let last = samples.last, last.percent == percent, date.timeIntervalSince(last.date) < interval { return }
        samples.append(BatterySample(date: date, percent: percent))
        if let first = samples.first, date.timeIntervalSince(first.date) > Self.window {
            samples.removeAll { date.timeIntervalSince($0.date) > Self.window }
        }
        save()
    }

    private func save() {
        guard let url, let data = try? JSONEncoder().encode(samples) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
