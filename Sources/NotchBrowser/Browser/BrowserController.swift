import AppKit
import WebKit

private final class BrowserTab {
    let webView: WKWebView
    var observations: [NSKeyValueObservation] = []
    var error: String?
    var isHome = true
    var title: String {
        if let error { return error }
        if isHome { return "New Tab" }
        return webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? webView.url?.host ?? "Loading…"
    }
    init(_ webView: WKWebView) { self.webView = webView }
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
/// The browser root and one WebView per tab stay mounted through notch transitions.
final class BrowserController: NSObject, NSTextFieldDelegate, WKNavigationDelegate, WKUIDelegate {
    var onDismissRequested: (() -> Void)?
    private let window: WorkspaceWindow
    private let root = NSView()
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
    private var currentTab: BrowserTab? { tabs.indices.contains(selectedIndex) ? tabs[selectedIndex] : nil }

    init(window: WorkspaceWindow) {
        self.window = window
        super.init()
        buildChrome()
        makeMenus()
        addTab()
    }

    func prepareForPresentation() { root.layoutSubtreeIfNeeded(); renderTabs(); syncNavigation() }
    func prepareForDismissal() { window.makeFirstResponder(nil) }
    func focusAddressIfHome() { if currentTab?.isHome == true { focusAddress(nil) } }

