import AppKit

/// Controls overlay the page: revealing them never resizes the WebKit viewport.
/// Only enter/exit events in a small top region are needed (no mouse polling).
final class BrowserRootView: NSView {
    static let chromeHeight: CGFloat = 68
    static let revealHeight: CGFloat = 8
    var onChromeHoverChanged: ((Bool) -> Void)?
    var controlsVisible = true {
        didSet { if controlsVisible != oldValue { updateTrackingAreas() } }
    }
    private var chromeArea: NSTrackingArea?

    var pointerInsideChrome: Bool {
        guard let window else { return false }
        return chromeTrackingRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private var chromeTrackingRect: NSRect {
        let height = min(bounds.height, controlsVisible ? Self.chromeHeight : Self.revealHeight)
        return NSRect(x: bounds.minX, y: bounds.maxY - height, width: bounds.width, height: height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let chromeArea { removeTrackingArea(chromeArea) }
        let area = NSTrackingArea(rect: chromeTrackingRect,
            options: [.activeAlways, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        chromeArea = area
    }

    override func mouseEntered(with event: NSEvent) { onChromeHoverChanged?(pointerInsideChrome) }
    override func mouseExited(with event: NSEvent) { onChromeHoverChanged?(pointerInsideChrome) }
}

enum BrowserChromePolicy {
    static func canHide(pointerInside: Bool, editing: Bool, controlsFocused: Bool,
                        hasSheet: Bool, isHome: Bool, pinned: Bool) -> Bool {
        !pointerInside && !editing && !controlsFocused && !hasSheet && !isHome && !pinned
    }
}
