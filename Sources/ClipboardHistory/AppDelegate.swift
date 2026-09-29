import AppKit
import ClipboardCore
import ClipboardPlatform
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var store: FileEntryStore!
    private var history: ClipboardHistory!
    private var capture: PasteboardCapture!
    private var picker: PickerWindowController!
    private var historyManager: HistoryManagerWindowController!
    private var hotkey: GlobalHotkey!
    private var feedbackTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let support: URL
            if let testDirectory = ProcessInfo.processInfo.environment["CLIPHISTORY_SUPPORT_DIRECTORY"] {
                support = URL(fileURLWithPath: testDirectory, isDirectory: true)
            } else {
                support = try FileManager.default.url(
                    for: .applicationSupportDirectory, in: .userDomainMask,
                    appropriateFor: nil, create: true
                ).appendingPathComponent("ClipboardHistory", isDirectory: true)
            }
            store = try FileEntryStore(root: support.appendingPathComponent("Entries", isDirectory: true))
            history = ClipboardHistory(store: store)
            capture = PasteboardCapture(history: history)
            capture.start()
            configureStatusItem()
            picker = PickerWindowController(history: history, capture: capture) { [weak self] message in
                self?.showFeedback(message)
            }
            historyManager = HistoryManagerWindowController(history: history, capture: capture) { [weak self] message in
                self?.showFeedback(message)
            } onWindowVisibilityChanged: { [weak self] managerIsOpen in
                self?.setManagerActivationPolicy(managerIsOpen)
            }
            hotkey = GlobalHotkey { [weak self] in self?.picker.show() }
            let status = hotkey.register()
            if status != noErr {
                statusItem.button?.toolTip = "Clipboard History · Use menu to open (shortcut unavailable)"
            }
        } catch {
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture?.stop()
        hotkey?.unregister()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Clipboard History")
        statusItem.button?.toolTip = "Clipboard History · ⌥⌘V"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open Fast Picker…", action: #selector(openPicker), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Open History Manager…", action: #selector(openHistoryManager), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clipboard Representation Report…", action: #selector(showClipboardReport), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Clipboard History", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    @objc private func openPicker() { picker.show() }
    @objc private func openHistoryManager() { historyManager.showManager() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func showClipboardReport() {
        let report = PasteboardSnapshotter.capture(from: .general)?.metadataReport
            ?? "No supported clipboard representations are currently available."
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Clipboard Representation Metadata"
        alert.informativeText = "Types and byte counts only. Clipboard payload contents are not displayed or logged."
        alert.addButton(withTitle: "Close")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 540, height: 280))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let reportView = NSTextView(frame: scroll.bounds)
        reportView.isEditable = false
        reportView.isSelectable = true
        reportView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        reportView.string = report
        scroll.documentView = reportView
        alert.accessoryView = scroll
        alert.runModal()
    }

    private func setManagerActivationPolicy(_ managerIsOpen: Bool) {
        let policy: NSApplication.ActivationPolicy = managerIsOpen ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        _ = NSApp.setActivationPolicy(policy)
    }

    private func showFeedback(_ message: String) {
        statusItem.button?.title = "✓"
        statusItem.button?.toolTip = message
        feedbackTimer?.invalidate()
        feedbackTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            self?.statusItem.button?.title = ""
            self?.statusItem.button?.toolTip = "Clipboard History · ⌥⌘V"
        }
    }
}
