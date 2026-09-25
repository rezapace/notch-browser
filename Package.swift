// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NotchBrowser",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "NotchBrowser", targets: ["NotchBrowser"])],
    targets: [
        .executableTarget(
            name: "NotchBrowser",
            path: "Sources/NotchBrowser",
            resources: [.process("Resources/icon.svg")]
        )
    ]
)
