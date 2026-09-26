import Foundation

/// Installed apps must never rely on SwiftPM's absolute development .build path.
enum AppResources {
    static var iconURL: URL? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resources = Bundle.main.resourceURL else { return nil }
            let url = resources.appendingPathComponent("NotchBrowser_NotchBrowser.bundle")
            return Bundle(url: url)?.url(forResource: "icon", withExtension: "svg")
        }
        // Resolve beside the executable, never through Bundle.module: SwiftPM's
        // generated accessor embeds an absolute path from the build machine.
        guard let executable = Bundle.main.executableURL else { return nil }
        let url = executable.deletingLastPathComponent()
            .appendingPathComponent("NotchBrowser_NotchBrowser.bundle")
        return Bundle(url: url)?.url(forResource: "icon", withExtension: "svg")
    }
}
