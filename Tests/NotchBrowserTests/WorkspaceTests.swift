import AppKit
import WebKit

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
            precondition(frame.width <= 1180 && frame.height <= 900)
            let viewport = WorkspaceGeometry.browserFrame(in: frame.size, topInset: 40)
            precondition(viewport.width >= 850 && viewport.height >= 650)
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
        let radius = WorkspaceGeometry.expandedCornerRadius
        for point in [NSPoint(x: content.minX, y: content.minY + radius),
                      NSPoint(x: content.minX + radius, y: content.minY),
                      NSPoint(x: content.maxX - radius, y: content.minY),
                      NSPoint(x: content.maxX, y: content.minY + radius),
                      NSPoint(x: content.maxX, y: content.maxY)] {
            precondition(shape.contains(point))
        }
        precondition(WorkspaceGeometry.sideInset == 10 && WorkspaceGeometry.bottomInset == 2)
        precondition(radius == 28)
        let tiny = NSRect(x: 0, y: 0, width: 640, height: 480)
        precondition(tiny.contains(WorkspaceGeometry.expandedFrame(in: tiny,
            visibleFrame: tiny.insetBy(dx: 32, dy: 32), topInset: 40)))
        for leftDock in [true, false] {
            let desktop = NSRect(x: 0, y: 0, width: 1440, height: 900)
            let usable = NSRect(x: leftDock ? 120 : 0, y: 0, width: 1320, height: 860)
            let frame = WorkspaceGeometry.expandedFrame(in: desktop, visibleFrame: usable, topInset: 40)
            precondition(frame.minX >= usable.minX && frame.maxX <= usable.maxX)
        }
        print("PASS: rounded shell, usable viewport, small displays, and side Docks")

        precondition(BrowserChromePolicy.canHide(pointerInside: false, editing: false, controlsFocused: false,
            hasSheet: false, isHome: false, pinned: false))
        for index in 0..<6 {
            var blockers = [Bool](repeating: false, count: 6)
            blockers[index] = true
            precondition(!BrowserChromePolicy.canHide(pointerInside: blockers[0], editing: blockers[1],
                controlsFocused: blockers[2], hasSheet: blockers[3], isHome: blockers[4], pinned: blockers[5]))
        }
        print("PASS: auto-hide preserves hover, editing, keyboard focus, sheets, home and pinned controls")

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
        let cachedPath = mask!.path!
        shell.layout()
        shell.layout()
        precondition(cachedPath === mask!.path!, "Repeated layout should reuse the mask path")
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
        precondition(pages.frame == root.bounds, "Chrome overlays must not reduce the page viewport")
        precondition(pages.layer?.mask == nil && pages.layer?.masksToBounds == false)
        let tabs = root.subviews.first { $0.accessibilityIdentifier() == "browser.tabs" }!
        precondition(tabs.frame.height + navigation.frame.height == BrowserRootView.chromeHeight)
        let scroll = tabs.subviews.compactMap { $0 as? NSScrollView }.first!
        let firstChip = scroll.documentView!.subviews.first!
        for _ in 0..<10 { controller.prepareForPresentation() }
        precondition(scroll.documentView!.subviews.first === firstChip, "Tab views must be reused")
        let web = pages.subviews.first as! WKWebView
        precondition(web.configuration.websiteDataStore === WebKitRuntime.dataStore)
        precondition(web.configuration.websiteDataStore.isPersistent)
        precondition(!web.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        precondition(web.appearance?.name == .darkAqua)
        #if !DEBUG
        if #available(macOS 13.3, *) { precondition(!web.isInspectable) }
        #endif
        print("PASS: stable full-page viewport, persistent cache, dark appearance and reusable tab views")

        let file = NSApp.mainMenu!.item(withTitle: "File")!.submenu!
        func invoke(_ title: String) {
            let item = file.item(withTitle: title)!
            precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
        }
        precondition(pages.subviews.count == 1)
        weak var closedWebView: WKWebView?
        autoreleasepool {
            invoke("New Tab")
            precondition(pages.subviews.count == 2)
            precondition((pages.subviews.last as! WKWebView).configuration.websiteDataStore === web.configuration.websiteDataStore)
            closedWebView = pages.subviews.last as? WKWebView
            invoke("Close Tab")
            precondition(pages.subviews.count == 1)
            invoke("Close Tab")
            precondition(pages.subviews.count == 1, "Closing the last tab must leave a usable new tab")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        precondition(closedWebView == nil, "A closed tab's WebView should be released")
        print("PASS: tab controls, shared persistent store, and closed WebView cleanup")

        // Off-screen, nonactivating panel: exercise UI state without moving the user's pointer.
        minimalWindow.present(on: display)
        pumpEvents(for: 0.35, checkingTopOf: minimalWindow, on: display)
        minimalWindow.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        controller.prepareForPresentation()
        let page = pages.subviews.first as! WKWebView
        page.loadHTMLString("<!doctype html><title>Local test</title><body>Test</body>",
            baseURL: URL(string: "https://notch-browser.invalid/"))
        minimalWindow.makeFirstResponder(page)
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        precondition(tabs.isHidden && navigation.isHidden, "Controls should auto-hide away from pointer/editor")
        let viewport = page.bounds.size
        let browserRoot = root as! BrowserRootView
        precondition(browserRoot.trackingAreas.first?.rect.height == BrowserRootView.revealHeight)
        let responder = minimalWindow.firstResponder
        browserRoot.onChromeHoverChanged?(true)
        precondition(!tabs.isHidden && browserRoot.trackingAreas.first?.rect.height == BrowserRootView.chromeHeight)
        precondition(minimalWindow.firstResponder === responder && page.bounds.size == viewport)
        browserRoot.onChromeHoverChanged?(false)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(tabs.isHidden)

        let activeChip = scroll.documentView!.subviews.first!
        let titleButton = activeChip.subviews.first as! NSButton
        var verifiedPage = false
        page.evaluateJavaScript("document.title = 'Updated title'; matchMedia('(prefers-color-scheme: dark)').matches") { result, error in
            precondition(error == nil && result as? Bool == true)
            verifiedPage = true
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && (!verifiedPage || titleButton.title != "Updated title") {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(verifiedPage && titleButton.title == "Updated title")
        precondition(scroll.documentView!.subviews.first === activeChip)
        precondition(page.bounds.size == viewport)
        print("PASS: hover reveal preserves focus; live title changes reuse chip; page sees dark preference")

        let navMenu = NSApp.mainMenu!.item(withTitle: "Navigation")!.submenu!
        let focus = navMenu.item(withTitle: "Address")!
        precondition(NSApp.sendAction(focus.action!, to: focus.target, from: focus))
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(!tabs.isHidden && !navigation.isHidden, "⌘L must reveal and keep editing controls")
        precondition(page.bounds.size == viewport, "Reveal must not resize WebKit")
        minimalWindow.makeFirstResponder(page)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(tabs.isHidden)
        let pin = NSApp.mainMenu!.item(withTitle: "View")!.submenu!.item(withTitle: "Always Show Controls")!
        precondition(NSApp.sendAction(pin.action!, to: pin.target, from: pin))
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(!tabs.isHidden && pin.state == .on)
        controller.prepareForDismissal()
        minimalWindow.orderOut(nil)
        withExtendedLifetime(controller) {}
        print("PASS: auto-hide, keyboard reveal, pinned controls, and invariant WebKit viewport")
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
