import AppKit
import Carbon
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
    private var pickerHotkey: GlobalHotkey?
    private var plainTextPasteHotkey: GlobalHotkey?
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
            configureMainMenu()
            picker = PickerWindowController(history: history, capture: capture) { [weak self] message in
                self?.showFeedback(message)
            }
            historyManager = HistoryManagerWindowController(history: history, capture: capture) { [weak self] message in
                self?.showFeedback(message)
            } onWindowVisibilityChanged: { [weak self] managerIsOpen in
                self?.setManagerActivationPolicy(managerIsOpen)
            }
            pickerHotkey = GlobalHotkey(id: 1, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
                self?.picker.show()
            }
            plainTextPasteHotkey = GlobalHotkey(id: 2, keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
                self?.pasteCurrentClipboardAsPlainText()
            }
            let pickerStatus = pickerHotkey?.register() ?? OSStatus(paramErr)
            let plainTextStatus = plainTextPasteHotkey?.register() ?? OSStatus(paramErr)
            if pickerStatus != noErr || plainTextStatus != noErr {
                statusItem.button?.toolTip = "Clipboard History · Use menu to open (shortcut unavailable)"
            }

            // Explicit launches open the Manager. Background/login launchers can
            // pass --background to start capture without presenting a window.
            if !ProcessInfo.processInfo.arguments.contains("--background") {
                historyManager.showManager()
            }
        } catch {
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        historyManager.showManager()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture?.stop()
        pickerHotkey?.unregister()
        plainTextPasteHotkey?.unregister()
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

    private func configureMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: "Clipboard History")
        let about = NSMenuItem(title: "About Clipboard History", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        about.target = NSApp
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Clipboard History", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp
        appMenu.addItem(hideOthers)
        let showAll = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAll.target = NSApp
        appMenu.addItem(showAll)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Clipboard History", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenu = NSMenu(title: "File")
        let showHistory = NSMenuItem(title: "Show History", action: #selector(openHistoryManagerFromMainMenu), keyEquivalent: "0")
        showHistory.target = self
        fileMenu.addItem(showHistory)
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileMenuItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(.separator())
        let bringAll = NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        bringAll.target = NSApp
        windowMenu.addItem(bringAll)
        let windowMenuItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openHistoryManagerFromMainMenu() { historyManager.showManager() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    @objc private func openPicker() { picker.show() }
    @objc private func openHistoryManager() { historyManager.showManager() }
    @objc private func quit() { NSApp.terminate(nil) }

    private func pasteCurrentClipboardAsPlainText() {
        // Capture destination before reading or rewriting clipboard state.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let destination = frontmost?.processIdentifier == NSRunningApplication.current.processIdentifier
            ? picker.latestExternalApplication : frontmost
        guard let destination, !destination.isTerminated else { return }
        guard let text = PlainTextPastePolicy.text(from: PasteboardSnapshotter.capture(from: .general)) else { return }

        guard PasteboardRestorer.restorePlainText(text) else { return }
        capture.noteOwnWrite()
        guard PasteCommand.ensureEventPostingAccess() else {
            showFeedback("Plain text restored. Paste manually with ⌘V.")
            return
        }

        let destinationPID = destination.processIdentifier
        let alreadyFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == destinationPID
        guard alreadyFrontmost || destination.activate(options: []) else {
            showFeedback("Plain text restored. Destination did not activate; paste manually with ⌘V.")
            return
        }
        waitForDestinationAndPost(destination, attemptsRemaining: 60)
    }

    private func waitForDestinationAndPost(_ destination: NSRunningApplication, attemptsRemaining: Int) {
        let destinationPID = destination.processIdentifier
        guard !destination.isTerminated else {
            showFeedback("Plain text restored. Paste manually with ⌘V.")
            return
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != destinationPID else {
            if PasteCommand.post(to: destinationPID) { return }
            showFeedback("Plain text restored. Paste manually with ⌘V.")
            return
        }
        guard attemptsRemaining > 0 else {
            showFeedback("Plain text restored. Destination did not activate; paste manually with ⌘V.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            self?.waitForDestinationAndPost(destination, attemptsRemaining: attemptsRemaining - 1)
        }
    }

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
