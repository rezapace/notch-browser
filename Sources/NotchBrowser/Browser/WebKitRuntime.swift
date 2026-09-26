import WebKit

/// Keep the existing persistent profile (cookies, HTTP cache and site storage).
/// WebKit controls cache capacity, GPU acceleration and process allocation.
/// A shared pool is not a guarantee of one web process or shared JavaScript state.
enum WebKitRuntime {
    static let dataStore = WKWebsiteDataStore.default()
    static let processPool = WKProcessPool()

    static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.processPool = processPool
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        // Block unsolicited popups; keep incremental rendering at its default.
        return configuration
    }
}
