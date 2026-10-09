import AppKit

enum ApplicationIcon: String, CaseIterable {
    case dustlight
    case lagoon

    var title: String { self == .dustlight ? "Dustlight" : "Lagoon" }
    var resourceName: String { self == .dustlight ? "Dustlight" : "Lagoon" }
}

/// Only changes the running app's image. Never writes bundle/Finder metadata.
final class ApplicationIconController: NSObject, NSMenuItemValidation {
    static let preferenceKey = "ApplicationIconSelection"
    private let defaults: UserDefaults
    private let images: [ApplicationIcon: NSImage]
    private let applyImage: (NSImage) -> Void
    private let schedule: (@escaping () -> Void) -> Void
    private var reapplicationPending = false
    private(set) var selected: ApplicationIcon = .dustlight
    let menu = NSMenu(title: "Application Icon")

    var selectedImage: NSImage? { images[selected] }

    static func loadImage(_ choice: ApplicationIcon, bundle: Bundle) -> NSImage? {
        guard let url = bundle.url(forResource: choice.resourceName, withExtension: "icns"),
              let image = NSImage(contentsOf: url), image.isValid,
              !image.representations.isEmpty else { return nil }
        return image
    }

    init(defaults: UserDefaults = .standard, bundle: Bundle = .main,
         loadImage: ((ApplicationIcon) -> NSImage?)? = nil,
         applyImage: @escaping (NSImage) -> Void = { NSApp.applicationIconImage = $0 },
         schedule: @escaping (@escaping () -> Void) -> Void = { DispatchQueue.main.async(execute: $0) }) {
        self.defaults = defaults
        self.applyImage = applyImage
        self.schedule = schedule
        let loader = loadImage ?? { Self.loadImage($0, bundle: bundle) }
        var loaded: [ApplicationIcon: NSImage] = [:]
        for choice in ApplicationIcon.allCases {
            if let image = loader(choice), image.isValid, !image.representations.isEmpty { loaded[choice] = image }
        }
        self.images = loaded
        super.init()
        menu.autoenablesItems = false
        for choice in ApplicationIcon.allCases {
            let item = NSMenuItem(title: choice.title, action: #selector(selectFromMenu(_:)), keyEquivalent: "")
            item.representedObject = choice.rawValue
            item.target = self
            menu.addItem(item)
        }
        if let stored = defaults.string(forKey: Self.preferenceKey),
           let choice = ApplicationIcon(rawValue: stored), images[choice] != nil {
            selected = choice
        }
        // Missing/corrupt alternative falls back to Dustlight without erasing
        // saved preference. No startup preference writes or new permissions.
        applySelectedIcon()
        refreshMenu()
    }

    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Application Icon", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @discardableResult
    func select(_ choice: ApplicationIcon) -> Bool {
        guard images[choice] != nil else { return false }
        selected = choice
        applySelectedIcon()
        defaults.set(choice.rawValue, forKey: Self.preferenceKey)
        refreshMenu()
        return true
    }

    // Startup and activation-policy changes can publish the bundle's Dock icon
    // after an early setter. Reassert after the current lifecycle callback, not
    // after an arbitrary timer. Read current selection at execution time so a
    // queued startup request cannot undo a user's intervening menu selection.
    func scheduleReapplication() {
        guard !reapplicationPending else { return }
        reapplicationPending = true
        schedule { [weak self] in
            guard let self else { return }
            self.reapplicationPending = false
            self.applySelectedIcon()
        }
    }

    private func applySelectedIcon() {
        if let image = selectedImage { applyImage(image) }
    }

    @objc private func selectFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let choice = ApplicationIcon(rawValue: raw) else { return }
        select(choice)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let raw = item.representedObject as? String,
              let choice = ApplicationIcon(rawValue: raw) else { return false }
        item.state = selected == choice ? .on : .off
        return images[choice] != nil
    }

    private func refreshMenu() {
        for item in menu.items { item.isEnabled = validateMenuItem(item) }
    }
}
