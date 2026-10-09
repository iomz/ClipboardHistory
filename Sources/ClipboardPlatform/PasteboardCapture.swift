import AppKit
import ClipboardCore
import Foundation
import UniformTypeIdentifiers

public struct RepresentationDiagnostic: Equatable {
    public enum Disposition: String { case retained, unsupported, unavailable }
    public let typeIdentifier: String
    public let disposition: Disposition
    public let byteCount: Int?
}

public struct PasteboardItemDiagnostic: Equatable {
    public let ordinal: Int
    public let advertisedTypes: [String]
    public let representations: [RepresentationDiagnostic]
}

public struct PasteboardSnapshot {
    public let entry: ClipboardEntry
    public let diagnostics: [PasteboardItemDiagnostic]

    /// Metadata only. Never includes representation payload bytes or text values.
    public var metadataReport: String {
        var lines = [
            "Classification: \(entry.compactTypeLabel) (\(entry.typeSummary))",
            "Items: \(diagnostics.count)",
        ]
        for item in diagnostics {
            lines.append("\nItem \(item.ordinal + 1) — \(item.advertisedTypes.count) advertised type(s)")
            lines.append("Advertised: \(item.advertisedTypes.isEmpty ? "none" : item.advertisedTypes.joined(separator: ", "))")
            for representation in item.representations {
                let size = representation.byteCount.map { " (\($0) bytes)" } ?? ""
                lines.append("\(representation.disposition.rawValue): \(representation.typeIdentifier)\(size)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum PlainTextPastePolicy {
    /// Non-text snapshots and empty text fail closed; never trigger a rich-paste fallback.
    public static func text(from snapshot: PasteboardSnapshot?) -> String? {
        guard let text = snapshot?.entry.plainText, !text.isEmpty else { return nil }
        return text
    }
}

/// Shared capture/normalization path for live monitoring and diagnostics/tests.
public enum PasteboardSnapshotter {
    public static let supportedTypeIdentifiers: Set<String> = [
        UTType.utf8PlainText.identifier, UTType.plainText.identifier,
        UTType.rtf.identifier, UTType.rtfd.identifier, UTType.html.identifier,
        UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier,
        UTType.url.identifier, UTType.fileURL.identifier,
        "public.utf16-external-plain-text", "com.apple.flat-rtfd"
    ]

    public static func capture(
        from pasteboard: NSPasteboard,
        sourceApplication: SourceApplication = SourceApplication(),
        capturedAt: Date = Date()
    ) -> PasteboardSnapshot? {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else { return nil }
        var capturedItems: [ClipboardPasteboardItem] = []
        var itemDiagnostics: [PasteboardItemDiagnostic] = []
        var derivedText: String?

        for (itemIndex, pasteboardItem) in pasteboardItems.enumerated() {
            let advertisedTypes = pasteboardItem.types.map(\.rawValue).sorted()
            var representations: [ClipboardRepresentation] = []
            var representationDiagnostics: [RepresentationDiagnostic] = []
            for type in advertisedTypes {
                guard supportedTypeIdentifiers.contains(type) else {
                    representationDiagnostics.append(.init(typeIdentifier: type, disposition: .unsupported, byteCount: nil))
                    continue
                }
                guard let data = pasteboardItem.data(forType: NSPasteboard.PasteboardType(type)) else {
                    representationDiagnostics.append(.init(typeIdentifier: type, disposition: .unavailable, byteCount: nil))
                    continue
                }
                representations.append(ClipboardRepresentation(typeIdentifier: type, data: data))
                representationDiagnostics.append(.init(typeIdentifier: type, disposition: .retained, byteCount: data.count))
            }
            itemDiagnostics.append(PasteboardItemDiagnostic(
                ordinal: itemIndex, advertisedTypes: advertisedTypes, representations: representationDiagnostics
            ))
            if derivedText == nil {
                derivedText = ClipboardEntry.extractPlainText(from: representations)
                    ?? deriveRichText(from: representations)
            }
            if !representations.isEmpty {
                capturedItems.append(ClipboardPasteboardItem(ordinal: itemIndex, representations: representations))
            }
        }
        guard !capturedItems.isEmpty else { return nil }
        let entry = ClipboardEntry(
            capturedAt: capturedAt,
            sourceApplication: sourceApplication,
            pasteboardItems: capturedItems,
            plainText: derivedText
        )
        return PasteboardSnapshot(entry: entry, diagnostics: itemDiagnostics)
    }

    private static func deriveRichText(from representations: [ClipboardRepresentation]) -> String? {
        for representation in representations {
            let type = representation.typeIdentifier
            guard type == UTType.rtf.identifier || type == UTType.rtfd.identifier || type == UTType.html.identifier else { continue }
            let documentType: NSAttributedString.DocumentType = type == UTType.html.identifier ? .html : (type == UTType.rtfd.identifier ? .rtfd : .rtf)
            if let attributed = try? NSAttributedString(
                data: representation.data,
                options: [.documentType: documentType],
                documentAttributes: nil
            ), !attributed.string.isEmpty {
                return attributed.string
            }
        }
        return nil
    }
}

public final class PasteboardCapture {
    private let pasteboard: NSPasteboard
    private let history: ClipboardLibrary
    private var timer: Timer?
    private var lastChangeCount: Int

    public init(history: ClipboardLibrary, pasteboard: NSPasteboard = .general) {
        self.history = history
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func noteOwnWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    /// Use the same board as monitoring, including isolated test boards.
    func restore(_ entry: ClipboardEntry, plainTextOnly: Bool) -> Bool {
        guard PasteboardRestorer.restore(entry, plainTextOnly: plainTextOnly, to: pasteboard) else { return false }
        noteOwnWrite()
        return true
    }

    func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = SourceApplication(
            bundleIdentifier: frontmost?.bundleIdentifier,
            displayName: frontmost?.localizedName
        )
        guard let snapshot = PasteboardSnapshotter.capture(from: pasteboard, sourceApplication: source) else { return }
        do { try history.capture(snapshot.entry) }
        catch { NSSound.beep() }
    }
}

public enum PasteboardRestorer {
    public static func plainText(for entry: ClipboardEntry) -> String? {
        guard let text = entry.plainText, !text.isEmpty else { return nil }
        return text
    }

    @discardableResult
    public static func restorePlainText(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        guard !text.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    @discardableResult
    public static func restore(_ entry: ClipboardEntry, plainTextOnly: Bool, to pasteboard: NSPasteboard = .general) -> Bool {
        if plainTextOnly {
            guard let text = plainText(for: entry) else { return false }
            return restorePlainText(text, to: pasteboard)
        }
        let items = entry.pasteboardItems.sorted { $0.ordinal < $1.ordinal }.map { modelItem -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for representation in modelItem.representations {
                item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.typeIdentifier))
            }
            return item
        }
        guard !items.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }
}
