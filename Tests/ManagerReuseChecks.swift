import AppKit
import ClipboardCore
@testable import ClipboardPlatform

private final class FailingStore: ClipboardEntryStore {
    var entries: [ClipboardEntry] = []
    var fails = false
    func loadAll() -> [ClipboardEntry] { entries }
    func upsert(_ entry: ClipboardEntry) throws {
        if fails { throw NSError(domain: "Test", code: 1) }
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
    }
    func remove(id: UUID) throws { entries.removeAll { $0.id == id } }
}

@main enum ManagerReuseChecks {
    static func main() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TheClipboard-reuse-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ClipboardLibrary(store: try FileEntryStore(root: root))
        let board = NSPasteboard(name: .init("com.iomz.TheClipboard.Test.Reuse.\(UUID().uuidString)"))
        defer { board.clearContents() }
        let capture = PasteboardCapture(history: history, pasteboard: board)
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1800, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let payloads: [(String, Data)] = [
            ("public.utf8-plain-text", Data(String(repeating: "needle TXT ", count: 100).utf8)),
            ("public.rtf", Data("{\\rtf1 needle RTF}".utf8)),
            ("public.html", Data("<p>needle HTML</p>".utf8)),
            ("public.png", image.representation(using: .png, properties: [:])!)
        ]
        var fixtures: [ClipboardEntry] = []
        for (index, payload) in payloads.enumerated() {
            let entry = ClipboardEntry(capturedAt: Date(timeIntervalSince1970: Double(100 + index)), sourceApplication: .init(displayName: index == 2 ? String(repeating: "Long source ", count: 100) : "Fixture"), isFavorite: index % 2 == 0, pasteboardItems: [.init(ordinal: 0, representations: [.init(typeIdentifier: payload.0, data: payload.1)])], plainText: index == 3 ? nil : "needle \(index)")
            try history.capture(entry, at: entry.lastCapturedAt)
            fixtures.append(entry)
        }
        var feedback: [String] = []
        let manager = HistoryManagerWindowController(history: history, capture: capture, onFeedback: { feedback.append($0) }, onWindowVisibilityChanged: { _ in })
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let content = manager.window!.contentView!
        let views = descendants(content)
        let split = views.compactMap { $0 as? NSSplitView }.first!
        let table = views.compactMap { $0 as? NSTableView }.first!
        let search = views.compactMap { $0 as? NSSearchField }.first!
        let scope = views.compactMap { $0 as? NSSegmentedControl }.first!
        let buttons = views.compactMap { $0 as? NSButton }
        let rich = buttons.first { $0.title == "Copy" }!
        let plain = buttons.first { $0.title == "Copy as Plain Text" }!
        let favorite = buttons.first { $0.title == "Favorite" || $0.title == "Unfavorite" }!
        func filtered() -> [ClipboardEntry] {
            let result = history.search(search.stringValue)
            return scope.selectedSegment == 1 ? result.filter(\.isFavorite) : result
        }
        func select(_ id: UUID) {
            table.selectRowIndexes(IndexSet(integer: filtered().firstIndex { $0.id == id }!), byExtendingSelection: false)
            content.layoutSubtreeIfNeeded()
        }
        func selectedID() -> UUID { filtered()[table.selectedRow].id }

