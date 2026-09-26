import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: NotchCoordinator?

    static func main() {
        if CommandLine.arguments.contains("--check-resources") {
            guard let icon = AppResources.iconURL,
                  let contents = try? String(contentsOf: icon, encoding: .utf8),
                  contents.contains("<svg") else {
                fputs("Missing icon.svg in application resources. Rebuild the app bundle.\n", stderr)
                exit(1)
            }
            print("Resource OK: \(icon.path)")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // NSApplication.delegate is weak; keep the owner alive for the whole event loop.
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let window = WorkspaceWindow()
        window.title = "NotchBrowser"
        if let screen = NSScreen.main {
            window.reposition(on: screen)
        }
        let diagnostics = CommandLine.arguments.contains("--diagnose-loading") ? NavigationDiagnostics() : nil
        let browser = BrowserController(window: window, diagnostics: diagnostics)
        let coordinator = NotchCoordinator(window: window, browser: browser)
        self.coordinator = coordinator
        coordinator.start()
        if CommandLine.arguments.contains("--show") { coordinator.show(activate: true) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.show(activate: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { coordinator?.stop() }
}
