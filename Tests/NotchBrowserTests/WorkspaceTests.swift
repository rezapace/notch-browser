import AppKit

/// Standalone checks for Command Line Tools installations without XCTest.
@main
struct WorkspaceTests {
    @MainActor
    static func main() {
        for size in [NSSize(width: 1024, height: 768), NSSize(width: 1440, height: 900), NSSize(width: 2560, height: 1600)] {
            let screen = NSRect(origin: .zero, size: size)
            let visible = NSRect(x: 0, y: 60, width: size.width, height: size.height - 92)
            let frame = WorkspaceGeometry.expandedFrame(in: screen, visibleFrame: visible, topInset: 40)
            let compact = WorkspaceGeometry.compactFrame(in: screen, height: 34, cameraGap: 180)
            precondition(screen.contains(frame) && screen.contains(compact))
            precondition(frame.minX > 0 && frame.minY > visible.minY)
            precondition(frame.midX == screen.midX && compact.midX == screen.midX)
            precondition(frame.maxY == screen.maxY && compact.maxY == screen.maxY)
            precondition(frame.width <= 1180 && frame.height <= 800)
        }
        print("PASS: compact and expanded share the screen-top anchor on three display sizes")

        let screen = NSRect(x: -1920, y: -150, width: 1920, height: 1080)
        let visible = screen.insetBy(dx: 0, dy: 32)
        let expanded = WorkspaceGeometry.expandedFrame(in: screen, visibleFrame: visible, topInset: 40)
        precondition(screen.contains(expanded) && expanded.maxY == screen.maxY && expanded.midX == screen.midX)
        print("PASS: secondary display with negative origin")

        let content = WorkspaceGeometry.browserFrame(in: expanded.size, topInset: 40)
        precondition(expanded.height - content.maxY == 40)
        precondition(content.minX == WorkspaceGeometry.sideInset && content.minY == WorkspaceGeometry.bottomInset)
        let shape = WorkspaceGeometry.silhouette(in: NSRect(origin: .zero, size: expanded.size))
        precondition(shape.contains(NSPoint(x: expanded.width / 2, y: expanded.height - 1)))
        precondition(!shape.contains(NSPoint(x: 1, y: 1)))
        let radius = WorkspaceGeometry.contentCornerRadius
        for point in [NSPoint(x: content.minX, y: content.minY + radius),
                      NSPoint(x: content.minX + radius, y: content.minY),
                      NSPoint(x: content.maxX - radius, y: content.minY),
                      NSPoint(x: content.maxX, y: content.minY + radius),
                      NSPoint(x: content.maxX, y: content.maxY)] {
            precondition(shape.contains(point))
        }
        precondition(WorkspaceGeometry.sideInset == 10 && WorkspaceGeometry.bottomInset == 2)
        print("PASS: thin borders, camera rail, and rounded content stay inside notch silhouette")

        precondition(!WorkspacePolicy.canAutoDismiss(isKey: true, hasSheet: false, pointerInside: false, hasInteracted: true))
        precondition(!WorkspacePolicy.canAutoDismiss(isKey: false, hasSheet: true, pointerInside: false, hasInteracted: true))
        precondition(!WorkspacePolicy.canAutoDismiss(isKey: false, hasSheet: false, pointerInside: true, hasInteracted: false))
        precondition(WorkspacePolicy.canAutoDismiss(isKey: false, hasSheet: false, pointerInside: false, hasInteracted: false))
        precondition(WorkspacePolicy.canAutoDismiss(isKey: false, hasSheet: false, pointerInside: true, hasInteracted: true))
        print("PASS: preview, interaction, and sheet dismissal policy")

        _ = NSApplication.shared
        guard let display = NSScreen.main else { fatalError("A graphical macOS session is required") }
        let window = WorkspaceWindow()
        precondition(!window.canBecomeKey && !window.canBecomeMain)
        precondition(!window.styleMask.contains(.titled) && window.styleMask.contains(.nonactivatingPanel))
        precondition(!window.isOpaque && !window.isMovable)
        let shell = window.contentView!
        let browser = NSView()
        window.installBrowser(browser)
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        window.showCompact(on: display)
        let panelNumber = window.windowNumber
        let compactFrame = window.frame
        precondition(window.isVisible && !window.isPresented && browser.isHidden)
        precondition(window.frame.maxY == display.frame.maxY)
        print("PASS: a single nonactivating panel starts compact at the notch")

        window.present(on: display)
        pumpEvents(for: 0.35, checkingTopOf: window, on: display)
        precondition(window.isPresented && window.isVisible && !window.isKeyWindow && window.canBecomeKey)
        precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
        precondition(window.contentView === shell && browser.superview === shell && browser.window === window)
        precondition(window.windowNumber == panelNumber && !browser.isHidden)
        let topRail = window.frame.height - window.browserContentFrame.maxY
        precondition(topRail >= display.safeAreaInsets.top)
        precondition(abs(topRail - max(display.safeAreaInsets.top, NSStatusBar.system.thickness) - 2) < 0.01)
        print("PASS: expansion stays top-anchored, reuses the shell/browser, and preserves focus")

        var staleCompletionRan = false
        window.dismiss { staleCompletionRan = true }
        window.present(on: display)
        pumpEvents(for: 0.4, checkingTopOf: window, on: display)
        precondition(window.isPresented && !staleCompletionRan && !browser.isHidden)
        print("PASS: reopening cancels stale collapse completion")

        for _ in 0..<3 {
            var completed = false
            let viewport = browser.bounds.size
            window.dismiss { completed = true }
            pumpEvents(for: 0.3, checkingTopOf: window, on: display)
            precondition(completed && window.isVisible && !window.isPresented)
            precondition(window.frame == compactFrame && browser.isHidden && browser.bounds.size == viewport)
            precondition(window.contentView === shell && browser.window === window && window.windowNumber == panelNumber)
            window.present(on: display)
            pumpEvents(for: 0.3, checkingTopOf: window, on: display)
            precondition(window.isVisible && !window.isKeyWindow && !browser.isHidden)
        }
        print("PASS: repeated collapse returns to the SAME notch panel without detaching browser")

        let mask = shell.layer?.mask as? CAShapeLayer
        precondition(mask?.path != nil)
        precondition(shell.hitTest(NSPoint(x: 1, y: 1)) == nil)
        precondition(shell.hitTest(NSPoint(x: shell.bounds.midX, y: shell.bounds.maxY - 1)) != nil)
        print("PASS: rendered mask and hit testing share notch geometry")
        window.orderOut(nil)

        let minimalWindow = WorkspaceWindow()
        minimalWindow.reposition(on: display)
        let controller = BrowserController(window: minimalWindow)
        controller.prepareForPresentation()
        let root = minimalWindow.contentView!.subviews.first { $0.accessibilityIdentifier() == "browser.root" }!
        precondition(root.subviews.count == 3, "Only tab strip, navigation row, and pages should be present")
        let navigation = root.subviews.first { $0.accessibilityIdentifier() == "browser.navigation" }!
        let pages = root.subviews.first { $0.accessibilityIdentifier() == "browser.pages" }!
        precondition(navigation.subviews.compactMap { $0 as? NSButton }.count == 2)
        precondition(navigation.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }.count == 1)
        precondition(pages.frame.minX == 0 && pages.frame.minY == 0 && pages.frame.width == root.bounds.width)
        precondition(abs(root.bounds.height - pages.frame.maxY - 68) < 0.01)
        print("PASS: only tabs, URL, previous/next; no nested page gutters or header")

        let file = NSApp.mainMenu!.item(withTitle: "File")!.submenu!
        func invoke(_ title: String) {
            let item = file.item(withTitle: title)!
            precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
        }
        precondition(pages.subviews.count == 1)
        invoke("New Tab")
        precondition(pages.subviews.count == 2)
        invoke("Close Tab")
        precondition(pages.subviews.count == 1)
        invoke("Close Tab")
        precondition(pages.subviews.count == 1, "Closing the last tab must leave a usable new tab")
        withExtendedLifetime(controller) {}
        print("PASS: minimal tab controls still add/close tabs including the last tab")
    }

    @MainActor
    private static func pumpEvents(for seconds: TimeInterval, checkingTopOf window: NSWindow, on screen: NSScreen) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
            precondition(abs(window.frame.maxY - screen.frame.maxY) < 1, "Animation detached from notch")
        }
    }
}
