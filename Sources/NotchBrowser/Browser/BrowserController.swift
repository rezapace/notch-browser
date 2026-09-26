import AppKit
import WebKit

private final class BrowserTab {
    var webView: WKWebView?
    var observations: [NSKeyValueObservation] = []
    var error: String?
    var requestedURL: URL?
    var isHome: Bool { webView == nil }
    var needsRefresh = true
    let item = NSView()
    var titleButton: BrowserButton?
    var isSelected = false
    var title: String {
        if let error { return error }
        if isHome { return "New Tab" }
        return webView?.title.flatMap { $0.isEmpty ? nil : $0 }
            ?? (requestedURL ?? webView?.url)?.host ?? "Loading…"
    }
}

/// Native buttons retain accessibility, first-click behavior and keyboard navigation.
private final class BrowserButton: NSButton {
    var actionHandler: (() -> Void)?
    private var hovered = false

    init(title: String = "", symbol: String? = nil, tooltip: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.title = title
        actionHandler = action
        toolTip = tooltip
        setAccessibilityLabel(tooltip)
        isBordered = false
        bezelStyle = .inline
        font = .systemFont(ofSize: 12)
        contentTintColor = .white.withAlphaComponent(0.85)
        if let symbol {
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
            imagePosition = .imageOnly
            imageScaling = .scaleProportionallyDown
            symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        }
        target = self
        self.action = #selector(invoke)
        wantsLayer = true
        layer?.cornerRadius = 7
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { actionHandler?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateHover() }
    override func mouseExited(with event: NSEvent) { hovered = false; updateHover() }
    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    private func updateHover() {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(hovered && isEnabled ? 0.08 : 0).cgColor
    }
}

/// Minimal chrome only: horizontal tabs, previous/next, and a native URL field.
/// Empty tabs are native placeholders. A navigated tab keeps its WebView mounted.
final class BrowserController: NSObject, NSTextFieldDelegate, WKNavigationDelegate, WKUIDelegate {
    var onDismissRequested: (() -> Void)?
    private let window: WorkspaceWindow
    private let diagnostics: NavigationDiagnostics?
    private let root = BrowserRootView()
    private let tabStrip = NSView()
    private let toolbar = NSView()
    private let pages = NSView()
    private let tabScroll = NSScrollView()
    private let tabDocument = FlippedDocumentView()
    private let address = NSTextField()
    private var back: BrowserButton!
    private var forward: BrowserButton!
    private var tabs: [BrowserTab] = []
    private var selectedIndex = -1
    private var refreshPending = false
    private var warmUpWork: DispatchWorkItem?
    private var preparedWebView: WKWebView?
    private var warmNavigation: WKNavigation?
    // Useful for diagnostics without exposing tabs, URLs, or browsing data.
    var allocatedWebViewCount: Int {
        tabs.filter { $0.webView != nil }.count + (preparedWebView == nil ? 0 : 1)
    }
    private var tabLayoutDirty = true
    private var navigationDirty = true
    private var revealSelectionPending = false
    private var controlsCanRender: Bool { browserPresented && root.controlsVisible }
    private var chromeHideWork: DispatchWorkItem?
    private var browserPresented = false
    private var controlsPinned = false
    private var currentTab: BrowserTab? { tabs.indices.contains(selectedIndex) ? tabs[selectedIndex] : nil }

    init(window: WorkspaceWindow, diagnostics: NavigationDiagnostics? = nil) {
        self.window = window
        self.diagnostics = diagnostics
        super.init()
        buildChrome()
        makeMenus()
        addTab()
        // Let the native shell start first, then warm ONE reusable empty engine.
        // This avoids a cold-process penalty on the user's first URL without
        // creating WebViews for every blank tab or prefetching any website.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.allocatedWebViewCount == 0 else { return }
            let web = self.makeWebView(configuration: WebKitRuntime.configuration())
            self.preparedWebView = web
            web.navigationDelegate = self
            self.warmNavigation = web.loadHTMLString("<!doctype html><meta name='color-scheme' content='dark'><style>html{background:#131516}</style>", baseURL: nil)
            self.warmUpWork = nil
        }
        warmUpWork = work
        DispatchQueue.main.async(execute: work)
    }

    func prepareForPresentation() {
        browserPresented = window.isPresented
        root.layoutSubtreeIfNeeded()
        setControlsVisible(true)
        scheduleChromeHide()
    }
    func prepareForDismissal() {
        browserPresented = false
        chromeHideWork?.cancel()
        window.makeFirstResponder(nil)
    }
    func focusAddressIfHome() { if currentTab?.isHome == true { focusAddress(nil) } }

