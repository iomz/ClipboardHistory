import Foundation

public final class FileEntryStore: ClipboardEntryStore {
    private struct RepresentationReference: Codable {
        let typeIdentifier: String
        let filename: String
    }

    private struct ItemReference: Codable {
        let ordinal: Int
        let representations: [RepresentationReference]
    }

    private struct Metadata: Codable {
        let schemaVersion: Int
        let id: UUID
        let firstCapturedAt: Date
        let lastCapturedAt: Date
        let sourceApplication: SourceApplication
        let isFavorite: Bool
        let plainText: String?
        let canonicalIdentity: String
        let items: [ItemReference]
    }

    private let root: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    public init(root: URL) throws {
        self.root = root
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func loadAll() -> [ClipboardEntry] {
        lock.lock(); defer { lock.unlock() }
        guard let children = try? fileManager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.compactMap(loadEntry(at:)).sorted { $0.lastCapturedAt > $1.lastCapturedAt }
    }

    public func upsert(_ entry: ClipboardEntry) throws {
        lock.lock(); defer { lock.unlock() }
        let staging = root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let destination = root.appendingPathComponent(entry.id.uuidString, isDirectory: true)
        let backup = root.appendingPathComponent(".backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            var itemReferences: [ItemReference] = []
            for item in entry.pasteboardItems.sorted(by: { $0.ordinal < $1.ordinal }) {
                var references: [RepresentationReference] = []
                for (offset, representation) in item.representations.enumerated() {
                    let filename = "item-\(item.ordinal)-representation-\(offset).bin"
                    try representation.data.write(to: staging.appendingPathComponent(filename), options: .atomic)
                    references.append(RepresentationReference(typeIdentifier: representation.typeIdentifier, filename: filename))
                }
                itemReferences.append(ItemReference(ordinal: item.ordinal, representations: references))
            }
            let metadata = Metadata(
                schemaVersion: 1, id: entry.id, firstCapturedAt: entry.firstCapturedAt,
                lastCapturedAt: entry.lastCapturedAt, sourceApplication: entry.sourceApplication,
                isFavorite: entry.isFavorite, plainText: entry.plainText,
                canonicalIdentity: entry.canonicalIdentity, items: itemReferences
            )
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            try encoder.encode(metadata).write(to: staging.appendingPathComponent("metadata.plist"), options: .atomic)

            let hadDestination = fileManager.fileExists(atPath: destination.path)
            if hadDestination { try fileManager.moveItem(at: destination, to: backup) }
            do {
                try fileManager.moveItem(at: staging, to: destination)
                if hadDestination { try? fileManager.removeItem(at: backup) }
            } catch {
                if hadDestination { try? fileManager.moveItem(at: backup, to: destination) }
                throw error
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    public func remove(id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        let directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func loadEntry(at directory: URL) -> ClipboardEntry? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("metadata.plist")),
              let metadata = try? PropertyListDecoder().decode(Metadata.self, from: data),
              metadata.schemaVersion == 1 else { return nil }
        var items: [ClipboardPasteboardItem] = []
        for item in metadata.items.sorted(by: { $0.ordinal < $1.ordinal }) {
            var representations: [ClipboardRepresentation] = []
            for reference in item.representations {
                guard !reference.filename.contains("/"),
                      let payload = try? Data(contentsOf: directory.appendingPathComponent(reference.filename)) else { return nil }
                representations.append(ClipboardRepresentation(typeIdentifier: reference.typeIdentifier, data: payload))
            }
            items.append(ClipboardPasteboardItem(ordinal: item.ordinal, representations: representations))
        }
        var entry = ClipboardEntry(
            id: metadata.id, capturedAt: metadata.firstCapturedAt,
            sourceApplication: metadata.sourceApplication, isFavorite: metadata.isFavorite,
            pasteboardItems: items, plainText: metadata.plainText
        )
        entry.lastCapturedAt = metadata.lastCapturedAt
        guard entry.canonicalIdentity == metadata.canonicalIdentity else { return nil }
        return entry
    }
}
