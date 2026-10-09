import AppKit
import Foundation

@main
enum ApplicationIconChecks {
    static func main() throws {
        _ = NSApplication.shared
        let previousImage = NSApp.applicationIconImage
        defer { NSApp.applicationIconImage = previousImage }
        let suite = "com.iomz.TheClipboard.Test.Icons.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = Bundle(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
        let protectedURLs = ["Info.plist", "Resources/Dustlight.icns", "Resources/Lagoon.icns", "Resources/Assets.car", "_CodeSignature/CodeResources"]
            .map { app.bundleURL.appendingPathComponent("Contents/\($0)") }
        let before = try protectedURLs.map { try Data(contentsOf: $0) }
        let dustlight = ApplicationIconController.loadImage(.dustlight, bundle: app)!
        let lagoon = ApplicationIconController.loadImage(.lagoon, bundle: app)!
        precondition(dustlight.tiffRepresentation != lagoon.tiffRepresentation)
        var applied: [NSImage] = []
        let controller = ApplicationIconController(defaults: defaults, bundle: app, applyImage: {
            applied.append($0)
            NSApp.applicationIconImage = $0
        })
        precondition(controller.selected == .dustlight)
        precondition(defaults.object(forKey: ApplicationIconController.preferenceKey) == nil)
        precondition(controller.menu.items.map(\.title) == ["Dustlight", "Lagoon"])
        precondition(controller.menu.items.map(\.state) == [.on, .off])
        precondition(controller.menu.items.allSatisfy { $0.isEnabled && $0.keyEquivalent.isEmpty })
        precondition(applied.count == 1)
        let nativeDustlight = NSApp.applicationIconImage.tiffRepresentation
        let item = controller.menu.items[1]
        precondition(NSApp.sendAction(item.action!, to: item.target, from: item))
        precondition(controller.selected == .lagoon && applied.count == 2)
        precondition(controller.menu.items.map(\.state) == [.off, .on])
        precondition(defaults.string(forKey: ApplicationIconController.preferenceKey) == "lagoon")
        precondition(NSApp.applicationIconImage.isValid)
        precondition(NSApp.applicationIconImage.tiffRepresentation != nativeDustlight)
        let restored = ApplicationIconController(defaults: defaults, bundle: app)
        precondition(restored.selected == .lagoon && restored.menu.items[1].state == .on)
        precondition(restored.select(.dustlight))
        precondition(restored.menu.items.map(\.state) == [.on, .off])
        precondition(defaults.string(forKey: ApplicationIconController.preferenceKey) == "dustlight")

        for saved in [nil, "dustlight", "lagoon"] as [String?] {
            defaults.removeObject(forKey: ApplicationIconController.preferenceKey)
            if let saved { defaults.set(saved, forKey: ApplicationIconController.preferenceKey) }
            var callbacks: [() -> Void] = []
            var displayed: NSImage?
            var applications = 0
            let lifecycle = ApplicationIconController(defaults: defaults, bundle: app,
                applyImage: { displayed = $0; applications += 1 },
                schedule: { callbacks.append($0) })
            let expected: ApplicationIcon = saved == "lagoon" ? .lagoon : .dustlight
            precondition(lifecycle.selected == expected && applications == 1)
            lifecycle.scheduleReapplication() // end of didFinishLaunching
            lifecycle.scheduleReapplication() // Manager activation-policy change
            lifecycle.scheduleReapplication() // didBecomeActive
            precondition(callbacks.count == 1, "Lifecycle requests must coalesce")
            displayed = nil // simulate late startup publisher overriding image
            callbacks.removeFirst()()
            precondition(displayed === lifecycle.selectedImage && applications == 2)
            precondition(lifecycle.selected == expected)
            precondition(defaults.string(forKey: ApplicationIconController.preferenceKey) == saved)
            lifecycle.scheduleReapplication()
            precondition(lifecycle.select(.lagoon)) // user changes while queued
            callbacks.removeFirst()()
            precondition(lifecycle.selected == .lagoon && displayed === lifecycle.selectedImage)
            precondition(defaults.string(forKey: ApplicationIconController.preferenceKey) == "lagoon")
        }

        defaults.set("unknown", forKey: ApplicationIconController.preferenceKey)
        let unknown = ApplicationIconController(defaults: defaults, bundle: app)
        precondition(unknown.selected == .dustlight)
        precondition(defaults.string(forKey: ApplicationIconController.preferenceKey) == "unknown")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TheClipboard-icon-fixture-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = root.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": suite, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: root.appendingPathComponent("Contents/Info.plist"))
        try FileManager.default.copyItem(at: app.url(forResource: "Dustlight", withExtension: "icns")!,
            to: resources.appendingPathComponent("Dustlight.icns"))
        let fixture = Bundle(url: root)!
        precondition(ApplicationIconController.loadImage(.lagoon, bundle: fixture) == nil)
        try Data("not an icon".utf8).write(to: resources.appendingPathComponent("Lagoon.icns"))
        let corruptURL = root.deletingLastPathComponent().appendingPathComponent("corrupt-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        try FileManager.default.copyItem(at: root, to: corruptURL)
        let corrupt = Bundle(url: corruptURL)!
        precondition(ApplicationIconController.loadImage(.lagoon, bundle: corrupt) == nil)
        defaults.set("lagoon", forKey: ApplicationIconController.preferenceKey)
        let missing = ApplicationIconController(defaults: defaults, bundle: fixture)
        precondition(missing.selected == .dustlight && missing.menu.items[0].state == .on)
        precondition(!missing.menu.items[1].isEnabled)
        precondition(!missing.select(.lagoon))
        precondition(missing.selected == .dustlight)
        precondition(defaults.string(forKey: ApplicationIconController.preferenceKey) == "lagoon")
        let corruptController = ApplicationIconController(defaults: defaults, bundle: corrupt)
        precondition(corruptController.selected == .dustlight && !corruptController.menu.items[1].isEnabled)
        let after = try protectedURLs.map { try Data(contentsOf: $0) }
        precondition(before == after, "Runtime selection modified signed bundle")
        print("Application icon checks passed: fresh/Dustlight/Lagoon startup restore, coalesced lifecycle reapplication, late overwrite recovery, latest-choice race guard, runtime switch, menu/persistence and missing/corrupt fallback.")
    }
}