        let initialOrder = history.allEntries()
        precondition(manager.window!.styleMask.contains(.resizable))
        precondition(split.delegate == nil, "Original split behavior must not acquire a controller/delegate")
        precondition(manager.window!.contentAspectRatio == .zero)
        precondition(manager.window!.contentMaxSize.width > 10000)
        // Check actual window/content geometry, not just pane-relative positions.
        // The rejected controller could pass divider tests while its root content
        // stayed ~804 points wide after a 1300-point window resize.
        for size in [NSSize(width: 1200, height: 700), NSSize(width: 1200, height: 850), NSSize(width: 1400, height: 900), manager.window!.contentMinSize] {
            manager.window!.setContentSize(size)
            content.layoutSubtreeIfNeeded()
            precondition(abs(content.frame.width - size.width) < 0.01, "Horizontal content did not follow window: requested \(size), actual \(content.frame), window \(manager.window!.frame)")
            precondition(abs(content.frame.height - size.height) < 0.01, "Vertical content did not follow window")
        }
        // Exercise every type/favorite combination at default, narrow, wide and
        // user-dragged divider positions. No visible windows or live clipboard.
        for width in [1040.0, 900.0, manager.window!.contentMinSize.width, 1400.0] {
            manager.window!.setContentSize(NSSize(width: width, height: 700))
            content.layoutSubtreeIfNeeded()
            for dragged in [false, true] {
                if dragged { split.setPosition(split.bounds.width * 0.5, ofDividerAt: 0) }
                content.layoutSubtreeIfNeeded()
                let divider = split.subviews[0].frame.maxX
                for entry in fixtures {
                    select(entry.id)
                    for _ in 0..<2 {
                        favorite.performClick(nil)
                        content.layoutSubtreeIfNeeded()
                        precondition(abs(split.subviews[0].frame.maxX - divider) < 0.01, "Divider moved: window \(width), dragged \(dragged), type \(entry.compactTypeLabel), baseline \(divider), actual \(split.subviews[0].frame.maxX)")
                        precondition(split.subviews[1].frame.maxX <= split.bounds.maxX + 0.01, "Detail overflow at minimum width")
                    }
                }
            }
        }
        precondition(history.allEntries() == initialOrder, "Selection/preview/favorite changed ordering")
        manager.window!.setContentSize(NSSize(width: 1040, height: 700))
        select(fixtures[0].id)
        let displayedCell = table.view(atColumn: 0, row: table.selectedRow, makeIfNecessary: true) as! HistoryManagerRowCell
        content.layoutSubtreeIfNeeded()
        let clip = table.enclosingScrollView!.contentView
        let displayedStar = displayedCell.favoriteIndicator.convert(displayedCell.favoriteIndicator.bounds, to: clip)
        precondition(clip.bounds.contains(displayedStar), "Favorite star clipped at original default window width")
        // Row geometry remains equal with visible/hidden favorite indicator.
        let row = manager.tableView(table, viewFor: table.tableColumns[0], row: 0) as! HistoryManagerRowCell
        row.frame = NSRect(x: 0, y: 0, width: 400, height: 66)
        content.addSubview(row)
        row.configureFavorite(true)
        row.layoutSubtreeIfNeeded()
        let favoriteFrame = row.favoriteIndicator.frame
        let title = row.subviews.compactMap { $0 as? NSTextField }.first!
        let titleFrame = title.frame
        row.configureFavorite(false)
        row.layoutSubtreeIfNeeded()
        precondition(row.favoriteIndicator.frame == favoriteFrame && title.frame == titleFrame)
        let favoriteAlignment = row.favoriteIndicator.alignmentRect(forFrame: favoriteFrame)
        precondition(favoriteAlignment.width == 14 && row.bounds.maxX - favoriteAlignment.maxX == 10, "Star slot geometry: \(favoriteAlignment), row \(row.bounds)")
        precondition(title.lineBreakMode == .byTruncatingTail)
        row.removeFromSuperview()

        // Test real Manager actions against the isolated monitored pasteboard.
        for action in [rich, plain, rich] {
            let target = fixtures[0]
            select(target.id)
            action.performClick(nil)
            let reused = history.allEntries()[0]
            precondition(reused.id == target.id && selectedID() == target.id)
            precondition(reused.firstCapturedAt == target.firstCapturedAt && reused.lastCapturedAt == target.lastCapturedAt)
            precondition(reused.pasteboardItems == target.pasteboardItems && reused.isFavorite == target.isFavorite && reused.lastUsedAt != nil)
            precondition(history.allEntries().count == fixtures.count)
            let beforePoll = history.allEntries()
            capture.poll()
            precondition(history.allEntries() == beforePoll, "Own write recaptured")
        }
        select(fixtures[3].id)
        // Plain copy of an image must fail, not fall back to rich copying.
        _ = manager.perform(NSSelectorFromString("copyPlain"))
        precondition(history.allEntries()[0].id == fixtures[0].id && history.allEntries().first { $0.id == fixtures[3].id }!.lastUsedAt == nil)

