import AppKit
import Sparkle

// Fixture-specific bundle IDs isolate preferences. Updaters are never started:
// no network, consent windows, helper launches or production defaults writes.
let source = URL(fileURLWithPath: CommandLine.arguments[1])
_ = NSApplication.shared
let sourceData = try Data(contentsOf: source)
let sourceInfo = try PropertyListSerialization.propertyList(from: sourceData, format: nil) as! [String: Any]
precondition(sourceInfo["SUEnableAutomaticChecks"] == nil, "Keep native consent")
precondition(sourceInfo["SUScheduledCheckInterval"] as? Double == 86400)
let work = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardHistory-updater-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

for choice in [nil, false, true] as [Bool?] {
    let id = "com.iomz.ClipboardHistory.Test.Updater.\(UUID().uuidString)"
    defer { UserDefaults.standard.removePersistentDomain(forName: id) }
    var info = sourceInfo
    info["CFBundleIdentifier"] = id
    let app = work.appendingPathComponent("\(id).app")
    let contents = app.appendingPathComponent("Contents")
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
    var preferences: [String: Any] = ["SUAutomaticallyUpdate": true]
    if let choice { preferences["SUEnableAutomaticChecks"] = choice }
    UserDefaults.standard.setPersistentDomain(preferences, forName: id)
    let bundle = Bundle(url: app)!
    let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
    let updater = SPUUpdater(hostBundle: bundle, applicationBundle: .main, userDriver: driver, delegate: nil)
    precondition(updater.automaticallyChecksForUpdates == (choice ?? false))
    precondition(updater.updateCheckInterval == 86400)
    precondition(!updater.automaticallyDownloadsUpdates && !updater.allowsAutomaticUpdates)
    precondition(UserDefaults.standard.persistentDomain(forName: id)?["SUEnableAutomaticChecks"] as? Bool == choice)
    // An explicit user change through Sparkle persists and survives recreation.
    updater.automaticallyChecksForUpdates = true
    let second = SPUUpdater(hostBundle: bundle, applicationBundle: .main, userDriver: driver, delegate: nil)
    precondition(second.automaticallyChecksForUpdates)
    updater.automaticallyChecksForUpdates = false
    let third = SPUUpdater(hostBundle: bundle, applicationBundle: .main, userDriver: driver, delegate: nil)
    precondition(!third.automaticallyChecksForUpdates)
}
print("Sparkle checks passed: consent unset, stored NO/YES respected, 86400-second default, downloads prohibited, explicit opt-in/out persisted.")
