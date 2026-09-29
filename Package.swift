// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipboardHistory",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ClipboardCore", targets: ["ClipboardCore"]),
        .executable(name: "ClipboardHistory", targets: ["ClipboardHistory"]),
    ],
    targets: [
        .target(name: "ClipboardCore"),
        .target(name: "ClipboardPlatform", dependencies: ["ClipboardCore"]),
        .executableTarget(name: "ClipboardHistory", dependencies: ["ClipboardCore", "ClipboardPlatform"]),
    ],
    swiftLanguageModes: [.v5]
)
