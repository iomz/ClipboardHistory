import AppKit
import ClipboardCore
import ClipboardPlatform
import Foundation

@main
enum RepresentationChecks {
    static func main() throws {
        let fixtures = try makeFixtures()
        for fixture in fixtures {
            try roundTrip(fixture)
        }
        try testUnsupportedTypeIsReportedAndNotPersisted()
        try testMixedFileAndImageClassificationIsOrderIndependent()
        try testPlainTextPasteDecisionAndRestore()
        try testShiftBadgePreviewUsesPlainPasteCapability()
        try testHoverRegionLifetime()
        print("Representation checks passed: \(fixtures.count) exact synthetic pasteboard round trips; diagnostics, plain-text policy, Shift badge preview, and hover lifetime passed")
    }

    private static func makeFixtures() throws -> [Fixture] {
        let png = try imageData(type: .png)
        let tiff = try imageData(type: .tiff)
        let rtfText = "Clipboard fixture — 日本語 🐈\nsecond line"
        let rtf = Data("{\\rtf1\\ansi \(rtfText)}".utf8)
        let html = Data("<html><body><b>\(rtfText)</b></body></html>".utf8)
        let plain = Data(rtfText.utf8)
        let url = Data("https://example.test/synthetic?item=1".utf8)
        let fileA = Data(URL(fileURLWithPath: "/tmp/TheClipboard-fixture-A.txt").absoluteString.utf8)
        let fileB = Data(URL(fileURLWithPath: "/tmp/TheClipboard-fixture-B.png").absoluteString.utf8)

        return [
            Fixture(name: "plain UTF-8", items: [[rep("public.utf8-plain-text", plain)]], expectedLabel: "TXT"),
            Fixture(name: "Unicode/Japanese/emoji", items: [[rep("public.utf8-plain-text", Data("日本語の clipboard 🐈‍⬛\nline 2".utf8))]], expectedLabel: "TXT"),
            Fixture(name: "plain + RTF + HTML composite", items: [[
                rep("public.utf8-plain-text", plain), rep("public.rtf", rtf), rep("public.html", html),
            ]], expectedLabel: "RTF"),
            Fixture(name: "PNG", items: [[rep("public.png", png)]], expectedLabel: "IMG"),
            Fixture(name: "TIFF", items: [[rep("public.tiff", tiff)]], expectedLabel: "IMG"),
            Fixture(name: "URL", items: [[rep("public.url", url)]], expectedLabel: "URL"),
            Fixture(name: "single file URL", items: [[rep("public.file-url", fileA)]], expectedLabel: "FILE"),
            Fixture(name: "multiple file URLs", items: [
                [rep("public.file-url", fileA)], [rep("public.file-url", fileB)],
            ], expectedLabel: "FILE"),
        ]
    }

    private static func roundTrip(_ fixture: Fixture) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TheClipboard-RepresentationTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileEntryStore(root: root)
        let history = ClipboardLibrary(store: store)
        let sourceBoard = NSPasteboard(name: NSPasteboard.Name("com.iomz.TheClipboard.Test.Source.\(UUID().uuidString)"))
        let targetBoard = NSPasteboard(name: NSPasteboard.Name("com.iomz.TheClipboard.Test.Target.\(UUID().uuidString)"))
        defer { sourceBoard.clearContents(); targetBoard.clearContents() }
        try write(fixture.items, to: sourceBoard)

        let sourceAdvertised = sourceBoard.pasteboardItems!.map { Set($0.types.map(\.rawValue)) }
        try require(sourceAdvertised.count == fixture.items.count, "\(fixture.name): source item count")
        for (index, expectedTypes) in fixture.items.enumerated() {
            try require(expectedTypes.allSatisfy({ sourceAdvertised[index].contains($0.typeIdentifier) }), "\(fixture.name): source advertises fixture types")
        }

