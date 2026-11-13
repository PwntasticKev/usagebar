import AppKit
import SwiftUI

/// Borderless, non-activating panel pinned to the bottom-left of the primary display.
/// It lives only on the Space (desktop) it was opened on, so swiping to other desktops leaves it behind.
final class FloatingPanel: NSPanel {
    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        // No .canJoinAllSpaces: the window stays on one desktop of the main display only.
        collectionBehavior = Self.homeBehavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        contentView = content
        pinToCorner(animated: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private static let homeBehavior: NSWindow.CollectionBehavior = [.ignoresCycle, .fullScreenNone]

    /// Moves the widget onto the main display's current desktop, making that its new home.
    /// Briefly joining all Spaces and then leaving them re-homes the window on the visible one.
    func showOnActiveSpace() {
        pinToCorner(animated: false)
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenNone]
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.collectionBehavior = Self.homeBehavior
            self?.orderFrontRegardless()
        }
    }

    /// Instantly enlarges the (transparent) window upward/rightward so an animating card never gets clipped.
    /// The bottom-left origin is unchanged, so nothing visibly moves.
    func growToCanvas() {
        let size = NSSize(
            width: max(frame.width, Layout.expandedCanvas.width),
            height: max(frame.height, Layout.expandedCanvas.height)
        )
        setFrame(NSRect(origin: frame.origin, size: size), display: true)
        // Commit the new layout now, outside any animation, so the card doesn't animate in from the top.
        contentView?.layoutSubtreeIfNeeded()
    }

    /// Sizes the window to its content and anchors it to the bottom-left of the primary (menu-bar) display.
    /// Growth happens upward because the bottom-left origin stays fixed.
    func pinToCorner(animated: Bool) {
        guard let screen = NSScreen.screens.first ?? NSScreen.main, let content = contentView else { return }
        content.layoutSubtreeIfNeeded()
        let size = content.fittingSize
        let target = NSRect(
            origin: NSPoint(x: screen.frame.minX + Layout.screenMargin, y: screen.frame.minY + Layout.screenMargin),
            size: size
        )
        guard animated else {
            setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
        }
    }
}

/// Hosting view that reports hover (even while the app is inactive) and shows a right-click menu.
final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    var menuProvider: (() -> NSMenu)?
    var onHover: ((Bool) -> Void)?
    private var hoverArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
