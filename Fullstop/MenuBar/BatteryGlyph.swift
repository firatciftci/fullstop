import AppKit

nonisolated struct GlyphStyle {
    var tint: NSColor?
    var showsBattery = true
    var symbolInside = false
    var modern = true
    var percentInside = false
}

nonisolated enum BatteryGlyph {
    private static let symbolGap = 3.0
    private static var besideConfiguration: NSImage.SymbolConfiguration { .init(pointSize: 11, weight: .semibold) }

    static func image(percent: Int, limit: Int?, symbol: String?, style: GlyphStyle) -> NSImage? {
        let mark = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        guard style.showsBattery || mark != nil else { return nil }
        let inside = style.symbolInside && style.showsBattery
        let beside = inside ? nil : mark
        let besideSize = beside?.withSymbolConfiguration(besideConfiguration)?.size ?? .zero
        let besideWidth = beside == nil ? 0 : (besideSize.width + (style.showsBattery ? symbolGap : 0)).rounded(.up)
        let canvas = style.showsBattery ? Canvas(percent: percent, limit: limit, style: style, symbol: inside ? symbol : nil) : nil
        let batterySize = canvas?.size ?? .zero
        let size = NSSize(
            width: besideWidth + batterySize.width.rounded(.up), height: max(batterySize.height, besideSize.height.rounded(.up)))
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            if let beside,
                let colored = beside.withSymbolConfiguration(
                    besideConfiguration.applying(.init(paletteColors: [style.tint ?? canvas?.ink ?? .black])))
            {
                colored.draw(in: NSRect(x: 0, y: (size.height - besideSize.height) / 2, width: besideSize.width, height: besideSize.height))
            }
            guard let canvas else { return true }
            context.translateBy(x: besideWidth, y: ((size.height - batterySize.height) / 2).rounded())
            canvas.draw(in: context)
            return true
        }
        image.isTemplate = style.tint == nil
        return image
    }
}

