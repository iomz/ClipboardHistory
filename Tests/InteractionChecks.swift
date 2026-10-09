import AppKit
import ClipboardCore
@testable import ClipboardPlatform

@main
enum InteractionChecks {
    static func main() throws {
        _ = NSApplication.shared
        let match = PickerShortcut.opensHistoryManager
        precondition(match(49, [.command, .shift], true))
        precondition(match(49, [.command, .shift, .capsLock], true))
        precondition(!match(49, [.command, .shift], false))
        for modifiers: NSEvent.ModifierFlags in [[], [.command], [.shift], [.control], [.command, .shift, .option], [.command, .shift, .control]] {
            precondition(!match(49, modifiers, true))
        }
        for key: UInt16 in [36, 76, 53, 35, 45, 125, 126, 9] {
            precondition(!match(key, [.command, .shift], true))
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TheClipboard-interaction-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ClipboardLibrary(store: try FileEntryStore(root: root))
        let entry = ClipboardEntry(pasteboardItems: [.init(ordinal: 0, representations: [
            .init(typeIdentifier: "public.utf8-plain-text", data: Data("Disposable favorite fixture".utf8))
        ])])
        try history.capture(entry)
        let board = NSPasteboard(name: .init("com.iomz.TheClipboard.Test.Interaction.\(UUID().uuidString)"))
        defer { board.clearContents() }
        let capture = PasteboardCapture(history: history, pasteboard: board)
        var handoffs = 0
        let picker = PickerWindowController(history: history, capture: capture, onOpenHistoryManager: {
            handoffs += 1
        }, onFeedback: { _ in preconditionFailure("Shortcut must not paste") })
        let shortcutChangeCount = board.changeCount
        picker.openHistoryManagerFromPicker()
        precondition(handoffs == 1 && board.changeCount == shortcutChangeCount)
        precondition(history.allEntries().count == 1 && history.allEntries()[0].id == entry.id)
        let manager = HistoryManagerWindowController(history: history, capture: capture, onFeedback: { _ in
            preconditionFailure("Unexpected fixture feedback")
        }, onWindowVisibilityChanged: { _ in })

        func descendants(_ view: NSView) -> [NSView] {
            [view] + view.subviews.flatMap(descendants)
        }
        let views = descendants(manager.window!.contentView!)
        let button = views.compactMap { $0 as? NSButton }.first { $0.title == "Favorite" }!
        let table = views.compactMap { $0 as? NSTableView }.first!
        func currentRow() -> HistoryManagerRowCell {
            manager.tableView(table, viewFor: table.tableColumns[0], row: 0) as! HistoryManagerRowCell
        }
        precondition(button.image != nil && button.accessibilityLabel() == "Add to favorites")
        precondition(currentRow().favoriteIndicator.isHidden)
        let before = board.changeCount
        button.performClick(nil)
        precondition(history.allEntries()[0].isFavorite)
        let favoriteReload = try FileEntryStore(root: root).loadAll()[0]
        precondition(favoriteReload.isFavorite)
        precondition(button.title == "Unfavorite" && button.accessibilityLabel() == "Remove from favorites")
        let cell = currentRow()
        precondition(!cell.favoriteIndicator.isHidden && cell.favoriteIndicator.image != nil)
        precondition(cell.favoriteIndicator.accessibilityLabel() == "Favorite")
        cell.backgroundStyle = .emphasized
        precondition(cell.favoriteIndicator.contentTintColor == .alternateSelectedControlTextColor)
        cell.backgroundStyle = .normal
        precondition(cell.favoriteIndicator.contentTintColor == .secondaryLabelColor)
        button.performClick(nil)
        precondition(!history.allEntries()[0].isFavorite)
        let unfavoriteReload = try FileEntryStore(root: root).loadAll()[0]
        precondition(!unfavoriteReload.isFavorite)
        precondition(currentRow().favoriteIndicator.isHidden)
        precondition(board.changeCount == before, "Favorite action changed fixture clipboard")
        precondition(!manager.window!.isVisible, "Tests must not activate a Manager window")
        print("Interaction checks passed: picker-only shortcut/handoff without paste; favorite button, persistence, SF Symbol, accessibility and selection tint.")
    }
}
