import AppKit

struct AboutInformation {
    let applicationName: String
    let version: String
    let build: String

    init(bundle: Bundle = .main) {
        applicationName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    var panelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        [.applicationName: applicationName, .applicationVersion: version, .version: build]
    }
}