private nonisolated struct Canvas {
    let percent: Int
    let limit: Int?
    let tint: NSColor?
    let modern: Bool
    let mark: NSImage?
    let text: CTLine?
    private let textInk: CGRect
    private let markInk: NSRect

    private static let classicSize = NSSize(width: 27, height: 13)
    private static let classicBody = NSRect(x: 0.5, y: 1.5, width: 23, height: 10)
    private static let classicWell = NSRect(x: 2, y: 3, width: 20, height: 7)
    private static let modernHeight = 12.0
    private static let modernRadius = 3.875
    private static let modernMinimumWidth = 23.0
    private static let modernPadding = 3.2
    private static let markGap = 1.25
    private static let markMaximumWidth = 7.5
    private static let baseline = 2.5
    private static let capGap = 1.0
    private static let cap = NSRect(x: 0, y: 4, width: 1.5, height: 4)
    private static let capRadius = 1.25
    private static let dimAlpha = 0.5
    private static let capAlpha = 0.6
    private static let markerOverhang = 2.0
    private static var digitFont: NSFont { .systemFont(ofSize: 10.125, weight: .medium) }
    private static let outlineAlpha = 0.45
    private static let haloRadius = 0.85

    init(percent: Int, limit: Int?, style: GlyphStyle, symbol: String?) {
        self.percent = percent
        self.limit = limit.flatMap { $0 < 100 ? $0 : nil }
        tint = style.tint
        modern = style.modern
        let ink = style.tint == nil ? NSColor.black : NSColor.labelColor
        let showsText = style.modern && style.percentInside
        let (pointSize, weight): (Double, NSFont.Weight) =
            switch (style.modern, showsText) {
            case (false, _): (6.5, .bold)
            case (true, true): (7.25, symbol?.hasSuffix(".fill") == false ? .heavy : .light)
            case (true, false): (8.5, .regular)
            }
        let mark = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        let palette = NSImage.SymbolConfiguration(paletteColors: [ink])
        var configured = mark?.withSymbolConfiguration(.init(pointSize: pointSize, weight: weight).applying(palette))
        var bounds = configured.map(Self.inkBounds) ?? .zero
        if showsText, bounds.width > Self.markMaximumWidth {
            let size = pointSize * Self.markMaximumWidth / bounds.width
            configured = mark?.withSymbolConfiguration(.init(pointSize: size, weight: weight).applying(palette))
            bounds = configured.map(Self.inkBounds) ?? .zero
        }
        self.mark = configured
        markInk = bounds
        let text =
            showsText
            ? CTLineCreateWithAttributedString(
                NSAttributedString(
                    string: percent.formatted(), attributes: [.font: Self.digitFont, .foregroundColor: NSColor.black, .kern: -0.4]))
            : nil
        self.text = text
        textInk = text.map { CTLineGetImageBounds($0, nil) } ?? .zero
    }

    var ink: NSColor { tint == nil ? .black : .labelColor }

    var size: NSSize {
        guard modern else { return Self.classicSize }
        let overhang = limit == nil ? 0 : Self.markerOverhang * 2
        return NSSize(width: bodyWidth + Self.capGap + Self.cap.width, height: Self.modernHeight + overhang)
    }

    private var level: Double { min(max(Double(percent), 0), 100) / 100 }

    private var contentWidth: Double {
        guard mark != nil else { return textInk.width }
        return text == nil ? markInk.width : textInk.width + Self.markGap + markInk.width
    }

    private var bodyWidth: Double { max(Self.modernMinimumWidth, (contentWidth + Self.modernPadding * 2).rounded(.up)) }

    func draw(in context: CGContext) {
        if modern {
            drawModern(in: context)
        } else {
            drawClassic(in: context)
        }
    }

    private func drawModern(in context: CGContext) {
        let height = Self.modernHeight
        let body = NSRect(x: 0, y: 0, width: bodyWidth, height: height)
        let fillWidth = level > 0 ? max(body.width * level, 1.5) : 0
        if limit != nil { context.translateBy(x: 0, y: Self.markerOverhang) }
        context.saveGState()
        NSBezierPath(roundedRect: body, xRadius: Self.modernRadius, yRadius: Self.modernRadius).addClip()
        ink.withAlphaComponent(Self.dimAlpha).setFill()
        body.fill()
        (tint ?? ink).setFill()
        NSRect(x: 0, y: 0, width: fillWidth, height: height).fill()
        context.restoreGState()
        ink.withAlphaComponent(Self.capAlpha).setFill()
        context.addPath(Self.capPath(at: body.maxX + Self.capGap))
        context.fillPath()

        context.setBlendMode(.destinationOut)
        var x = (body.width - contentWidth) / 2
        if let text {
            context.setShouldSubpixelPositionFonts(true)
            context.setShouldSubpixelQuantizeFonts(false)
            context.textPosition = CGPoint(x: x - textInk.minX, y: Self.baseline)
            CTLineDraw(text, context)
            x += textInk.width + Self.markGap
        }
        if let mark {
            let center = text == nil ? height / 2 : Self.baseline + textInk.midY
            let frame = NSRect(
                x: x - markInk.minX, y: center - markInk.midY, width: mark.size.width, height: mark.size.height)
            mark.draw(in: frame, from: .zero, operation: .destinationOut, fraction: 1)
        }
        if let limit {
            let x = (body.width * Double(limit) / 100).rounded()
            for y in [-2.5, height - 1.5] {
                NSBezierPath(roundedRect: NSRect(x: x - 1, y: y, width: 2, height: 4), xRadius: 1, yRadius: 1).fill()
            }
            context.setBlendMode(.normal)
            ink.setFill()
            for y in [-2.0, height - 1] {
                NSBezierPath(roundedRect: NSRect(x: x - 0.5, y: y, width: 1, height: 3), xRadius: 0.5, yRadius: 0.5).fill()
            }
        }
        context.setBlendMode(.normal)
    }

    private static func inkBounds(of image: NSImage) -> NSRect {
        let scale = 4.0
        let width = Int((image.size.width * scale).rounded(.up))
        let height = Int((image.size.height * scale).rounded(.up))
        let fallback = NSRect(origin: .zero, size: image.size)
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return fallback }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: fallback)
        NSGraphicsContext.restoreGraphicsState()
        guard let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return fallback }
        let inked = { (column: Int, row: Int) in pixels[(row * width + column) * 4 + 3] > 32 }
        let columns = (0..<width).filter { column in (0..<height).contains { inked(column, $0) } }
        let rows = (0..<height).filter { row in (0..<width).contains { inked($0, row) } }
        guard let left = columns.first, let right = columns.last, let top = rows.first, let bottom = rows.last else { return fallback }
        return NSRect(
            x: Double(left) / scale, y: Double(height - 1 - bottom) / scale, width: Double(right + 1 - left) / scale,
            height: Double(bottom + 1 - top) / scale)
    }

    private static func capPath(at x: Double) -> CGPath {
        let rect = cap.offsetBy(dx: x, dy: 0)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: capRadius)
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: capRadius)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private func drawClassic(in context: CGContext) {
        let body = Self.classicBody
        let well = Self.classicWell
        ink.withAlphaComponent(Self.outlineAlpha).setStroke()
        let outline = NSBezierPath(roundedRect: body, xRadius: 3.5, yRadius: 3.5)
        outline.lineWidth = 1
        outline.stroke()
        ink.withAlphaComponent(Self.outlineAlpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: 24.5, y: 4.5, width: 1.75, height: 4), xRadius: 0.9, yRadius: 0.9).fill()
        if level > 0 {
            (tint ?? ink).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: well.minX, y: well.minY, width: max(well.width * level, 2), height: well.height), xRadius: 1.75,
                yRadius: 1.75
            )
            .fill()
        }

        let limitX = limit.map { (well.minX + well.width * Double($0) / 100).rounded() + 0.5 }
        if let mark {
            var center = body.midX
            if let limitX {
                let left = limitX - 1.5 - well.minX
                let right = well.maxX - limitX - 1.5
                center = left >= right ? well.minX + left / 2 : limitX + 1.5 + right / 2
            }
            drawHaloed(
                mark,
                in: NSRect(
                    x: center - mark.size.width / 2, y: body.midY - mark.size.height / 2, width: mark.size.width, height: mark.size.height))
        }

        guard let limitX else { return }
        let height = Self.classicSize.height
        context.setBlendMode(.clear)
        NSBezierPath(rect: NSRect(x: limitX - 1.5, y: 0, width: 3, height: height)).fill()
        context.setBlendMode(.normal)
        ink.setFill()
        NSBezierPath(roundedRect: NSRect(x: limitX - 0.5, y: 0, width: 1, height: height), xRadius: 0.5, yRadius: 0.5).fill()
    }

    private func drawHaloed(_ mark: NSImage, in frame: NSRect) {
        for step in 0..<16 {
            let angle = Double(step) / 16 * 2 * .pi
            mark.draw(
                in: frame.offsetBy(dx: cos(angle) * Self.haloRadius, dy: sin(angle) * Self.haloRadius), from: .zero,
                operation: .destinationOut, fraction: 1)
        }
        mark.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

extension BatteryGlyph {
    @MainActor static func styled(percent: Int, limit: Int, status: ChargeStatus, label: String) -> NSImage? {
        let prefs = Preferences.shared
        var tint = prefs.colorIcon ? status.tint ?? (percent <= 10 ? .systemRed : nil) : nil
        if EnergySettings.shared.isLowPowerMode { tint = .systemYellow }
        let style = GlyphStyle(
            tint: tint, showsBattery: prefs.showIcon,
            symbolInside: prefs.symbolsInside, modern: prefs.iconStyle == .modern,
            percentInside: prefs.showPercentage && prefs.percentInside)
        let symbol = status.statusSymbol.flatMap { prefs.statusSymbols.contains($0) ? $0.systemName : nil }
        let glyph = image(percent: percent, limit: prefs.showLimitMarker ? limit : nil, symbol: symbol, style: style)
        glyph?.accessibilityDescription = label
        return glyph
    }
}
