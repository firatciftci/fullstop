import Charts
import SwiftUI

struct HistoryChart: View {
    let samples: Array<BatterySample>
    let current: Int
    let limit: Int

    @State private var hovered: BatterySample?

    private static let minimumSpan: TimeInterval = 15 * 60
    private let height: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.historyTitle)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(caption)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .accessibilityHidden(true)
            if let range {
                chart(range)
            } else {
                Text(L.historyEmpty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: height)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var points: Array<BatterySample> {
        guard current > 0, let last = samples.last, last.date < .now else { return samples }
        return samples + [BatterySample(date: .now, percent: current)]
    }

    private var range: ClosedRange<Date>? {
        guard let first = samples.first, Date.now.timeIntervalSince(first.date) >= Self.minimumSpan else { return nil }
        return first.date...Date.now
    }

    private var caption: String {
        if let hovered {
            return L.historyPoint(hovered.percent.percentText, hovered.date.formatted(date: .omitted, time: .shortened))
        }
        guard let range else { return "" }
        if Date.now.timeIntervalSince(range.lowerBound) > BatteryHistory.window - 30 * 60 {
            return L.historyLastDay
        }
        return L.historySince(range.lowerBound.formatted(date: .omitted, time: .shortened))
    }

    private func chart(_ range: ClosedRange<Date>) -> some View {
        Chart {
            ForEach(points) { sample in
                AreaMark(x: .value("Time", sample.date), y: .value("Level", sample.percent))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Color.primary.opacity(0.2), Color.primary.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", sample.date), y: .value("Level", sample.percent))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
            if limit < Preferences.limitRange.upperBound {
                RuleMark(xStart: .value("Start", range.lowerBound), xEnd: .value("End", range.upperBound), y: .value("Limit", limit))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(Color.green.opacity(0.8))
            }
            if let hovered {
                RuleMark(x: .value("Time", hovered.date))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                PointMark(x: .value("Time", hovered.date), y: .value("Level", hovered.percent))
                    .symbolSize(28)
                    .foregroundStyle(Color.primary)
            }
        }
        .chartXScale(domain: range)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            guard let plot = proxy.plotFrame else { return }
                            let date: Date? = proxy.value(atX: location.x - geometry[plot].origin.x)
                            hovered = date.flatMap(nearest)
                        case .ended:
                            hovered = nil
                        }
                    }
            }
        }
        .frame(height: height)
        .accessibilityLabel(L.historyLabel)
    }

    private func nearest(to date: Date) -> BatterySample? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}
