import AppKit
import NoNeedCloudCore
import Observation
import SwiftUI

/// Owns the menu bar item and its panel. A custom status item (instead of
/// SwiftUI's MenuBarExtra) lets the icon fill with progress and lets the
/// panel open centred under the icon.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let router: AppRouter
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var lastIconKey = ""

    init(model: AppModel, router: AppRouter) {
        self.model = model
        self.router = router
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.imagePosition = .imageOnly
            button.toolTip = "NoNeedCloud"
        }
        updateIcon()
        observeModel()
    }

    // MARK: Icon

    /// Re-renders the icon whenever the backup state or progress changes.
    private func observeModel() {
        withObservationTracking {
            _ = model.screenState
            _ = model.progress?.fractionCompleted
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateIcon()
                self?.observeModel()
            }
        }
    }

    private func updateIcon() {
        let state = model.screenState
        var fraction: Double?
        if case .running = state { fraction = model.progress?.fractionCompleted ?? 0 }
        var attention = false
        if case .needsAttention = state { attention = true }
        // Whole percent steps are enough and keep redraws cheap.
        let key = "\(fraction.map { Int($0 * 100) } ?? -1)-\(attention)"
        guard key != lastIconKey else { return }
        lastIconKey = key
        statusItem.button?.image = CloudProgressIcon.image(fraction: fraction, attention: attention)
        statusItem.button?.setAccessibilityValue(fraction.map { "\(Int($0 * 100))%" })
    }

    // MARK: Panel

    @objc private func togglePanel() {
        if let panel, panel.isVisible { closePanel() } else { showPanel() }
    }

    private func showPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }
        statusItem.button?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    func closePanel() {
        guard let panel, panel.isVisible else { return }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        statusItem.button?.highlight(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = StatusPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.onResignKey = { [weak self] in self?.closePanel() }

        let root = MenuBarPanel(model: model, router: router, onAction: { [weak self] in self?.closePanel() })
            .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Theme.lightLine))
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentView = hosting
        return panel
    }

    /// Centre the panel horizontally under the status item, a few points below the menu bar.
    private func position(_ panel: NSPanel) {
        guard let button = statusItem.button, let window = button.window else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        // Measure the SwiftUI content first; before its first layout it reports zero.
        panel.contentView?.layoutSubtreeIfNeeded()
        var size = panel.contentView?.fittingSize ?? .zero
        if size.width < 10 || size.height < 10 { size = NSSize(width: 348, height: 360) }
        var origin = NSPoint(x: buttonFrame.midX - size.width / 2, y: buttonFrame.minY - size.height - 6)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

/// Borderless panels can't become key by default; this one can, so text
/// fields and Esc work, and it reports losing focus so it can close.
private final class StatusPanel: NSPanel {
    var onResignKey: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
    override func cancelOperation(_ sender: Any?) { onResignKey?() }
}
