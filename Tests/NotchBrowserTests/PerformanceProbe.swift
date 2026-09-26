import AppKit
import WebKit
import Darwin

@main
struct PerformanceProbe {
    static func cpuSeconds() -> Double {
        var value = timespec()
        clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &value)
        return Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000
    }
    static func footprintMiB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
    @MainActor static func wait(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
    @MainActor static func sample(_ label: String, seconds: Double = 4) {
        let cpu = cpuSeconds(), start = ProcessInfo.processInfo.systemUptime
        wait(seconds)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        print(String(format: "%@: main-process CPU %.3f%%, footprint %.2f MiB (%.2fs)", label,
                     (cpuSeconds() - cpu) / elapsed * 100, footprintMiB(), elapsed))
        fflush(stdout)
    }
    @MainActor static func renderBenchmark(_ browser: BrowserController, tabs: Int) {
        var values: [Double] = []
        for _ in 0..<80 {
            let start = ProcessInfo.processInfo.systemUptime
            autoreleasepool { browser.prepareForPresentation() }
            values.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        values.sort()
        print(String(format: "%d tabs: prepareForPresentation median %.3f ms, p95 %.3f ms (80 iterations)",
                     tabs, values[values.count / 2], values[Int(Double(values.count) * 0.95)]))
        fflush(stdout)
    }
    @MainActor static func main() {
        setbuf(stdout, nil)
        print("Synthetic blank-page probe: CPU/footprint exclude WebKit subprocesses. Not Speedometer or FPS.")
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        guard let screen = NSScreen.main else { fatalError("Requires GUI session") }
        let panel = WorkspaceWindow()
        panel.reposition(on: screen)
        let start = ProcessInfo.processInfo.systemUptime
        let browser = BrowserController(window: panel)
        print(String(format: "BrowserController init %.2f ms (not whole-app launch time)", (ProcessInfo.processInfo.systemUptime - start) * 1000))
        panel.showCompact(on: screen)
        wait(4)
        sample("1 blank tab / compact")
        panel.present(on: screen)
        browser.prepareForPresentation()
        wait(3)
        sample("1 blank tab / expanded")
        renderBenchmark(browser, tabs: 1)
        wait(1)
        let baseline = footprintMiB()
        for _ in 0..<20 {
            panel.dismiss {}
            wait(0.25)
            panel.present(on: screen)
            browser.prepareForPresentation()
            wait(0.30)
        }
        wait(2)
        print(String(format: "20 collapse/expand: footprint before %.2f MiB, after %.2f MiB", baseline, footprintMiB()))

        let file = NSApp.mainMenu!.item(withTitle: "File")!.submenu!
        func invoke(_ title: String) {
            let item = file.item(withTitle: title)!
            _ = NSApp.sendAction(item.action!, to: item.target, from: item)
        }
        for _ in 1..<5 { autoreleasepool { invoke("New Tab") }; wait(0.15) }
        wait(3)
        sample("5 blank tabs / expanded")
        renderBenchmark(browser, tabs: 5)
        for _ in 5..<10 { autoreleasepool { invoke("New Tab") }; wait(0.15) }
        wait(3)
        sample("10 blank tabs / expanded")
        renderBenchmark(browser, tabs: 10)
        let root = panel.contentView!.subviews.first { $0.accessibilityIdentifier() == "browser.root" }!
        let pages = root.subviews.first { $0.accessibilityIdentifier() == "browser.pages" }!
        let navigation = root.subviews.first { $0.accessibilityIdentifier() == "browser.navigation" }!
        let address = navigation.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }.first!
        print("WebViews attached to 10 untouched blank tabs: \(pages.subviews.compactMap { $0 as? WKWebView }.count)")
        print("Total WebViews including the reusable reserve: \(browser.allocatedWebViewCount)")
        let server = try! LocalHTTPServer()
        let serverDeadline = Date().addingTimeInterval(3)
        while server.port == nil && Date() < serverDeadline { wait(0.01) }
        guard let port = server.port else { fatalError("Loopback server did not start") }
        let url = "http://127.0.0.1:\(port)/fixture"
        func loadFixture(_ label: String) {
            autoreleasepool {
                let start = ProcessInfo.processInfo.systemUptime
                address.stringValue = url
                precondition(NSApp.sendAction(address.action!, to: address.target, from: address))
                let web = pages.subviews.compactMap { $0 as? WKWebView }.last!
                wait(0.001)
                let deadline = Date().addingTimeInterval(5)
                while Date() < deadline && (web.isLoading || web.url?.absoluteString != url) { wait(0.001) }
                guard !web.isLoading && web.url?.absoluteString == url else {
                    fatalError("Loopback fixture navigation did not finish at the requested URL")
                }
                print(String(format: "%@: %.2f ms (to WK isLoading=false, not first paint)", label,
                             (ProcessInfo.processInfo.systemUptime - start) * 1000))
            }
        }
        loadFixture("First loopback HTML load after idle")
        wait(1)
        loadFixture("Repeat loopback HTML load in same WebView")
        withExtendedLifetime(server) {}
        weak var closedView: WKWebView?
        autoreleasepool {
            closedView = pages.subviews.compactMap { $0 as? WKWebView }.last
            for _ in 1..<10 { invoke("Close Tab") }
        }
        wait(4)
        print("Closed tab WKWebView released: \(closedView == nil)")
        sample("After closing 9 tabs / expanded")
        panel.orderOut(nil)
        withExtendedLifetime(browser) {}
    }
}
