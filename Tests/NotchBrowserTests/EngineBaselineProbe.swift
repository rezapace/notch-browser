import AppKit
import WebKit

/// Interactive developer probe, not shipped in NotchBrowser.app.
/// Does not inject scripts, drive Speedometer, or collect page content/URLs.
@MainActor
private final class ProbeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    var browser: BrowserController?
    var webView: WKWebView?
    var server: LocalHTTPServer?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct EngineBaselineProbe {
    @MainActor
    static func wait(until deadline: Date, condition: () -> Bool) {
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    @MainActor
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let mode = args.first ?? "plain"
        guard ["plain", "notch"].contains(mode), args.count <= 2 else {
            fputs("Usage: engine-baseline.sh [plain|notch] [http(s)-URL|--smoke-test]\n", stderr)
            exit(2)
        }
        let smoke = args.last == "--smoke-test"
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.setActivationPolicy(smoke ? .accessory : .regular)
        app.appearance = NSAppearance(named: .darkAqua)
        app.finishLaunching()
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            fatalError("Requires a graphical macOS session")
        }
        let rail = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness) + 2
        let frame = WorkspaceGeometry.expandedFrame(in: screen.frame, visibleFrame: screen.visibleFrame, topInset: rail)
        let viewport = WorkspaceGeometry.browserFrame(in: frame.size, topInset: rail).size
        let target: URL
        if smoke {
            delegate.server = try! LocalHTTPServer()
            wait(until: Date().addingTimeInterval(3)) { delegate.server?.port != nil }
            guard let port = delegate.server?.port else { fatalError("Loopback fixture did not start") }
            target = URL(string: "http://127.0.0.1:\(port)/fixture")!
        } else {
            guard let url = URL(string: args.count == 2 ? args[1] : "https://browserbench.org/Speedometer3.1/"),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                fputs("Expected an HTTP(S) benchmark URL.\n", stderr)
                exit(2)
            }
            target = url
        }

        if mode == "notch" {
            let window = WorkspaceWindow()
            delegate.window = window
            window.reposition(on: screen)
            let browser = BrowserController(window: window)
            delegate.browser = browser
            window.present(on: screen, activate: !smoke)
            browser.prepareForPresentation()
            browser.navigate(to: target)
            let root = window.contentView!.subviews.first { $0.accessibilityIdentifier() == "browser.root" }!
            let pages = root.subviews.first { $0.accessibilityIdentifier() == "browser.pages" }!
            delegate.webView = pages.subviews.compactMap { $0 as? WKWebView }.first!
        } else {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: viewport),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = true
            window.backgroundColor = .black
            window.title = "WKWebView baseline"
            let web = WKWebView(frame: NSRect(origin: .zero, size: viewport), configuration: WebKitRuntime.configuration())
            web.appearance = NSAppearance(named: .darkAqua)
            web.underPageBackgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1)
            window.contentView = web
            window.center()
            delegate.window = window
            delegate.webView = web
            let menu = NSMenu()
            let item = NSMenuItem()
            item.submenu = NSMenu()
            item.submenu!.addItem(withTitle: "Quit Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.addItem(item)
            app.mainMenu = menu
            if smoke { window.orderFront(nil) }
            else {
                app.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(web)
            }
            web.load(URLRequest(url: target))
        }

        let web = delegate.webView!
        print("Mode: \(mode); viewport: \(Int(viewport.width)) x \(Int(viewport.height)) pt")
        if smoke {
            wait(until: Date().addingTimeInterval(8)) { !web.isLoading && web.title == "Timing fixture" }
            precondition(!web.isLoading && web.title == "Timing fixture" && web.url == target)
            precondition(web.bounds.size == viewport && web.configuration.websiteDataStore.isPersistent)
            precondition(!web.isHidden && web.window === delegate.window)
            delegate.window?.orderOut(nil)
            print("PASS: \(mode) probe loads only loopback HTTP with matching viewport and persistent-store policy")
        } else {
            print("Run the benchmark manually after loading/animation. Use the same URL, power, zoom and cache conditions in both modes.")
            print("No scores or WebKit subprocess measurements are collected automatically. Quit with Command-Q.")
            app.run()
        }
        withExtendedLifetime(delegate) {}
    }
}
