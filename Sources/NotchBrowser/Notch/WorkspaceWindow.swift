import AppKit
import QuartzCore

/// Compact and expanded frames share exactly the same top anchor.
enum WorkspaceGeometry {
    // One shell mask clips both the browser and the rounded lower corners.
    static let sideInset: CGFloat = 10
    static let bottomInset: CGFloat = 2
    static let expandedCornerRadius: CGFloat = 28

    static func expandedFrame(in screenFrame: NSRect, visibleFrame: NSRect, topInset: CGFloat) -> NSRect {
        // Prefer an 850×650 page where the display permits it. Respect a Dock
        // on either side while staying centered on the physical screen/notch.
        let availableWidth = max(1, min(screenFrame.width - 16,
            2 * min(screenFrame.midX - visibleFrame.minX, visibleFrame.maxX - screenFrame.midX) - 16))
        let width = min(1180, availableWidth, max(850 + sideInset * 2, screenFrame.width * 0.84))
        let availableHeight = max(1, screenFrame.maxY - visibleFrame.minY - 16)
        let height = min(900, availableHeight, max(650 + topInset + bottomInset, visibleFrame.height * 0.90 + topInset))
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    static func compactFrame(in screenFrame: NSRect, height: CGFloat, cameraGap: CGFloat) -> NSRect {
        let width = min(screenFrame.width, max(360, cameraGap + 150))
        return NSRect(x: screenFrame.midX - width / 2, y: screenFrame.maxY - height, width: width, height: height)
    }

    static func browserFrame(in size: NSSize, topInset: CGFloat) -> NSRect {
        NSRect(x: sideInset, y: bottomInset,
               width: max(1, size.width - sideInset * 2),
               height: max(1, size.height - topInset - bottomInset))
    }

    /// DynamicNotchShape is y-down; AppKit's container and layer here are y-up.
    static func silhouette(in bounds: NSRect, expanded: Bool = true) -> CGPath {
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.minY + bounds.maxY)
        let radius = expanded ? expandedCornerRadius : 14
        let path = DynamicNotchShape(direction: .top, cornerRadius: radius, shoulderRadius: 8).path(in: bounds).cgPath
        return path.copy(using: &flip)!
    }
}

enum WorkspacePolicy {
    static func canAutoDismiss(isKey: Bool, hasSheet: Bool, pointerInside: Bool, hasInteracted: Bool) -> Bool {
        !isKey && !hasSheet && (hasInteracted || !pointerInside)
    }
}

/// ONE panel owns both compact notch and expanded browser for its entire lifetime.
final class WorkspaceWindow: NSPanel {
    var onDismiss: (() -> Void)?
    var onExpandRequested: (() -> Void)?
    var onHoverChanged: ((Bool) -> Void)?
    var onInteraction: (() -> Void)?
    var onFocusChanged: (() -> Void)?
    private let surface = WorkspaceSurface(frame: .zero)
    private var transitionID = 0
    private var targetScreen: NSScreen?
    private var compactFrame = NSRect.zero
    private var expandedFrame = NSRect.zero
    private(set) var isPresented = false // true = expanded, false = compact
    private(set) var isTransitioning = false

    override var canBecomeKey: Bool { isPresented }
    override var canBecomeMain: Bool { false }
    var containsPointer: Bool { surface.containsPointer }
    var browserContentFrame: NSRect { surface.browserView?.frame ?? .zero }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        appearance = NSAppearance(named: .darkAqua)
        isMovable = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        contentView = surface
        surface.onHoverChanged = { [weak self] inside in self?.onHoverChanged?(inside) }
    }

    func installBrowser(_ view: NSView) { surface.installBrowser(view) }

    private func configure(on screen: NSScreen) {
        targetScreen = screen
        let rail = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) + 2
        let gap: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            gap = max(0, right.minX - left.maxX)
        } else { gap = 0 }
        compactFrame = WorkspaceGeometry.compactFrame(in: screen.frame,
            height: max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) + 2, cameraGap: gap)
        expandedFrame = WorkspaceGeometry.expandedFrame(in: screen.frame, visibleFrame: screen.visibleFrame, topInset: rail)
        surface.configure(browserSize: expandedFrame.size, topInset: rail, cameraGap: gap)
    }

    func showCompact(on screen: NSScreen) {
        transitionID += 1
        isPresented = false
        isTransitioning = false
        configure(on: screen)
        surface.setExpanded(false)
        setFrame(compactFrame, display: true)
        orderFrontRegardless()
        surface.refreshHover()
    }

    func present(on screen: NSScreen, activate: Bool = false) {
        guard !isPresented else {
            if activate { takeFocus() }
            return
        }
        if !isVisible { showCompact(on: screen) }
        configure(on: screen)
        isPresented = true
        surface.setExpanded(true)
        orderFrontRegardless() // no activation on hover
        animate(to: expandedFrame, duration: 0.24) { [weak self] in self?.surface.refreshHover() }
        if activate { takeFocus() }
    }

    func dismiss(completion: @escaping () -> Void) {
        guard isPresented else { return }
        let wasKey = isKeyWindow
        isPresented = false
        if wasKey { makeFirstResponder(nil); resignKey() }
        // Preserve the full-sized, same browser view while the outer panel contracts.
        surface.hideBrowserForCollapse()
        animate(to: compactFrame, duration: 0.20) { [weak self] in
            guard let self else { return }
            self.surface.setExpanded(false)
            self.surface.refreshHover()
            completion()
        }
    }

    func reposition(on screen: NSScreen) {
        transitionID += 1
        isTransitioning = false
        configure(on: screen)
        surface.setExpanded(isPresented)
        setFrame(isPresented ? expandedFrame : compactFrame, display: true)
        surface.refreshHover()
    }

    private func animate(to frame: NSRect, duration: TimeInterval, completion: @escaping () -> Void) {
        transitionID += 1
        let id = transitionID
        isTransitioning = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            // y and height interpolate together: maxY never leaves the screen's top edge.
            animator().setFrame(frame, display: true)
        } completionHandler: { [weak self] in
            guard let self, self.transitionID == id else { return }
            self.isTransitioning = false
            completion()
        }
    }

    func takeFocus() {
        guard isPresented else { return }
        onInteraction?()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            if isPresented { takeFocus() } else { onExpandRequested?(); return }
        }
        super.sendEvent(event)
    }

    @discardableResult
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let changed = firstResponder !== responder
        let accepted = super.makeFirstResponder(responder)
        if accepted && changed { onFocusChanged?() }
        return accepted
    }

    override func performClose(_ sender: Any?) { onDismiss?() }
}

