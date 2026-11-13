import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usage = UsageStore()
    private let stats = StatsStore()
    private let panelState = PanelState()
    private var panel: FloatingPanel?
    private var screenObserver: NSObjectProtocol?
    private var collapseWork: DispatchWorkItem?
    private var statsObserver: AnyCancellable?
    private var isAnimating = false

    /// Double-clicking the app while it's already running brings the widget to the current desktop.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel?.showOnActiveSpace()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let host = InteractiveHostingView(rootView: RootView(usage: usage, stats: stats, panel: panelState))
        host.sizingOptions = [.intrinsicContentSize]  // Report content size only; we size/position the window ourselves.
        host.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        host.onHover = { [weak self] inside in self?.hoverChanged(inside) }

        let panel = FloatingPanel(content: host)
        panel.orderFrontRegardless()
        self.panel = panel

        // Re-anchor when displays are plugged in/out or resolution changes.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.panel?.pinToCorner(animated: false) }
        }
        // Stats can arrive after the panel settled open (first scan); refit so the card isn't clipped.
        statsObserver = stats.$stats.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refitIfSettledOpen() }
        }
        usage.start()
        stats.start()
    }

    private func hoverChanged(_ inside: Bool) {
        collapseWork?.cancel()
        if inside {
            setExpanded(true)
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Config.collapseDelay, execute: work)
    }

    /// The window is first grown (invisibly — it's transparent) to a canvas big enough for the expanded card,
    /// then SwiftUI animates the card itself. Once the animation settles the window is trimmed to fit.
    func setExpanded(_ expanded: Bool) {
        guard panelState.expanded != expanded else { return }
        if expanded {
            stats.refreshIfStale()
            panel?.growToCanvas()
        }
        isAnimating = true
        withAnimation(expanded ? Motion.expand : Motion.collapse) {
            panelState.expanded = expanded
        } completion: { [weak self] in
            // Completion runs inside SwiftUI's layout pass, where fittingSize reads as zero. Defer it.
            DispatchQueue.main.async { self?.settleWindow() }
        }
    }

    /// Trims the window to the card and collapses if the pointer is no longer over it.
    private func settleWindow() {
        isAnimating = false
        guard let panel else { return }
        panel.pinToCorner(animated: false)
        if panelState.expanded, !panel.frame.contains(NSEvent.mouseLocation) {
            hoverChanged(false)
        }
    }

    private func refitIfSettledOpen() {
        guard panelState.expanded, !isAnimating else { return }
        panel?.pinToCorner(animated: false)
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        if let updated = usage.lastUpdated {
            let title = "Updated \(DateFormatter.localizedString(from: updated, dateStyle: .none, timeStyle: .short))"
            let info = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            info.isEnabled = false
            menu.addItem(info)
            menu.addItem(.separator())
        }
        menu.addItem(item("Refresh Now", #selector(refreshNow)))
        menu.addItem(item("Open Claude Usage", #selector(openClaude)))
        menu.addItem(item("Open Codex Usage", #selector(openCodex)))
        menu.addItem(.separator())
        menu.addItem(item("Quit UsageBar", #selector(quit)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
        menuItem.target = self
        return menuItem
    }

    @objc private func refreshNow() {
        usage.refresh()
        stats.refresh()
    }

    @objc private func openClaude() { NSWorkspace.shared.open(Config.claudeWebUsageURL) }
    @objc private func openCodex() { NSWorkspace.shared.open(Config.codexWebUsageURL) }
    @objc private func quit() { NSApp.terminate(nil) }
}
