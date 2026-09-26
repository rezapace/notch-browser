import WebKit

/// Opt-in, local timing output only. Never emit URLs, titles, headers, or error text.
/// No polling, injected user scripts, or persistent logs. Disabled by default.
final class NavigationDiagnostics {
    private struct Trace {
        let navigation: WKNavigation
        let id: Int
        let start: TimeInterval
    }
    private struct ViewState {
        let id: Int
        var trace: Trace?
    }
    private var views: [ObjectIdentifier: ViewState] = [:]
    private var nextView = 0
    private var nextNavigation = 0
    private let output: (String) -> Void

    init(output: @escaping (String) -> Void = { line in
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }) { self.output = output }

    func created(_ webView: WKWebView, since start: TimeInterval) {
        nextView += 1
        views[ObjectIdentifier(webView)] = ViewState(id: nextView)
        emit(event: "webview_created", view: nextView,
             metrics: ["create_ms": (ProcessInfo.processInfo.systemUptime - start) * 1000])
    }

    func started(_ webView: WKWebView, navigation: WKNavigation?) {
        guard let navigation, var state = views[ObjectIdentifier(webView)] else { return }
        nextNavigation += 1
        state.trace = Trace(navigation: navigation, id: nextNavigation, start: ProcessInfo.processInfo.systemUptime)
        views[ObjectIdentifier(webView)] = state
        emit(event: "navigation_started", view: state.id, navigation: nextNavigation)
    }

    func committed(_ webView: WKWebView, navigation: WKNavigation?) {
        guard let state = matching(webView, navigation: navigation), let trace = state.trace else { return }
        emit(event: "navigation_committed", view: state.id, navigation: trace.id,
             metrics: ["start_to_commit_ms": elapsed(trace)])
    }

    func finished(_ webView: WKWebView, navigation: WKNavigation?) {
        guard let state = matching(webView, navigation: navigation), let trace = state.trace else { return }
        emit(event: "navigation_finished", view: state.id, navigation: trace.id,
             metrics: ["start_to_finish_ms": elapsed(trace)])
        // Isolated world; read only numeric Navigation Timing fields, once after load.
        webView.evaluateJavaScript(Self.timingScript, in: nil, in: .defaultClient) { [weak self, weak webView] result in
            guard let self, let webView,
                  self.matching(webView, navigation: trace.navigation)?.trace?.id == trace.id else { return }
            let metrics: [String: Double]
            if case .success(let value) = result { metrics = Self.sanitizedMetrics(value) }
            else { metrics = [:] }
            self.emit(event: metrics.isEmpty ? "navigation_timing_unavailable" : "navigation_timing",
                      view: state.id, navigation: trace.id, metrics: metrics)
            self.views[ObjectIdentifier(webView)]?.trace = nil
        }
    }

    func failed(_ webView: WKWebView, navigation: WKNavigation?, code: Int) {
        guard let state = matching(webView, navigation: navigation), let trace = state.trace else { return }
        emit(event: code == NSURLErrorCancelled ? "navigation_cancelled" : "navigation_failed",
             view: state.id, navigation: trace.id, metrics: ["elapsed_ms": elapsed(trace)], errorCode: code)
        views[ObjectIdentifier(webView)]?.trace = nil
    }

    func terminated(_ webView: WKWebView) {
        guard let state = views[ObjectIdentifier(webView)] else { return }
        emit(event: "web_process_terminated", view: state.id)
        views[ObjectIdentifier(webView)]?.trace = nil
    }

    func closed(_ webView: WKWebView) { views.removeValue(forKey: ObjectIdentifier(webView)) }

    private func matching(_ webView: WKWebView, navigation: WKNavigation?) -> ViewState? {
        guard let navigation, let state = views[ObjectIdentifier(webView)],
              state.trace?.navigation === navigation else { return nil }
        return state
    }

    private func elapsed(_ trace: Trace) -> Double {
        (ProcessInfo.processInfo.systemUptime - trace.start) * 1000
    }

    private func emit(event: String, view: Int, navigation: Int? = nil,
                      metrics: [String: Double] = [:], errorCode: Int? = nil) {
        var record: [String: Any] = ["event": event, "view": view]
        if let navigation { record["navigation"] = navigation }
        if let errorCode { record["error_code"] = errorCode }
        for (key, value) in metrics where value.isFinite && value >= 0 {
            record[key] = (value * 1000).rounded() / 1000
        }
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        output(line)
    }

    static func sanitizedMetrics(_ value: Any) -> [String: Double] {
        guard let values = value as? [String: Any] else { return [:] }
        var result: [String: Double] = [:]
        for key in ["dns_ms", "connect_ms", "tls_ms", "request_to_first_byte_ms", "download_ms",
                    "dom_content_loaded_ms", "load_ms"] {
            guard let number = values[key] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
            let value = number.doubleValue
            guard value.isFinite, value >= 0, value <= 86_400_000 else { continue }
            result[key] = value
        }
        return result
    }

    private static let timingScript = """
    (() => {
        const entry = performance.getEntriesByType('navigation')[0];
        // Some WKWebView versions expose only legacy Navigation Timing.
        const n = entry || performance.timing;
        if (!n) return null;
        const origin = entry ? n.startTime : n.navigationStart;
        const span = (a, b) => a >= 0 && b > 0 && b >= a ? b - a : null;
        return {
            dns_ms: span(n.domainLookupStart, n.domainLookupEnd),
            connect_ms: span(n.connectStart, n.connectEnd),
            tls_ms: n.secureConnectionStart > 0 ? span(n.secureConnectionStart, n.connectEnd) : null,
            request_to_first_byte_ms: span(n.requestStart, n.responseStart),
            download_ms: span(n.responseStart, n.responseEnd),
            dom_content_loaded_ms: span(origin, n.domContentLoadedEventEnd),
            load_ms: span(origin, n.loadEventEnd)
        };
    })()
    """
}
