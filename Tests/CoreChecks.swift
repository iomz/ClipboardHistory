import Foundation

@main
enum CoreChecks {
    static func main() throws {
        try checkCanonicalIdentity()
        try checkPlainTextExtraction()
        try checkCompactTypeBadges()
        try checkDuplicatePromotion()
        try checkSharedFavoriteDeleteAndSearch()
        try checkFileStoreRoundTripAndIsolation()
        print("Core checks passed: canonical hash, duplicate promotion, persistence round-trip/corruption isolation")
    }

    static func checkPlainTextExtraction() throws {
        let value = "日本語 🐈\nmultiline"
        let representations = [ClipboardRepresentation(typeIdentifier: "public.utf8-plain-text", data: Data(value.utf8))]
        try require(ClipboardEntry.extractPlainText(from: representations) == value, "plain text extraction preserves Unicode and newlines")
        try require(ClipboardEntry.extractPlainText(from: [ClipboardRepresentation(typeIdentifier: "public.rtf", data: Data([1]))]) == nil, "opaque rich payload not mislabeled as plain text")
    }

    static func checkCompactTypeBadges() throws {
        let text = ClipboardEntry(pasteboardItems: [ClipboardPasteboardItem(ordinal: 0, representations: [
            ClipboardRepresentation(typeIdentifier: "public.utf8-plain-text", data: Data("text".utf8)),
        ])])
        let rich = ClipboardEntry(pasteboardItems: [ClipboardPasteboardItem(ordinal: 0, representations: [
            ClipboardRepresentation(typeIdentifier: "public.rtf", data: Data([1])),
            ClipboardRepresentation(typeIdentifier: "public.utf8-plain-text", data: Data("rich".utf8)),
        ])])
        let image = ClipboardEntry(pasteboardItems: [ClipboardPasteboardItem(ordinal: 0, representations: [
            ClipboardRepresentation(typeIdentifier: "public.png", data: Data([1])),
        ])])
        try require(text.compactTypeLabel == "TXT", "text badge")
        try require(rich.compactTypeLabel == "RTF", "rich representation wins over plain badge")
        try require(image.compactTypeLabel == "IMG", "image badge")
    }

    static func checkCanonicalIdentity() throws {
        let text = ClipboardRepresentation(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))
        let rtf = ClipboardRepresentation(typeIdentifier: "public.rtf", data: Data("{\\rtf1 hello}".utf8))
        let sameItem = ClipboardPasteboardItem(ordinal: 0, representations: [text, rtf])
        let reordered = ClipboardPasteboardItem(ordinal: 0, representations: [rtf, text])
        try require(ClipboardEntry.identity(for: [sameItem]) == ClipboardEntry.identity(for: [reordered]), "representation order canonicalized")
        let split = [
            ClipboardPasteboardItem(ordinal: 0, representations: [text]),
            ClipboardPasteboardItem(ordinal: 1, representations: [rtf]),
        ]
        try require(ClipboardEntry.identity(for: [sameItem]) != ClipboardEntry.identity(for: split), "item grouping affects identity")
    }

    static func checkDuplicatePromotion() throws {
        let store = MemoryStore()
        let history = ClipboardHistory(store: store)
        let firstDate = Date(timeIntervalSince1970: 100)
        let original = entry("same", source: "First")
        _ = try history.capture(original, at: firstDate)
        try history.setFavorite(true, for: original.id)
        _ = try history.capture(entry("other", source: "Other"), at: firstDate.addingTimeInterval(1))
        let latest = firstDate.addingTimeInterval(20)
        let result = try history.capture(entry("same", source: "Latest"), at: latest)
        try require(result.wasDuplicate, "duplicate detected")
        try require(result.entry.id == original.id, "stable identity preserved")
        try require(result.entry.isFavorite, "favorite preserved")
        try require(result.entry.sourceApplication.displayName == "Latest", "source updated")
        try require(result.entry.lastCapturedAt == latest, "recency updated")
        try require(history.allEntries().first?.id == original.id && history.allEntries().count == 2, "promoted to newest without duplicate row")
    }

    static func checkFileStoreRoundTripAndIsolation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileEntryStore(root: root)
        let rawText = "日本語 🐈\nline 2"
        let item = ClipboardPasteboardItem(ordinal: 0, representations: [
            ClipboardRepresentation(typeIdentifier: "public.rtf", data: Data([0, 1, 2, 255])),
            ClipboardRepresentation(typeIdentifier: "public.utf8-plain-text", data: Data(rawText.utf8)),
        ])
        let captured = Date(timeIntervalSince1970: 1000)
        var expected = ClipboardEntry(capturedAt: captured, pasteboardItems: [item], plainText: rawText)
        expected.lastCapturedAt = captured.addingTimeInterval(5)
        try store.upsert(expected)
        let corrupt = root.appendingPathComponent("corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        try Data("invalid metadata".utf8).write(to: corrupt.appendingPathComponent("metadata.plist"))
        let entries = store.loadAll()
        try require(entries.count == 1, "corrupt record isolated")
        try require(entries[0] == expected, "binary payload/persisted metadata round-trip")
        try require(entries[0].pasteboardItems[0].representations.count == 2, "simultaneous representations retained")
    }

    static func checkSharedFavoriteDeleteAndSearch() throws {
        let store = MemoryStore()
        let history = ClipboardHistory(store: store)
        let older = entry("older marker", source: "First")
        let newer = entry("newest marker", source: "Second")
        _ = try history.capture(older, at: Date(timeIntervalSince1970: 10))
        _ = try history.capture(newer, at: Date(timeIntervalSince1970: 20))
        try require(history.search("marker").count == 2, "shared search returns same matching data")
        try history.setFavorite(true, for: older.id)
        try require(history.allEntries().first(where: { $0.id == older.id })?.isFavorite == true, "favorite mutation immediately reflected in shared model")
        try require(history.search("older").first?.id == older.id, "search uses preview text")
        try history.remove(id: older.id)
        try require(history.allEntries().count == 1 && history.allEntries()[0].id == newer.id, "delete immediately removes item from shared model")
        try require(history.search("older").isEmpty, "deleted item disappears from search results")
    }

    static func entry(_ text: String, source: String) -> ClipboardEntry {
        ClipboardEntry(
            sourceApplication: SourceApplication(bundleIdentifier: "test.\(source)", displayName: source),
            pasteboardItems: [ClipboardPasteboardItem(ordinal: 0, representations: [
                ClipboardRepresentation(typeIdentifier: "public.utf8-plain-text", data: Data(text.utf8))
            ])],
            plainText: text
        )
    }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure(message: message) }
    }
}

struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { "Check failed: \(message)" }
}

private final class MemoryStore: ClipboardEntryStore {
    private var records: [UUID: ClipboardEntry] = [:]
    func loadAll() -> [ClipboardEntry] { Array(records.values) }
    func upsert(_ entry: ClipboardEntry) throws { records[entry.id] = entry }
    func remove(id: UUID) throws { records.removeValue(forKey: id) }
}