        guard let snapshot = PasteboardSnapshotter.capture(
            from: sourceBoard,
            sourceApplication: SourceApplication(bundleIdentifier: "test.synthetic", displayName: "Synthetic fixture")
        ) else { throw CheckFailure(message: "\(fixture.name): no capture") }
        try require(snapshot.entry.compactTypeLabel == fixture.expectedLabel, "\(fixture.name): classification")
        let retainedByItem = snapshot.entry.pasteboardItems.map { Set($0.representations.map(\.typeIdentifier)) }
        let advertisedSupported = sourceAdvertised.map { $0.intersection(PasteboardSnapshotter.supportedTypeIdentifiers) }
        try require(retainedByItem == advertisedSupported, "\(fixture.name): capture retains every advertised supported representation")

        try history.capture(snapshot.entry)
        let reloaded = try FileEntryStore(root: root).loadAll()
        guard let persisted = reloaded.first else { throw CheckFailure(message: "\(fixture.name): missing persisted item") }
        try require(persisted.pasteboardItems.count == fixture.items.count, "\(fixture.name): persisted item grouping")
        try require(PasteboardRestorer.restore(persisted, plainTextOnly: false, to: targetBoard), "\(fixture.name): restore")

        guard let restoredItems = targetBoard.pasteboardItems else { throw CheckFailure(message: "\(fixture.name): no restored items") }
        try require(restoredItems.count == fixture.items.count, "\(fixture.name): restored item count")
        for index in fixture.items.indices {
            let restored = restoredItems[index]
            let persistedTypes = Set(persisted.pasteboardItems[index].representations.map(\.typeIdentifier))
            try require(Set(restored.types.map(\.rawValue)) == persistedTypes, "\(fixture.name): restored type set")
            for representation in persisted.pasteboardItems[index].representations {
                try require(
                    restored.data(forType: NSPasteboard.PasteboardType(representation.typeIdentifier)) == representation.data,
                    "\(fixture.name): exact synthetic bytes for \(representation.typeIdentifier)"
                )
            }
            for representation in fixture.items[index] {
                let captured = persisted.pasteboardItems[index].representations.first(where: { $0.typeIdentifier == representation.typeIdentifier })
                try require(captured?.data == representation.data, "\(fixture.name): original fixture bytes retained for \(representation.typeIdentifier)")
            }
        }
        let retainedCount = persisted.pasteboardItems.flatMap(\.representations).count
        print("PASS \(fixture.name): advertised → captured → persisted → restored; \(retainedCount) representation(s), \(fixture.items.count) item(s)")
    }

    private static func testUnsupportedTypeIsReportedAndNotPersisted() throws {
        let marker = "SYNTHETIC-DIAGNOSTIC-MARKER-DO-NOT-PRINT"
        let item = [rep("public.utf8-plain-text", Data(marker.utf8)), rep("com.example.synthetic-opaque", Data("private synthetic payload".utf8))]
        let board = NSPasteboard(name: NSPasteboard.Name("com.iomz.TheClipboard.Test.Unsupported.\(UUID().uuidString)"))
        defer { board.clearContents() }
        try write([item], to: board)
        guard let snapshot = PasteboardSnapshotter.capture(from: board) else { throw CheckFailure(message: "unsupported diagnostic fixture capture") }
        let statuses = snapshot.diagnostics[0].representations
        try require(statuses.contains(where: { $0.typeIdentifier == "com.example.synthetic-opaque" && $0.disposition == .unsupported }), "unsupported type marked dropped")
        try require(statuses.contains(where: { $0.typeIdentifier == "public.utf8-plain-text" && $0.disposition == .retained }), "supported type marked retained")
        try require(!snapshot.metadataReport.contains(marker) && !snapshot.metadataReport.contains("private synthetic payload"), "diagnostic report contains metadata only")
        try require(snapshot.entry.pasteboardItems[0].representations.count == 1, "unsupported payload not retained")
    }

    private static func testMixedFileAndImageClassificationIsOrderIndependent() throws {
        let image = rep("public.png", try imageData(type: .png))
        let file = rep("public.file-url", Data(URL(fileURLWithPath: "/tmp/synthetic-image.png").absoluteString.utf8))
        let first = ClipboardEntry(pasteboardItems: [.init(ordinal: 0, representations: [image, file])])
        let reversed = ClipboardEntry(pasteboardItems: [.init(ordinal: 0, representations: [file, image])])
        try require(first.compactTypeLabel == "MIX" && reversed.compactTypeLabel == "MIX", "file+image classified as explicit mixed, independent of order")
        try require(first.typeSummary == "Mixed file and image", "mixed semantic summary")
    }

    private static func testPlainTextPasteDecisionAndRestore() throws {
        let source = NSPasteboard(name: NSPasteboard.Name("com.iomz.TheClipboard.Test.PlainPaste.Source.\(UUID().uuidString)"))
        let target = NSPasteboard(name: NSPasteboard.Name("com.iomz.TheClipboard.Test.PlainPaste.Target.\(UUID().uuidString)"))
        defer { source.clearContents(); target.clearContents() }

        let explicitText = "plain wins — 日本語 🐈"
        let composite = [
            rep("public.html", Data("<p>HTML-derived fallback</p>".utf8)),
            rep("public.rtf", Data("{\\rtf1 rich fallback}".utf8)),
            rep("public.utf8-plain-text", Data(explicitText.utf8)),
        ]
        try write([composite], to: source)
        let snapshot = PasteboardSnapshotter.capture(from: source)
        try require(PlainTextPastePolicy.text(from: snapshot) == explicitText, "explicit plain text preferred over rich representations")
        try require(PasteboardRestorer.restorePlainText(explicitText, to: target), "plain-only clipboard restore")
        try require(target.string(forType: .string) == explicitText, "restored plain text matches selected text")
        let restoredTypes = Set((target.types ?? []).map(\.rawValue))
        try require(restoredTypes.contains(NSPasteboard.PasteboardType.string.rawValue), "plain restore advertises standard string type")
        try require(restoredTypes.isDisjoint(with: ["public.rtf", "public.rtfd", "public.html", "public.png", "public.tiff"]), "plain restore drops rich and non-text representations")

        let richOnly = NSPasteboard(name: NSPasteboard.Name("com.iomz.TheClipboard.Test.RichPlain.Source.\(UUID().uuidString)"))
        defer { richOnly.clearContents() }
        try write([[rep("public.html", Data("<p>derived text</p>".utf8))]], to: richOnly)
        let richSnapshot = PasteboardSnapshotter.capture(from: richOnly)
        let derived = PlainTextPastePolicy.text(from: richSnapshot)
        try require(derived == "derived text\n", "HTML-derived text follows existing AppKit normalization")

        let imageOnly = NSPasteboard(name: NSPasteboard.Name("com.iomz.TheClipboard.Test.NonTextPlain.Source.\(UUID().uuidString)"))
        defer { imageOnly.clearContents() }
        try write([[rep("public.png", imageData(type: .png))]], to: imageOnly)
        let originalTypes = Set((imageOnly.types ?? []).map(\.rawValue))
        let originalChangeCount = imageOnly.changeCount
        try require(PlainTextPastePolicy.text(from: PasteboardSnapshotter.capture(from: imageOnly)) == nil, "image-only clipboard has no plain-paste fallback")
        try require(imageOnly.changeCount == originalChangeCount, "non-text decision leaves original clipboard untouched")
        try require(Set((imageOnly.types ?? []).map(\.rawValue)) == originalTypes, "non-text representations remain unchanged")
    }

    private static func testShiftBadgePreviewUsesPlainPasteCapability() throws {
        let image = rep("public.png", try imageData(type: .png))
        let file = rep("public.file-url", Data(URL(fileURLWithPath: "/tmp/shift-preview-fixture.txt").absoluteString.utf8))
        let entries = try [
            capturedEntry([rep("public.rtf", Data("{\\rtf1 rich text}".utf8))]),
            capturedEntry([rep("public.html", Data("<p>html text</p>".utf8))]),
            capturedEntry([rep("public.utf8-plain-text", Data("plain".utf8))]),
            capturedEntry([image]),
            capturedEntry([file]),
            capturedEntry([image, file, rep("public.utf8-plain-text", Data("mixed text".utf8))]),
            capturedEntry([image, file]),
        ]
        let normalBadges = entries.map(\.compactTypeLabel)
        try require(normalBadges == ["RTF", "HTML", "TXT", "IMG", "FILE", "MIX", "MIX"], "synthetic normal badges")
        let originalEntries = entries
        let previewModels = entries.map(ClipboardEntryPreviewModel.init(entry:))
        try require(previewModels.map(\.text) == entries.map { $0.plainText ?? $0.preview }, "shared Manager and picker preview text semantics")
        try require(previewModels[3].image != nil && previewModels[4].image == nil && previewModels[5].image != nil, "image data previews without fabricating file thumbnails")
        try require(previewModels[4].typeDescription == "File · FILE" && previewModels[6].typeDescription == "Mixed file and image · MIX", "shared type descriptions for file and mixed entries")
        try require(entries == originalEntries, "preview model construction does not mutate history entries")

        var preview = PickerBadgePreviewState()
        try require(entries.map { preview.badge(for: $0) } == normalBadges, "Shift-up shows original badges")
        preview.updateShift(isDown: true)
        let shiftedBadges = entries.map { preview.badge(for: $0) }
        try require(shiftedBadges == ["TXT", "TXT", "TXT", "IMG", "FILE", "TXT", "MIX"], "Shift preview follows actual plain-paste capability")
        try require(entries == originalEntries, "preview does not mutate history entries or classification")

        preview.updateShift(isDown: false)
        try require(entries.map { preview.badge(for: $0) } == normalBadges, "Shift release restores original badges")
        preview.updateShift(isDown: true)
        preview.reset()
        try require(!preview.isShiftDown && entries.map { preview.badge(for: $0) } == normalBadges, "dismiss reset prevents stale Shift preview")
        try require(entries == originalEntries, "preview state never changes stored entries")
    }

    private static func capturedEntry(_ representations: [ClipboardRepresentation]) throws -> ClipboardEntry {
        let board = NSPasteboard(name: NSPasteboard.Name("com.iomz.TheClipboard.Test.BadgePreview.\(UUID().uuidString)"))
        defer { board.clearContents() }
        try write([representations], to: board)
        guard let snapshot = PasteboardSnapshotter.capture(from: board) else {
            throw CheckFailure(message: "badge preview fixture capture")
        }
        return snapshot.entry
    }

    private static func testHoverRegionLifetime() throws {
        let row = UUID()
        let nextRow = UUID()
        var state = PickerHoverRegionState()
        state.enterRow(row)
        try require(state.entryID == row && !state.shouldDismiss, "hover row keeps session alive")
        try require(state.exitRow(row) && state.shouldDismiss, "leaving row schedules dismissal unless preview entered")
        state.enterPreview()
        try require(!state.shouldDismiss, "preview entry cancels row-exit dismissal")
        state.exitPreview()
        try require(state.shouldDismiss, "leaving preview and row allows dismissal")
        state.enterRow(nextRow)
        try require(state.entryID == nextRow && !state.shouldDismiss, "new row becomes active hover target")
        try require(!state.exitRow(row) && state.entryID == nextRow, "stale previous-row exit cannot dismiss new preview")
        state.reset()
        try require(state.entryID == nil && state.shouldDismiss, "hover session resets cleanly")
    }

    private static func imageData(type: NSBitmapImageRep.FileType) throws -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw CheckFailure(message: "synthetic bitmap allocation") }
        bitmap.setColor(NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1), atX: 0, y: 0)
        bitmap.setColor(NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1), atX: 1, y: 0)
        bitmap.setColor(NSColor(calibratedRed: 0, green: 1, blue: 0, alpha: 1), atX: 2, y: 0)
        guard let data = bitmap.representation(using: type, properties: [:]) else {
            throw CheckFailure(message: "synthetic image encoding \(type)")
        }
        return data
    }

    private static func write(_ items: [[ClipboardRepresentation]], to pasteboard: NSPasteboard) throws {
        pasteboard.clearContents()
        let nativeItems = items.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for representation in representations {
                item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.typeIdentifier))
            }
            return item
        }
        try require(pasteboard.writeObjects(nativeItems), "synthetic named-pasteboard write")
    }

    private static func rep(_ type: String, _ data: Data) -> ClipboardRepresentation {
        ClipboardRepresentation(typeIdentifier: type, data: data)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure(message: "Check failed: \(message)") }
    }
}

private struct Fixture {
    let name: String
    let items: [[ClipboardRepresentation]]
    let expectedLabel: String
}

private struct CheckFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
