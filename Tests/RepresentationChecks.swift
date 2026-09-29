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
        print("Representation checks passed: \(fixtures.count) exact synthetic pasteboard round trips; mixed classification and unsupported-type reporting passed")
    }

    private static func makeFixtures() throws -> [Fixture] {
        let png = try imageData(type: .png)
        let tiff = try imageData(type: .tiff)
        let rtfText = "Clipboard fixture — 日本語 🐈\nsecond line"
        let rtf = Data("{\\rtf1\\ansi \(rtfText)}".utf8)
        let html = Data("<html><body><b>\(rtfText)</b></body></html>".utf8)
        let plain = Data(rtfText.utf8)
        let url = Data("https://example.test/synthetic?item=1".utf8)
        let fileA = Data(URL(fileURLWithPath: "/tmp/ClipboardHistory-fixture-A.txt").absoluteString.utf8)
        let fileB = Data(URL(fileURLWithPath: "/tmp/ClipboardHistory-fixture-B.png").absoluteString.utf8)

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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardHistory-RepresentationTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try FileEntryStore(root: root)
        let history = ClipboardHistory(store: store)
        let sourceBoard = NSPasteboard(name: NSPasteboard.Name("com.iomz.ClipboardHistory.Test.Source.\(UUID().uuidString)"))
        let targetBoard = NSPasteboard(name: NSPasteboard.Name("com.iomz.ClipboardHistory.Test.Target.\(UUID().uuidString)"))
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
        let board = NSPasteboard(name: NSPasteboard.Name("com.iomz.ClipboardHistory.Test.Unsupported.\(UUID().uuidString)"))
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
