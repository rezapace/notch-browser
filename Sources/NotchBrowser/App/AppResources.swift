import Foundation

/// Installed apps must never rely on SwiftPM's absolute development .build path.
enum AppResources {
    static var iconURL: URL? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resources = Bundle.main.resourceURL else { return nil }
            let url = resources.appendingPathComponent("NotchBrowser_NotchBrowser.bundle")
            return Bundle(url: url)?.url(forResource: "icon", withExtension: "svg")
        }
        // swift run / the bare executable use SwiftPM's resource layout.
        return Bundle.module.url(forResource: "icon", withExtension: "svg")
    }
}
