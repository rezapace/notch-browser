import WebKit

/// Keep the existing persistent profile (cookies, HTTP cache and site storage).
/// WebKit controls cache capacity, GPU acceleration and process allocation.
/// Explicit WKProcessPool selection has no effect on our supported macOS 13+.
enum WebKitRuntime {
    static let dataStore = WKWebsiteDataStore.default()

    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Block unsolicited popups; keep incremental rendering at its default.
        return configuration
    }
}
