// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipboardHistory",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "ClipboardCore", targets: ["ClipboardCore"]),
        .executable(name: "ClipboardHistory", targets: ["ClipboardHistory"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "ClipboardCore"),
        .target(name: "ClipboardPlatform", dependencies: ["ClipboardCore"]),
        .executableTarget(
            name: "ClipboardHistory",
            dependencies: ["ClipboardCore", "ClipboardPlatform", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ],
    swiftLanguageModes: [.v5]
)