        search.stringValue = "needle"
        manager.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification))
        scope.selectedSegment = 1
        _ = manager.perform(NSSelectorFromString("scopeChanged"))
        select(fixtures[2].id)
        rich.performClick(nil)
        precondition(search.stringValue == "needle" && scope.selectedSegment == 1 && selectedID() == fixtures[2].id && table.selectedRow == 0)
        precondition(manager.numberOfRows(in: table) == 2)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        precondition(selectedID() == fixtures[0].id, "Navigation skipped remaining filtered row")
        plain.performClick(nil)
        precondition(selectedID() == fixtures[0].id && table.selectedRow == 0)
        select(fixtures[2].id)
        plain.performClick(nil)
        precondition(selectedID() == fixtures[2].id && table.selectedRow == 0)
        precondition(board.string(forType: .string) == fixtures[2].plainText)
        precondition(board.data(forType: .html) == nil, "Plain copy restored rich representation")
        precondition(history.allEntries()[0].pasteboardItems == fixtures[2].pasteboardItems, "Plain copy destroyed stored HTML")

        var pickerFeedback: [String] = []
        let picker = PickerWindowController(history: history, capture: capture, onFeedback: { pickerFeedback.append($0) })
        let pickerViews = descendants(picker.panel.contentView!)
        let pickerTable = pickerViews.compactMap { $0 as? NSTableView }.first!
        let pickerSearch = pickerViews.compactMap { $0 as? NSSearchField }.first!
        pickerSearch.stringValue = "needle"
        func selectPicker(_ entry: ClipboardEntry) {
            picker.reloadRows(query: pickerSearch.stringValue)
            let index = history.search(pickerSearch.stringValue).firstIndex { $0.id == entry.id }!
            pickerTable.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        let destination = NSRunningApplication.current
        picker.ensurePasteAccess = { true }
        picker.frontmostPID = { destination.processIdentifier }
        picker.activateDestination = { _ in preconditionFailure("Must not activate real apps") }
        var posted = 0
        picker.postPaste = { pid in precondition(pid == destination.processIdentifier); posted += 1; return true }
        selectPicker(fixtures[1])
        picker.destinationApplication = destination
        picker.activate(plainTextOnly: false)
        precondition(posted == 1 && history.allEntries()[0].id == fixtures[1].id)
        picker.reloadRows(query: pickerSearch.stringValue, preservingSelection: true)
        precondition(pickerTable.selectedRow == 0 && pickerSearch.stringValue == "needle")
        precondition(history.search("needle")[pickerTable.selectedRow].id == fixtures[1].id)
        let usedOnce = history.allEntries()[0].lastUsedAt!
        picker.destinationApplication = destination
        picker.activate(plainTextOnly: true)
        precondition(posted == 2 && history.allEntries()[0].lastUsedAt! > usedOnce)
        precondition(history.allEntries().count == fixtures.count)

        // Restore failure, missing destination, access denial, rejected
        // activation, focus timeout, and failed event dispatch never promote.
        let beforeFailures = history.allEntries()
        pickerSearch.stringValue = ""
        selectPicker(fixtures[3])
        picker.activate(plainTextOnly: true)
        selectPicker(fixtures[2])
        picker.destinationApplication = nil
        picker.activate(plainTextOnly: false)
        picker.destinationApplication = destination
        picker.ensurePasteAccess = { false }
        picker.activate(plainTextOnly: false)
        picker.ensurePasteAccess = { true }
        picker.destinationApplication = destination
        picker.frontmostPID = { nil }
        picker.activateDestination = { _ in false }
        picker.activate(plainTextOnly: false)
        picker.waitForDestinationAndPost(destination, entryID: fixtures[2].id, attemptsRemaining: 0)
        picker.frontmostPID = { destination.processIdentifier }
        picker.postPaste = { _ in false }
        picker.destinationApplication = destination
        picker.activate(plainTextOnly: false)
        precondition(history.allEntries() == beforeFailures && pickerFeedback.count == 6)
        capture.poll()
        precondition(history.allEntries() == beforeFailures, "Failed paste's own clipboard write recaptured")

        let reloaded = ClipboardLibrary(store: try FileEntryStore(root: root)).allEntries()
        precondition(reloaded == history.allEntries(), "Relaunch lost persisted reuse ordering/metadata")
        // Monitor sees a genuine external copy of an existing entry: stable ID,
        // no duplicate, original capture retained, reuse metadata survives.
        let retainedUseDate = history.allEntries().first { $0.id == fixtures[0].id }!.lastUsedAt
        precondition(PasteboardRestorer.restore(fixtures[0], plainTextOnly: false, to: board))
        capture.poll()
        let deduplicated = history.allEntries()[0]
        precondition(history.allEntries().count == fixtures.count && deduplicated.id == fixtures[0].id)
        precondition(deduplicated.firstCapturedAt == fixtures[0].firstCapturedAt && deduplicated.lastUsedAt == retainedUseDate)

        let failingStore = FailingStore()
        let failureHistory = ClipboardLibrary(store: failingStore)
        try failureHistory.capture(fixtures[0])
        try failureHistory.capture(fixtures[1])
        let beforeStorageFailure = failureHistory.allEntries()
        failingStore.fails = true
        do { try failureHistory.recordReuse(of: fixtures[0].id); preconditionFailure("Expected storage failure") }
        catch { precondition(failureHistory.allEntries() == beforeStorageFailure) }
        var failedCopyFeedback: [String] = []
        let failedCopyManager = HistoryManagerWindowController(history: failureHistory, capture: PasteboardCapture(history: failureHistory, pasteboard: board), onFeedback: { failedCopyFeedback.append($0) }, onWindowVisibilityChanged: { _ in })
        let failureViews = descendants(failedCopyManager.window!.contentView!)
        let failureTable = failureViews.compactMap { $0 as? NSTableView }.first!
        failureTable.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        failureViews.compactMap { $0 as? NSButton }.first { $0.title == "Copy" }!.performClick(nil)
        precondition(failureHistory.allEntries() == beforeStorageFailure && failureTable.selectedRow == 1)
        precondition(failedCopyFeedback == ["Copied to clipboard, but could not save history order"])
        failingStore.fails = false
        try failureHistory.recordReuse(of: fixtures[0].id, at: Date(timeIntervalSince1970: 1))
        let monotonic = failureHistory.allEntries()[0].lastUsedAt!
        try failureHistory.recordReuse(of: fixtures[1].id, at: Date(timeIntervalSince1970: 1))
        precondition(failureHistory.allEntries()[0].id == fixtures[1].id && failureHistory.allEntries()[0].lastUsedAt! > monotonic)
        precondition(ClipboardLibrary(store: failingStore).allEntries() == failureHistory.allEntries())
        // Missing optional metadata remains readable without migration.
        let legacyURL = root.appendingPathComponent(fixtures[0].id.uuidString).appendingPathComponent("metadata.plist")
        var legacy = try PropertyListSerialization.propertyList(from: Data(contentsOf: legacyURL), format: nil) as! [String: Any]
        legacy.removeValue(forKey: "lastUsedAt")
        try PropertyListSerialization.data(fromPropertyList: legacy, format: .binary, options: 0).write(to: legacyURL)
        let legacyStore = try FileEntryStore(root: root)
        precondition(legacyStore.loadAll().first { $0.id == fixtures[0].id }!.lastUsedAt == nil)
        precondition(!manager.window!.isVisible && !picker.panel.isVisible)
        print("Manager/reuse checks passed: stable divider across TXT/RTF/HTML/image, favorites/resizes/drag; equal star spacing; Manager copy/plain and Picker dispatch promotion; repeated reuse, IDs/capture/payload preservation, filters/selection/navigation, relaunch, monitor dedup, six paste failures and storage rollback.")
    }
}