/// One black, shaped surface: no gap or second rounded window below the notch.
/// The same path masks rendering, hit testing, and hover detection.
final class WorkspaceSurface: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private(set) var browserView: NSView?
    private let leading = NSTextField(labelWithString: "Browse")
    private let trailing = NSImageView()
    private let shapeMask = CAShapeLayer()
    private var shapePath: CGPath?
    private var hoverArea: NSTrackingArea?
    private var inside = false
    private var expanded = false
    private var browserSize = NSSize(width: 900, height: 600)
    private var topInset: CGFloat = 40
    private var cameraGap: CGFloat = 0
    private struct GeometryState: Equatable {
        let bounds: NSRect
        let browserSize: NSSize
        let topInset: CGFloat
        let cameraGap: CGFloat
        let expanded: Bool
    }
    private var lastGeometry: GeometryState?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.mask = shapeMask
        leading.font = .systemFont(ofSize: 11, weight: .medium)
        leading.textColor = .white
        leading.alignment = .right
        trailing.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Open browser")
        trailing.contentTintColor = .lightGray
        addSubview(leading)
        addSubview(trailing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var containsPointer: Bool {
        guard let window else { return false }
        return shapePath?.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) == true
    }

    func installBrowser(_ view: NSView) {
        precondition(browserView == nil, "Install one persistent browser view only")
        browserView = view
        addSubview(view)
        view.isHidden = !expanded
        lastGeometry = nil
        updateGeometry()
    }

    func configure(browserSize: NSSize, topInset: CGFloat, cameraGap: CGFloat) {
        self.browserSize = browserSize
        self.topInset = topInset
        self.cameraGap = cameraGap
        updateGeometry()
    }

    func setExpanded(_ value: Bool) {
        expanded = value
        browserView?.isHidden = !value
        leading.isHidden = value
        trailing.isHidden = value
        updateGeometry()
    }

    func hideBrowserForCollapse() { browserView?.isHidden = true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateGeometry()
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    private func updateGeometry() {
        let state = GeometryState(bounds: bounds, browserSize: browserSize,
            topInset: topInset, cameraGap: cameraGap, expanded: expanded)
        guard state != lastGeometry else { return }
        if lastGeometry?.bounds != bounds || lastGeometry?.expanded != expanded {
            shapePath = WorkspaceGeometry.silhouette(in: bounds, expanded: expanded)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            shapeMask.frame = bounds
            shapeMask.path = shapePath
            CATransaction.commit()
        }
        lastGeometry = state
        // Keep WebKit's viewport stable during animation; clip rather than squash it.
        let target = WorkspaceGeometry.browserFrame(in: browserSize, topInset: topInset)
        let browserFrame = NSRect(x: (bounds.width - target.width) / 2,
                                  y: bounds.height - topInset - target.height,
                                  width: target.width, height: target.height)
        if browserView?.frame != browserFrame { browserView?.frame = browserFrame }
        let center = bounds.midX
        leading.frame = NSRect(x: center - cameraGap / 2 - 68, y: (bounds.height - 16) / 2, width: 56, height: 16)
        trailing.frame = NSRect(x: center + cameraGap / 2 + 12, y: (bounds.height - 12) / 2, width: 12, height: 12)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard shapePath?.contains(point) == true else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { refreshHover() }
    override func mouseMoved(with event: NSEvent) { refreshHover() }
    override func mouseExited(with event: NSEvent) { setInside(false) }

    func refreshHover() { setInside(containsPointer) }

    private func setInside(_ value: Bool) {
        guard value != inside else { return }
        inside = value
        onHoverChanged?(value)
    }
}

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
