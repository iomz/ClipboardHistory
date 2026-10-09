import AppKit

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
if CommandLine.arguments.contains("--distribution-check") {
    guard delegate.checkDistributionConfiguration() else {
        fatalError("Sparkle/menu distribution configuration check failed")
    }
    print("Sparkle started; both update menus target standard updater; automatic checks/downloads disabled.")
    exit(0)
}
application.run()