    private func buildChrome() {
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        window.installBrowser(root)
        root.setAccessibilityIdentifier("browser.root")
        for view in [tabStrip, toolbar, pages] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        tabStrip.setAccessibilityIdentifier("browser.tabs")
        toolbar.setAccessibilityIdentifier("browser.navigation")
        pages.setAccessibilityIdentifier("browser.pages")
        pages.wantsLayer = true
        pages.layer?.cornerRadius = WorkspaceGeometry.contentCornerRadius
        pages.layer?.masksToBounds = true
        pages.layer?.backgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1).cgColor
        NSLayoutConstraint.activate([
            tabStrip.topAnchor.constraint(equalTo: root.topAnchor),
            tabStrip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tabStrip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tabStrip.heightAnchor.constraint(equalToConstant: 30),
            toolbar.topAnchor.constraint(equalTo: tabStrip.bottomAnchor, constant: 2),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            pages.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 4),
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

    private func addTab(configuration: WKWebViewConfiguration = WKWebViewConfiguration(), home: Bool = true) {
        if home {
            configuration.applicationNameForUserAgent = "Version/\(max(26, ProcessInfo.processInfo.operatingSystemVersion.majorVersion)).0 Safari/605.1.15"
        }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.appearance = NSAppearance(named: .aqua)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.isHidden = true
        if #available(macOS 13.3, *) { web.isInspectable = true }
        pages.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: pages.topAnchor), web.bottomAnchor.constraint(equalTo: pages.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: pages.leadingAnchor), web.trailingAnchor.constraint(equalTo: pages.trailingAnchor)
        ])
        let tab = BrowserTab(web)
        tab.isHome = home
        // URL/title observations also handle SPA navigation and back/forward changes.
        let refresh: () -> Void = { [weak self, weak tab] in
            DispatchQueue.main.async { [weak self, weak tab] in
                guard let self, let tab, self.tabs.contains(where: { $0 === tab }) else { return }
                if let url = tab.webView.url { tab.isHome = url.absoluteString == "about:blank" }
                if tab === self.currentTab { self.syncNavigation() }
                self.renderTabs()
            }
        }
        tab.observations = [
            web.observe(\.url) { _, _ in refresh() },
            web.observe(\.title) { _, _ in refresh() },
            web.observe(\.canGoBack) { _, _ in refresh() },
            web.observe(\.canGoForward) { _, _ in refresh() }
        ]
        tabs.append(tab)
        selectTab(tabs.count - 1)
        if home {
            web.loadHTMLString("<!doctype html><meta name='color-scheme' content='dark'><style>html,body{margin:0;background:#131516}</style>", baseURL: nil)
        }
    }

    private func selectTab(_ index: Int) {
        guard tabs.indices.contains(index) else { return }
        window.makeFirstResponder(nil)
        currentTab?.webView.isHidden = true
        selectedIndex = index
        currentTab?.webView.isHidden = false
        syncNavigation()
        renderTabs()
    }

    private func closeTab(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        let wasSelected = index == selectedIndex
        tab.observations.removeAll()
        tab.webView.stopLoading()
        tab.webView.navigationDelegate = nil
        tab.webView.uiDelegate = nil
        tab.webView.removeFromSuperview()
        tabs.remove(at: index)
        if tabs.isEmpty { selectedIndex = -1; addTab(); return }
        if wasSelected { selectedIndex = -1; selectTab(min(index, tabs.count - 1)) }
        else {
            if index < selectedIndex { selectedIndex -= 1 }
            renderTabs()
        }
    }

    private func renderTabs() {
        tabDocument.subviews.forEach { $0.removeFromSuperview() }
        let width: CGFloat = 164
        tabDocument.frame = NSRect(x: 0, y: 0, width: max(tabScroll.contentSize.width, CGFloat(tabs.count) * width), height: 30)
        for (index, tab) in tabs.enumerated() {
            let item = NSView(frame: NSRect(x: CGFloat(index) * width, y: 1, width: width - 4, height: 28))
            item.wantsLayer = true
            item.layer?.cornerRadius = 8
            item.layer?.backgroundColor = NSColor.white.withAlphaComponent(index == selectedIndex ? 0.10 : 0.025).cgColor
            let select = BrowserButton(title: tab.title, tooltip: tab.title) { [weak self, weak tab] in
                guard let self, let tab, let index = self.tabs.firstIndex(where: { $0 === tab }) else { return }
                self.selectTab(index)
            }
            select.frame = NSRect(x: 6, y: 0, width: width - 40, height: 28)
            select.alignment = .left
            select.lineBreakMode = .byTruncatingTail
            let close = BrowserButton(symbol: "xmark", tooltip: "Close tab") { [weak self, weak tab] in
                if let tab { self?.closeTab(tab) }
            }
            close.frame = NSRect(x: width - 30, y: 1, width: 24, height: 26)
            item.addSubview(select)
            item.addSubview(close)
            tabDocument.addSubview(item)
        }
        let x = max(0, CGFloat(selectedIndex + 1) * width - tabScroll.contentSize.width)
        tabScroll.contentView.scroll(to: NSPoint(x: x, y: 0))
        tabScroll.reflectScrolledClipView(tabScroll.contentView)
    }

    private func syncNavigation() {
        guard let tab = currentTab else { return }
        back.isEnabled = tab.webView.canGoBack
        forward.isEnabled = tab.webView.canGoForward
        if address.currentEditor() == nil {
            address.stringValue = tab.isHome ? "" : (tab.webView.url?.absoluteString ?? address.stringValue)
        }
        address.toolTip = tab.error
        window.title = "NotchBrowser · \(tab.title)"
    }

    @objc private func navigateFromAddress(_ sender: Any?) {
        let input = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, let tab = currentTab else { return }
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
        tab.error = nil
        tab.isHome = false
        window.makeFirstResponder(tab.webView)
        address.stringValue = target.absoluteString
        tab.webView.load(URLRequest(url: target))
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

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        tabs.first(where: { $0.webView === webView })?.error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { syncNavigation(); renderTabs() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showFailure(webView, error: error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showFailure(webView, error: error) }
    private func showFailure(_ webView: WKWebView, error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        tabs.first(where: { $0.webView === webView })?.error = "Could not load page"
        syncNavigation(); renderTabs()
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        tabs.first(where: { $0.webView === webView })?.error = "Reload with ⌘R"
        syncNavigation(); renderTabs()
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        addTab(configuration: configuration, home: false)
        return currentTab?.webView
    }
    func webViewDidClose(_ webView: WKWebView) {
        if let tab = tabs.first(where: { $0.webView === webView }) { closeTab(tab) }
    }

    // Keyboard/menu actions stay available without extra on-screen controls.
    @objc private func newTab(_ sender: Any?) { addTab(); focusAddress(nil) }
    @objc private func closeCurrentTab(_ sender: Any?) { if let tab = currentTab { closeTab(tab) } }
    @objc private func focusAddress(_ sender: Any?) { window.makeFirstResponder(address); address.selectText(nil) }
    @objc private func goBack(_ sender: Any?) { currentTab?.webView.goBack() }
    @objc private func goForward(_ sender: Any?) { currentTab?.webView.goForward() }
    @objc private func reload(_ sender: Any?) { currentTab?.error = nil; currentTab?.webView.reload() }
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
