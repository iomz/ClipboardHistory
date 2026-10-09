import AppKit

@main
struct AboutChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardHistory-about-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Different bundles prove metadata isn't hard-coded or fetched from a
        // different installed copy. Neither fixture is a release artifact.
        for (index, version, build) in [(1, "9.8.7", "987"), (2, "1.2.3", "456")] {
            let app = root.appendingPathComponent("Fixture\(index).app")
            let contents = app.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let values = ["CFBundleName": "Fixture \(index)", "CFBundleIdentifier": "test.about.\(index)",
                          "CFBundleShortVersionString": version, "CFBundleVersion": build]
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            let bundle = Bundle(url: app)!
            let information = AboutInformation(bundle: bundle)
            precondition(information.panelOptions[.applicationName] as? String == "Fixture \(index)")
            precondition(information.panelOptions[.applicationVersion] as? String == version)
            precondition(information.panelOptions[.version] as? String == build)
        }
        print("About checks passed: application name, version and build follow supplied bundle metadata.")
    }
}