    private func setControlsVisible(_ visible: Bool) {
        if root.controlsVisible != visible {
            root.controlsVisible = visible
            tabStrip.isHidden = !visible
            toolbar.isHidden = !visible
        }
        // Also flush on presentation when controls were already marked visible.
        if visible { flushRefreshes() }
    }

    private func scheduleChromeHide() {
        chromeHideWork?.cancel()
        guard browserPresented else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.browserPresented else { return }
            let focused = self.window.firstResponder as? NSView
            let controlsFocused = focused.map {
                $0.isDescendant(of: self.tabStrip) || $0.isDescendant(of: self.toolbar)
            } ?? false
            guard BrowserChromePolicy.canHide(pointerInside: self.root.pointerInsideChrome,
                editing: self.address.currentEditor() != nil, controlsFocused: controlsFocused,
                hasSheet: self.window.attachedSheet != nil, isHome: self.currentTab?.isHome == true,
                pinned: self.controlsPinned || NSWorkspace.shared.isVoiceOverEnabled) else { return }
            self.setControlsVisible(false)
        }
        chromeHideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        chromeHideWork?.cancel()
        setControlsVisible(true)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        navigationDirty = true
        flushRefreshes()
        scheduleChromeHide()
    }

    @objc private func togglePinnedControls(_ sender: NSMenuItem) {
        controlsPinned.toggle()
        sender.state = controlsPinned ? .on : .off
        setControlsVisible(true)
        scheduleChromeHide()
    }

    private func buildChrome() {
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        root.appearance = NSAppearance(named: .darkAqua)
        root.onChromeHoverChanged = { [weak self] inside in
            guard let self, self.browserPresented else { return }
            if inside { self.chromeHideWork?.cancel(); self.setControlsVisible(true) }
            else { self.scheduleChromeHide() }
        }
        window.onFocusChanged = { [weak self] in self?.scheduleChromeHide() }
        window.installBrowser(root)
        root.setAccessibilityIdentifier("browser.root")
        for view in [pages, tabStrip, toolbar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        tabStrip.setAccessibilityIdentifier("browser.tabs")
        toolbar.setAccessibilityIdentifier("browser.navigation")
        pages.setAccessibilityIdentifier("browser.pages")
        // One outer shell mask supplies rounded lower corners; no nested page mask.
        pages.wantsLayer = true
        pages.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
        for chrome in [tabStrip, toolbar] {
            chrome.wantsLayer = true
            chrome.layer?.backgroundColor = NSColor.black.cgColor
        }
        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: root.topAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabStrip.heightAnchor.constraint(equalToConstant: 32),
            toolbar.topAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 36),
            pages.topAnchor.constraint(equalTo: root.topAnchor),
            pages.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            pages.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pages.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        tabScroll.translatesAutoresizingMaskIntoConstraints = false
        tabScroll.drawsBackground = false
        tabScroll.hasHorizontalScroller = true
        tabScroll.autohidesScrollers = true
        tabScroll.scrollerStyle = .overlay
        tabScroll.documentView = tabDocument
        tabStrip.addSubview(tabScroll)
        let plus = BrowserButton(symbol: "plus", tooltip: "New tab (⌘T)") { [weak self] in self?.newTab(nil) }
        plus.translatesAutoresizingMaskIntoConstraints = false
        tabStrip.addSubview(plus)
        NSLayoutConstraint.activate([
            tabScroll.leadingAnchor.constraint(equalTo: tabStrip.leadingAnchor),
            tabScroll.topAnchor.constraint(equalTo: tabStrip.topAnchor),
            tabScroll.bottomAnchor.constraint(equalTo: tabStrip.bottomAnchor),
            tabScroll.trailingAnchor.constraint(equalTo: plus.leadingAnchor, constant: -2),
            plus.trailingAnchor.constraint(equalTo: tabStrip.trailingAnchor, constant: -2),
            plus.centerYAnchor.constraint(equalTo: tabStrip.centerYAnchor),
            plus.widthAnchor.constraint(equalToConstant: 28), plus.heightAnchor.constraint(equalToConstant: 28)
        ])

        back = BrowserButton(symbol: "chevron.left", tooltip: "Previous page (⌘[)") { [weak self] in self?.goBack(nil) }
        forward = BrowserButton(symbol: "chevron.right", tooltip: "Next page (⌘])") { [weak self] in self?.goForward(nil) }
        let well = NSView()
        well.wantsLayer = true
        well.layer?.cornerRadius = 9
        well.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.085).cgColor
        for view in [back!, forward!, well] {
            view.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(view)
        }
        address.translatesAutoresizingMaskIntoConstraints = false
        address.isBordered = false
        address.isBezeled = false
        address.drawsBackground = false
        address.focusRingType = .none
        address.font = .systemFont(ofSize: 12)
        address.textColor = .white.withAlphaComponent(0.9)
        address.placeholderString = "Search or enter URL"
        address.setAccessibilityLabel("URL")
        address.delegate = self
        address.target = self
        address.action = #selector(navigateFromAddress(_:))
        address.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        well.addSubview(address)
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
            back.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            back.widthAnchor.constraint(equalToConstant: 28), back.heightAnchor.constraint(equalToConstant: 28),
            forward.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 2),
            forward.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            forward.widthAnchor.constraint(equalToConstant: 28), forward.heightAnchor.constraint(equalToConstant: 28),
            well.leadingAnchor.constraint(equalTo: forward.trailingAnchor, constant: 4),
            well.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
            well.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor), well.heightAnchor.constraint(equalToConstant: 30),
            address.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 10),
            address.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -10),
            address.centerYAnchor.constraint(equalTo: well.centerYAnchor)
        ])
    }

    // MARK: Tabs / WebKit

    @discardableResult
    private func addTab(configuration: WKWebViewConfiguration? = nil) -> BrowserTab {
        let tab = BrowserTab()
        installTabItem(tab)
        tabs.append(tab)
        tabLayoutDirty = true
        // window.open must return a real WebView synchronously with its original config.
        if let configuration { ensureWebView(for: tab, configuration: configuration) }
        selectTab(tabs.count - 1)
        return tab
    }

    private func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let started = diagnostics.map { _ in ProcessInfo.processInfo.systemUptime }
        root.layoutSubtreeIfNeeded()
        let web = WKWebView(frame: pages.bounds, configuration: configuration)
        web.appearance = NSAppearance(named: .darkAqua)
        web.underPageBackgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.isHidden = true
        #if DEBUG
        if #available(macOS 13.3, *) { web.isInspectable = true }
        #endif
        if let started { diagnostics?.created(web, since: started) }
        return web
    }

    @discardableResult
    private func ensureWebView(for tab: BrowserTab, configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        if let web = tab.webView { return web }
        warmUpWork?.cancel()
        warmUpWork = nil
        let web: WKWebView
        if let configuration {
            // A popup must not consume the spare: its related configuration is mandatory.
            web = makeWebView(configuration: configuration)
        } else if let preparedWebView {
            web = preparedWebView
            self.preparedWebView = nil
            web.stopLoading()
        } else {
            web = makeWebView(configuration: WebKitRuntime.configuration())
        }
        tab.webView = web
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isHidden = tab !== currentTab
        pages.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: pages.topAnchor), web.bottomAnchor.constraint(equalTo: pages.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: pages.leadingAnchor), web.trailingAnchor.constraint(equalTo: pages.trailingAnchor)
        ])
        // Coalesce URL/title/back/forward changes into one main-runloop update.
        let refresh: () -> Void = { [weak self, weak tab] in
            guard let self, let tab else { return }
            self.scheduleRefresh(tab)
        }
        tab.observations = [
            web.observe(\.url) { _, _ in refresh() },
            web.observe(\.title) { _, _ in refresh() },
            web.observe(\.canGoBack) { _, _ in refresh() },
            web.observe(\.canGoForward) { _, _ in refresh() }
        ]
        root.layoutSubtreeIfNeeded()
        return web
    }

    private func selectTab(_ index: Int) {
        guard tabs.indices.contains(index), index != selectedIndex else { return }
        window.makeFirstResponder(nil)
        currentTab?.webView?.isHidden = true
        selectedIndex = index
        currentTab?.webView?.isHidden = false
        tabLayoutDirty = true
        navigationDirty = true
        revealSelectionPending = true
        setControlsVisible(true)
        scheduleChromeHide()
    }

    private func closeTab(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasSelected = index == selectedIndex
        tab.observations.removeAll()
        if let web = tab.webView {
            diagnostics?.closed(web)
            web.stopLoading()
            web.navigationDelegate = nil
            web.uiDelegate = nil
            web.removeFromSuperview()
        }
        tab.item.removeFromSuperview()
        tabs.remove(at: index)
        tabLayoutDirty = true
        if tabs.isEmpty { selectedIndex = -1; addTab(); return }
        if wasSelected { selectedIndex = -1; selectTab(min(index, tabs.count - 1)) }
        else {
            if index < selectedIndex { selectedIndex -= 1 }
            flushRefreshes()
        }
    }

    private func installTabItem(_ tab: BrowserTab) {
        let item = tab.item
        item.wantsLayer = true
        item.layer?.cornerRadius = 8
        item.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.025).cgColor
        let select = BrowserButton(title: tab.title, tooltip: tab.title) { [weak self, weak tab] in
            guard let self, let tab, let index = self.tabs.firstIndex(where: { $0 === tab }) else { return }
            self.selectTab(index)
        }
        select.frame = NSRect(x: 6, y: 0, width: 124, height: 28)
        select.alignment = .left
        select.lineBreakMode = .byTruncatingTail
        let close = BrowserButton(symbol: "xmark", tooltip: "Close tab") { [weak self, weak tab] in
            if let tab { self?.closeTab(tab) }
        }
        close.frame = NSRect(x: 134, y: 1, width: 24, height: 26)
        tab.titleButton = select
        item.addSubview(select)
        item.addSubview(close)
        tabDocument.addSubview(item)
    }

    private func updateTabTitle(_ tab: BrowserTab) {
        let title = tab.title
        guard tab.titleButton?.title != title else { return }
        tab.titleButton?.title = title
        tab.titleButton?.toolTip = title
        tab.titleButton?.setAccessibilityLabel(title)
    }

    private func scheduleRefresh(_ tab: BrowserTab) {
        tab.needsRefresh = true
        if tab === currentTab { navigationDirty = true }
        // WebKit remains the live model. Hidden chrome only accumulates dirty flags.
        guard controlsCanRender, !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.flushRefreshes()
        }
    }

    private func flushRefreshes() {
        guard controlsCanRender else { return }
        renderTabs()
        for tab in tabs where tab.needsRefresh {
            tab.needsRefresh = false
            updateTabTitle(tab)
        }
        if navigationDirty { syncNavigation() }
    }

    private func renderTabs() {
        let width: CGFloat = 164
        let frame = NSRect(x: 0, y: 0, width: max(tabScroll.contentSize.width, CGFloat(tabs.count) * width), height: 30)
        guard tabLayoutDirty || tabDocument.frame != frame else { return }
        tabLayoutDirty = false
        if tabDocument.frame != frame { tabDocument.frame = frame }
        for (index, tab) in tabs.enumerated() {
            let frame = NSRect(x: CGFloat(index) * width, y: 1, width: width - 4, height: 28)
            if tab.item.frame != frame { tab.item.frame = frame }
            let selected = index == selectedIndex
            if tab.isSelected != selected {
                tab.isSelected = selected
                tab.item.layer?.backgroundColor = NSColor.white.withAlphaComponent(selected ? 0.10 : 0.025).cgColor
            }
        }
        if revealSelectionPending, tabs.indices.contains(selectedIndex) {
            tabDocument.scrollToVisible(tabs[selectedIndex].item.frame)
            tabScroll.reflectScrolledClipView(tabScroll.contentView)
        }
        revealSelectionPending = false
    }

    private func syncNavigation() {
        navigationDirty = true
        guard controlsCanRender, let tab = currentTab else { return }
        navigationDirty = false
        let canGoBack = tab.webView?.canGoBack ?? false
        let canGoForward = tab.webView?.canGoForward ?? false
        if back.isEnabled != canGoBack { back.isEnabled = canGoBack }
        if forward.isEnabled != canGoForward { forward.isEnabled = canGoForward }
        if address.currentEditor() == nil {
            let text = (tab.requestedURL ?? tab.webView?.url)?.absoluteString ?? ""
            if address.stringValue != text { address.stringValue = text }
        }
        if address.toolTip != tab.error { address.toolTip = tab.error }
        let title = "NotchBrowser · \(tab.title)"
        if window.title != title { window.title = title }
    }

    @objc private func navigateFromAddress(_ sender: Any?) {
        let input = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        let target: URL?
        let lower = input.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { target = URL(string: input) }
        else if !input.contains(" ") && (input.contains(".") || lower.hasPrefix("localhost")) { target = URL(string: "https://" + input) }
        else {
            var search = URLComponents(string: "https://www.google.com/search")!
            search.queryItems = [URLQueryItem(name: "q", value: input)]
            target = search.url
        }
        guard let target else { return }
        navigate(to: target)
    }

    /// Materialize the selected tab only when a navigation is actually requested.
    func navigate(to target: URL) {
        guard let tab = currentTab else { return }
        tab.error = nil
        tab.requestedURL = target
        let web = ensureWebView(for: tab)
        window.makeFirstResponder(web)
        scheduleRefresh(tab)
        flushRefreshes()
        web.load(URLRequest(url: target))
        scheduleChromeHide()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        if command == #selector(NSResponder.insertNewline(_:)) { navigateFromAddress(nil); return true }
        if command == #selector(NSResponder.cancelOperation(_:)) {
            window.makeFirstResponder(currentTab?.webView)
            syncNavigation()
            return true
        }
        return false
    }

    private func isWarmNavigation(_ navigation: WKNavigation?) -> Bool {
        guard let navigation, let warmNavigation else { return false }
        return navigation === warmNavigation
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !isWarmNavigation(navigation) else { return }
        diagnostics?.started(webView, navigation: navigation)
        if let tab = tabs.first(where: { $0.webView === webView }) {
            tab.error = nil
            scheduleRefresh(tab)
        }
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard !isWarmNavigation(navigation) else { return }
        diagnostics?.committed(webView, navigation: navigation)
        if let tab = tabs.first(where: { $0.webView === webView }) {
            tab.requestedURL = nil
            scheduleRefresh(tab)
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if isWarmNavigation(navigation) { warmNavigation = nil; return }
        diagnostics?.finished(webView, navigation: navigation)
        if let tab = tabs.first(where: { $0.webView === webView }) { scheduleRefresh(tab) }
        scheduleChromeHide()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if isWarmNavigation(navigation) { warmNavigation = nil; return }
        diagnostics?.failed(webView, navigation: navigation, code: (error as NSError).code)
        showFailure(webView, error: error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if isWarmNavigation(navigation) { warmNavigation = nil; return }
        diagnostics?.failed(webView, navigation: navigation, code: (error as NSError).code)
        showFailure(webView, error: error)
    }
    private func showFailure(_ webView: WKWebView, error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        if let tab = tabs.first(where: { $0.webView === webView }) {
            tab.error = "Could not load page"
            scheduleRefresh(tab)
        }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        diagnostics?.terminated(webView)
        if let tab = tabs.first(where: { $0.webView === webView }) {
            tab.error = "Reload with ⌘R"
            scheduleRefresh(tab)
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        addTab(configuration: configuration).webView
    }
    func webViewDidClose(_ webView: WKWebView) {
        if let tab = tabs.first(where: { $0.webView === webView }) { closeTab(tab) }
    }

    // Keyboard/menu actions stay available without extra on-screen controls.
    @objc private func newTab(_ sender: Any?) { addTab(); focusAddress(nil) }
    @objc private func closeCurrentTab(_ sender: Any?) { if let tab = currentTab { closeTab(tab) } }
    @objc private func focusAddress(_ sender: Any?) {
        chromeHideWork?.cancel()
        setControlsVisible(true)
        window.makeFirstResponder(address)
        address.selectText(nil)
    }
    @objc private func goBack(_ sender: Any?) { currentTab?.webView?.goBack() }
    @objc private func goForward(_ sender: Any?) { currentTab?.webView?.goForward() }
    @objc private func reload(_ sender: Any?) {
        guard let tab = currentTab, let web = tab.webView else { return }
        tab.error = nil
        if let target = tab.requestedURL { navigate(to: target) }
        else { web.reload() }
        scheduleRefresh(tab)
    }
    @objc private func collapse(_ sender: Any?) { onDismissRequested?() }
    @objc private func jumpTab(_ sender: NSMenuItem) { selectTab(sender.tag) }

    private func makeMenus() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            item.submenu = submenu
            main.addItem(item)
            return submenu
        }
        func action(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String) {
            menu.addItem(withTitle: title, action: selector, keyEquivalent: key).target = self
        }
        menu("NotchBrowser").addItem(withTitle: "Quit NotchBrowser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = menu("File")
        action(file, "New Tab", #selector(newTab(_:)), "t")
        action(file, "Close Tab", #selector(closeCurrentTab(_:)), "w")
        let hide = file.addItem(withTitle: "Collapse to Notch", action: #selector(collapse(_:)), keyEquivalent: "w")
        hide.target = self; hide.keyEquivalentModifierMask = [.command, .shift]
        let edit = menu("Edit")
        for (title, selector, key) in [("Undo", #selector(UndoManager.undo), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        action(menu("View"), "Always Show Controls", #selector(togglePinnedControls(_:)), "")
        let navigation = menu("Navigation")
        action(navigation, "Address", #selector(focusAddress(_:)), "l")
        action(navigation, "Previous", #selector(goBack(_:)), "[")
        action(navigation, "Next", #selector(goForward(_:)), "]")
        action(navigation, "Reload", #selector(reload(_:)), "r")
        for number in 1...9 {
            let item = navigation.addItem(withTitle: "Tab \(number)", action: #selector(jumpTab(_:)), keyEquivalent: "\(number)")
            item.target = self; item.tag = number - 1
        }
        NSApp.mainMenu = main
    }
}
