import AppKit
import SwiftUI

struct ChargeTrack: View {
    let level: Int
    let limit: Int
    let restDepth: Int?
    let fill: Color
    let onChange: (Int) -> Void
    let onCommit: (Int) -> Void

    @State private var dragging = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackHeight: CGFloat = 22
    private let fillRadius: CGFloat = 3
    private let stopSize = CGSize(width: 8, height: 30)
    private let range = Preferences.limitRange
    private let step = Preferences.limitStep

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let limitX = position(of: limit, in: width)
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.quaternary)
                    if let floor = restFloor {
                        let floorX = position(of: floor, in: width)
                        Rectangle()
                            .fill(fill.opacity(0.22))
                            .frame(width: max(limitX - floorX, 0))
                            .offset(x: floorX)
                            .transition(.opacity)
                    }
                    UnevenRoundedRectangle(bottomTrailingRadius: fillRadius, topTrailingRadius: fillRadius, style: .continuous)
                        .fill(fill.gradient)
                        .frame(width: max(position(of: level, in: width), fillRadius * 2))
                        .opacity(level > 0 ? 1 : 0)
                    if limit < range.upperBound {
                        Hatching()
                            .foregroundStyle(.primary.opacity(0.12))
                            .frame(width: width - limitX)
                            .offset(x: limitX)
                    }
                }
                .frame(height: trackHeight)
                .clipShape(Capsule())
                if let floor = restFloor {
                    Capsule()
                        .fill(level > floor ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                        .frame(width: 2, height: trackHeight - 10)
                        .offset(x: position(of: floor, in: width) - 1)
                        .transition(.opacity)
                }
                Capsule()
                    .fill(.white)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.28), radius: dragging ? 4 : 2, y: 1)
                    .frame(width: stopSize.width, height: stopSize.height)
                    .scaleEffect(dragging && !reduceMotion ? 1.12 : 1)
                    .offset(x: limitX - stopSize.width / 2)
            }
            .frame(height: stopSize.height)
            .contentShape(Rectangle())
            .gesture(drag(width: width))
            .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.2), value: dragging)
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: level)
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: restFloor)
        }
        .frame(height: stopSize.height)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay {
            Capsule()
                .strokeBorder(Color.accentColor.opacity(focused && NSApp.isFullKeyboardAccessEnabled ? 0.8 : 0), lineWidth: 3)
                .frame(height: trackHeight + 6)
        }
        .onKeyPress(keys: [.leftArrow, .downArrow, .rightArrow, .upArrow]) { press in
            let delta = press.key == .leftArrow || press.key == .downArrow ? -step : step
            commit(limit + delta)
            return .handled
        }
        .accessibilityRepresentation {
            Slider(
                value: Binding {
                    Double(limit)
                } set: {
                    commit(Int($0))
                },
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            ) {
                Text(L.chargeLimit)
            }
            .accessibilityValue(limit >= range.upperBound ? L.chargeLimitOff : limit.percentText)
        }
    }

    private var restFloor: Int? {
        guard let restDepth, limit < range.upperBound else { return nil }
        return max(range.lowerBound, limit - restDepth)
    }

    private func position(of value: Int, in width: CGFloat) -> CGFloat {
        let inset = stopSize.width / 2
        return inset + (width - inset * 2) * CGFloat(min(max(value, 0), 100)) / 100
    }

    private func value(at x: CGFloat, in width: CGFloat) -> Int {
        let inset = stopSize.width / 2
        let raw = Double((x - inset) / (width - inset * 2)) * 100
        let snapped = Int((raw / Double(step)).rounded()) * step
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                dragging = true
                let next = value(at: gesture.location.x, in: width)
                guard next != limit else { return }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                onChange(next)
            }
            .onEnded { gesture in
                dragging = false
                commit(value(at: gesture.location.x, in: width))
            }
    }

    private func commit(_ value: Int) {
        onCommit(min(max(value, range.lowerBound), range.upperBound))
    }
}

private nonisolated struct Hatching: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let spacing: CGFloat = 5
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path.strokedPath(StrokeStyle(lineWidth: 1.5))
    }
}
