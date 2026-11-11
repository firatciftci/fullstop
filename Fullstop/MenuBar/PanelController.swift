import AppKit
import SwiftUI

final class FullstopPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_: Any?) {
        onCancel?()
    }
}

final class PanelHostingView<Content: View>: NSHostingView<Content> {
    var onResize: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onResize?()
    }
}

final class PanelController: NSObject {
    var onVisibilityChange: ((Bool) -> Void)?

    private let width: CGFloat = 340
    private let panel = FullstopPanel(
        contentRect: .zero,
        styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    private var host: NSView?
    private weak var anchor: NSStatusBarButton?
    private var outsideMonitor: Any?

    override init() {
        super.init()
        build()
        panel.onCancel = { [weak self] in self?.close() }
    }

    var isVisible: Bool { panel.isVisible }

    private func build() {
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let glass = NSGlassEffectView()
        glass.cornerRadius = 24
        glass.style = .regular
        let root = PanelRootView()
            .environment(BatteryMonitor.shared)
            .environment(ChargeController.shared)
            .environment(HelperClient.shared)
            .environment(Preferences.shared)
            .environment(EnergySettings.shared)
            .frame(width: width)
        let host = PanelHostingView(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]
        host.onResize = { [weak self] in
            guard let self, panel.isVisible else { return }
            Task { @MainActor in self.position() }
        }
        glass.contentView = host
        self.host = host
        glass.wantsLayer = true
        glass.layer?.cornerRadius = glass.cornerRadius
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        panel.contentView = glass
    }

    func toggle(from button: NSStatusBarButton?) {
        if panel.isVisible {
            close()
        } else {
            show(from: button)
        }
    }

    func show(from button: NSStatusBarButton?) {
        if let button { anchor = button }
        BatteryMonitor.shared.refresh()
        HelperClient.shared.refresh()
        EnergySettings.shared.refresh()
        position()
        let finalFrame = panel.frame
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        if !reduceMotion { panel.setFrame(finalFrame.offsetBy(dx: 0, dy: 8), display: false) }
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.12 : 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(finalFrame, display: true) }
        } completionHandler: {
            MainActor.assumeIsolated { self.panel.invalidateShadow() }
        }
        installMonitor()
        onVisibilityChange?(true)
    }

    func close() {
        guard panel.isVisible else { return }
        removeMonitor()
        onVisibilityChange?(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    private func position() {
        guard let screen = anchor?.window?.screen ?? NSScreen.main ?? NSScreen.screens.first,
            let host
        else { return }
        host.layoutSubtreeIfNeeded()
        let height = host.fittingSize.height
        let visible = screen.visibleFrame
        var x = visible.midX - width / 2
        var top = visible.maxY - 1
        if DemoData.isEnabled {
            top = visible.midY + height / 2
        } else if let placement = anchor?.menuBarPlacement {
            x = placement.frame.midX - width / 2
            top = placement.barBottom - 1
        }
        x = min(max(x, visible.minX + 8), visible.maxX - width - 8)
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: false)
    }

    private func installMonitor() {
        removeMonitor()
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeMonitor() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }
}

extension NSView {
    var menuBarPlacement: (frame: NSRect, barBottom: Double)? {
        guard let window, let screen = window.screen else { return nil }
        let frame = window.convertToScreen(convert(bounds, to: nil))
        let visible = screen.visibleFrame
        return (frame, visible.maxY < screen.frame.maxY ? visible.maxY : 2 * frame.midY - screen.frame.maxY)
    }
}
