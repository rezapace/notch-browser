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
        var timingRecords: [String] = []
        let diagnostics = NavigationDiagnostics { timingRecords.append($0) }
        let controller = BrowserController(window: minimalWindow, diagnostics: diagnostics)
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
        precondition(pages.subviews.isEmpty && timingRecords.isEmpty, "Startup/presentation must not create a WebView")
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        precondition(pages.subviews.isEmpty && controller.allocatedWebViewCount == 1)
        precondition(timingRecords.count == 1 && timingRecords[0].contains("webview_created"))
        print("PASS: native startup defers one reusable engine warm-up; empty tabs remain native")

        let file = NSApp.mainMenu!.item(withTitle: "File")!.submenu!
        func invoke(_ title: String) {
            let item = file.item(withTitle: title)!
            precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
        }
        for _ in 0..<20 { invoke("New Tab") }
        precondition(pages.subviews.isEmpty && controller.allocatedWebViewCount == 1)
        precondition(timingRecords.count == 1, "Many blank tabs must share a single prepared engine")
        precondition(scroll.documentView!.subviews.count == 21)
        for _ in 0..<20 { invoke("Close Tab") }
        precondition(scroll.documentView!.subviews.count == 1)
        weak var closedWebView: WKWebView?
        autoreleasepool {
            invoke("New Tab")
            precondition(pages.subviews.isEmpty)
            controller.navigate(to: URL(string: "about:blank")!)
            precondition(pages.subviews.count == 1 && controller.allocatedWebViewCount == 1)
            precondition(timingRecords.count == 1, "First navigation must adopt the prepared WebView, not create another")
            let web = pages.subviews.last as! WKWebView
            precondition(web.configuration.websiteDataStore === WebKitRuntime.dataStore)
            precondition(web.configuration.websiteDataStore.isPersistent)
            precondition(!web.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
            precondition(web.appearance?.name == .darkAqua)
            #if !DEBUG
            if #available(macOS 13.3, *) { precondition(!web.isInspectable) }
            #endif
            closedWebView = web
            invoke("Close Tab")
            precondition(pages.subviews.isEmpty)
            invoke("Close Tab")
            precondition(pages.subviews.isEmpty && scroll.documentView!.subviews.count == 1)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        precondition(closedWebView == nil, "A closed tab's WebView should be released")
        print("PASS: lazy empty tabs, first navigation, persistent store, dark appearance, and WebView cleanup")

        // Off-screen, nonactivating panel: exercise UI state without moving the user's pointer.
        minimalWindow.present(on: display)
        pumpEvents(for: 0.35, checkingTopOf: minimalWindow, on: display)
        minimalWindow.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        controller.prepareForPresentation()
        let navigationMenu = NSApp.mainMenu!.item(withTitle: "Navigation")!.submenu!
        for title in ["Previous", "Next", "Reload"] {
            let item = navigationMenu.item(withTitle: title)!
            precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
        }
        precondition(pages.subviews.isEmpty, "Blank tab shortcuts must not create a WebView")
        controller.navigate(to: URL(string: "about:blank")!)
        let page = pages.subviews.first as! WKWebView
        precondition(page.bounds.size == pages.bounds.size, "First navigation starts with the full viewport")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        page.loadHTMLString("<!doctype html><title>Local test</title><body>Test</body>",
            baseURL: URL(string: "https://notch-browser.invalid/"))
        minimalWindow.makeFirstResponder(page)
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        precondition(tabs.isHidden && navigation.isHidden, "Controls should auto-hide away from pointer/editor")
        let hiddenHideCount = controller.refreshCounts.hideScheduled
        controller.webView(page, didFinish: nil)
        precondition(controller.refreshCounts.hideScheduled == hiddenHideCount, "Hidden controls must not schedule another hide")
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
        let previousTitle = titleButton.title
        var verifiedPage = false
        page.evaluateJavaScript("document.title = 'Updated title'; matchMedia('(prefers-color-scheme: dark)').matches") { result, error in
            precondition(error == nil && result as? Bool == true)
            verifiedPage = true
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && (!verifiedPage || page.title != "Updated title") {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        precondition(verifiedPage && page.title == "Updated title")
        precondition(titleButton.title == previousTitle, "Hidden controls should not render title updates")
        precondition(scroll.documentView!.subviews.first === activeChip)
        precondition(page.bounds.size == viewport)
        print("PASS: hidden controls defer rendering while the page model stays live; dark preference preserved")

        let navMenu = NSApp.mainMenu!.item(withTitle: "Navigation")!.submenu!
        let focus = navMenu.item(withTitle: "Address")!
        precondition(NSApp.sendAction(focus.action!, to: focus.target, from: focus))
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(!tabs.isHidden && !navigation.isHidden, "⌘L must reveal and keep editing controls")
        precondition(titleButton.title == "Updated title", "Reveal must flush deferred updates")
        precondition(page.bounds.size == viewport, "Reveal must not resize WebKit")
        let editor = minimalWindow.firstResponder
        let sameTab = navMenu.item(withTitle: "Tab 1")!
        precondition(NSApp.sendAction(sameTab.action!, to: sameTab.target, from: sameTab))
        precondition(minimalWindow.firstResponder === editor && !page.isHidden)
        precondition(pages.subviews.first === page, "Reselecting the active tab must be a no-op")
        let fieldEditor = editor as! NSTextView
        fieldEditor.string = "unfinished input"
        let beforeTitleChange = controller.refreshCounts
        var changedWhileEditing = false
        page.evaluateJavaScript("document.title = 'While editing'") { _, error in
            precondition(error == nil)
            changedWhileEditing = true
        }
        let editingDeadline = Date().addingTimeInterval(2)
        while Date() < editingDeadline && (!changedWhileEditing || titleButton.title != "While editing") {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(changedWhileEditing && titleButton.title == "While editing")
        precondition(fieldEditor.string == "unfinished input", "Metadata refresh must preserve the active editor")
        precondition(minimalWindow.title == "NotchBrowser · While editing")
        precondition(controller.refreshCounts.title > beforeTitleChange.title)
        precondition(controller.refreshCounts.address == beforeTitleChange.address)
        precondition(controller.refreshCounts.history == beforeTitleChange.history)
        print("PASS: title-only KVO updates tab/window titles without processing address or history")
        minimalWindow.makeFirstResponder(page)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(tabs.isHidden)
        let pin = NSApp.mainMenu!.item(withTitle: "View")!.submenu!.item(withTitle: "Always Show Controls")!
        precondition(NSApp.sendAction(pin.action!, to: pin.target, from: pin))
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        precondition(!tabs.isHidden && pin.state == .on)
        let pinnedHideCount = controller.refreshCounts.hideScheduled
        controller.webView(page, didFinish: nil)
        precondition(controller.refreshCounts.hideScheduled == pinnedHideCount, "Pinned controls must not schedule a hide")
        invoke("New Tab")
        precondition(pages.subviews.count == 1 && page.isHidden)
        let address = navigation.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }.first!
        precondition(address.stringValue.isEmpty, "Blank tab must not inherit another tab's URL")
        precondition(NSApp.sendAction(sameTab.action!, to: sameTab.target, from: sameTab))
        precondition(!page.isHidden && pages.subviews.count == 1)
        print("PASS: blank/loaded tab switching preserves the existing page and editing focus")

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.applicationNameForUserAgent = "PopupConfigTest"
        let popup = controller.webView(page, createWebViewWith: config,
            for: WKNavigationAction(), windowFeatures: WKWindowFeatures())!
        precondition(popup.configuration.websiteDataStore === config.websiteDataStore)
        precondition(!popup.configuration.websiteDataStore.isPersistent)
        precondition(popup.configuration.applicationNameForUserAgent == "PopupConfigTest")
        precondition(pages.subviews.count == 2, "Popup WebView must be returned immediately")
        invoke("Close Tab")
        precondition(pages.subviews.count == 1)
        print("PASS: popup creation is eager and preserves WebKit's supplied configuration")

        let server = try! LocalHTTPServer()
        let serverDeadline = Date().addingTimeInterval(3)
        while server.port == nil && Date() < serverDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        guard let port = server.port else { fatalError("Loopback fixture server did not start") }
        precondition(NSApp.sendAction(sameTab.action!, to: sameTab.target, from: sameTab))
        let beforeNetwork = timingRecords.count
        controller.navigate(to: URL(string: "http://127.0.0.1:\(port)/fixture?do-not-log=fixture")!)
        let networkDeadline = Date().addingTimeInterval(5)
        while Date() < networkDeadline && !timingRecords.dropFirst(beforeNetwork).contains(where: { $0.contains("navigation_timing") }) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let networkRecord = timingRecords.dropFirst(beforeNetwork).first { $0.contains("navigation_timing") }
        precondition(networkRecord != nil, "Real navigation must produce timing metrics")
        precondition(page.url?.port == Int(port) && page.title == "Timing fixture", "Fixture must actually load, not about:blank")
        let networkMetrics = try! JSONSerialization.jsonObject(with: Data(networkRecord!.utf8)) as! [String: Any]
        precondition(networkMetrics["request_to_first_byte_ms"] is NSNumber && networkMetrics["download_ms"] is NSNumber)
        precondition(timingRecords.allSatisfy { !$0.contains("127.0.0.1") && !$0.contains("do-not-log") })
        print("PASS: loopback HTTP load produces Navigation Timing without logging its URL/query")

        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        minimalWindow.makeFirstResponder(page)
        var historyChanged = false
        page.evaluateJavaScript("document.title = ''; history.pushState({}, '', '/history-change')") { _, error in
            precondition(error == nil)
            historyChanged = true
        }
        let historyDeadline = Date().addingTimeInterval(3)
        while Date() < historyDeadline && (!historyChanged || !address.stringValue.hasSuffix("/history-change") || titleButton.title != "127.0.0.1") {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(historyChanged && address.stringValue == page.url?.absoluteString)
        precondition(titleButton.title == "127.0.0.1" && minimalWindow.title == "NotchBrowser · 127.0.0.1")
        let backButton = navigation.subviews.compactMap { $0 as? NSButton }.first!
        precondition(page.canGoBack && backButton.isEnabled)
        precondition(NSApp.sendAction(focus.action!, to: focus.target, from: focus))
        let historyEditor = minimalWindow.firstResponder as! NSTextView
        historyEditor.string = "uncommitted address"
        var replacedHistory = false
        page.evaluateJavaScript("history.replaceState({}, '', '/while-editing')") { _, error in
            precondition(error == nil)
            replacedHistory = true
        }
        let replaceDeadline = Date().addingTimeInterval(3)
        while Date() < replaceDeadline && (!replacedHistory || page.url?.path != "/while-editing") {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(replacedHistory && page.url?.path == "/while-editing")
        precondition(historyEditor.string == "uncommitted address")
        precondition(controller.control(address, textView: historyEditor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        precondition(address.stringValue == page.url?.absoluteString)
        print("PASS: same-document history updates address/buttons and fallback titles; Escape restores the latest URL")

        // A real background navigation must update its chip, not the active toolbar's timer.
        let background = controller.webView(page, createWebViewWith: WebKitRuntime.configuration(),
            for: WKNavigationAction(), windowFeatures: WKWindowFeatures())!
        let backgroundTitle = scroll.documentView!.subviews.last!.subviews.first as! NSButton
        precondition(NSApp.sendAction(sameTab.action!, to: sameTab.target, from: sameTab))
        precondition(NSApp.sendAction(pin.action!, to: pin.target, from: pin))
        precondition(pin.state == .off)
        precondition(NSApp.sendAction(focus.action!, to: focus.target, from: focus))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let beforeBackground = controller.refreshCounts
        let activeTitle = minimalWindow.title
        background.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/background")!))
        let backgroundDeadline = Date().addingTimeInterval(5)
        while Date() < backgroundDeadline && (background.isLoading || backgroundTitle.title != "Timing fixture") {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(!background.isLoading && backgroundTitle.title == "Timing fixture")
        precondition(background.isHidden && !page.isHidden && minimalWindow.title == activeTitle)
        precondition(controller.refreshCounts.hideScheduled == beforeBackground.hideScheduled)
        precondition(controller.refreshCounts.title == beforeBackground.title)
        precondition(controller.refreshCounts.address == beforeBackground.address)
        precondition(controller.refreshCounts.history == beforeBackground.history)
        controller.webViewDidClose(background)
        let afterClose = controller.refreshCounts.hideScheduled
        controller.webView(background, didFinish: nil)
        precondition(controller.refreshCounts.hideScheduled == afterClose)
        print("PASS: background and closed-page finishes do not reschedule the active toolbar; background chip stays current")

        let metrics = NavigationDiagnostics.sanitizedMetrics([
            "dns_ms": 2.5, "connect_ms": -1, "tls_ms": true, "load_ms": Double.infinity,
            "download_ms": "private-data", "url": "https://private.invalid/?secret=example",
            "dom_content_loaded_ms": 10.0
        ])
        precondition(metrics == ["dns_ms": 2.5, "dom_content_loaded_ms": 10])
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let records = timingRecords.map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        precondition(records.contains { $0["event"] as? String == "webview_created" })
        precondition(records.contains { $0["event"] as? String == "navigation_started" })
        precondition(records.contains { $0["event"] as? String == "navigation_finished" })
        precondition(timingRecords.allSatisfy { !$0.contains("invalid") && !$0.contains("Updated title") && !$0.contains("https:") })
        var isolatedRecords: [String] = []
        let isolated = NavigationDiagnostics { isolatedRecords.append($0) }
        isolated.created(popup, since: ProcessInfo.processInfo.systemUptime)
        let oldNavigation = popup.loadHTMLString("<title>old</title>", baseURL: nil)!
        let newNavigation = popup.loadHTMLString("<title>new</title>", baseURL: nil)!
        isolated.started(popup, navigation: oldNavigation)
        isolated.started(popup, navigation: newNavigation)
        let count = isolatedRecords.count
        isolated.failed(popup, navigation: oldNavigation, code: NSURLErrorCancelled)
        precondition(isolatedRecords.count == count, "Stale callbacks must not affect a newer navigation")
        isolated.closed(popup)
        isolated.finished(popup, navigation: newNavigation)
        precondition(isolatedRecords.count == count, "Closed tabs must not emit further timings")
        popup.stopLoading()
        print("PASS: opt-in diagnostics report numeric timings only and reject stale/closed callbacks")

        let earlyWindow = WorkspaceWindow()
        earlyWindow.reposition(on: display)
        var earlyRecords: [String] = []
        let early = BrowserController(window: earlyWindow, diagnostics: NavigationDiagnostics { earlyRecords.append($0) })
        let warmDeadline = Date().addingTimeInterval(2)
        while early.allocatedWebViewCount == 0 && Date() < warmDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
        }
        precondition(early.allocatedWebViewCount == 1)
        early.navigate(to: URL(string: "http://127.0.0.1:\(port)/early")!)
        let earlyRoot = earlyWindow.contentView!.subviews.first { $0.accessibilityIdentifier() == "browser.root" }!
        let earlyPages = earlyRoot.subviews.first { $0.accessibilityIdentifier() == "browser.pages" }!
        let earlyWeb = earlyPages.subviews.first as! WKWebView
        let earlyDeadline = Date().addingTimeInterval(5)
        while Date() < earlyDeadline && (earlyWeb.isLoading || earlyWeb.title != "Timing fixture") {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        precondition(earlyWeb.url?.path == "/early" && earlyWeb.title == "Timing fixture")
        precondition(early.allocatedWebViewCount == 1)
        precondition(earlyRecords.filter { $0.contains("navigation_started") }.count == 1,
                     "Warm-up callbacks must not be attributed to the real navigation")
        withExtendedLifetime(early) {}
        withExtendedLifetime(server) {}
        print("PASS: immediate navigation safely adopts/cancels in-flight warm-up without a second WebView")
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
