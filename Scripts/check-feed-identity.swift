import Foundation

// Only feeds belonging to The Clipboard may enter its release pipeline.
// Reusing an EdDSA key does not make the previous product an update target.
let document = try XMLDocument(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), options: [.nodeLoadExternalEntitiesNever])
let items = try document.nodes(forXPath: "/rss/channel/item/enclosure")
guard !items.isEmpty else { fatalError("Previous feed has no enclosures") }
for case let enclosure as XMLElement in items {
    guard let url = enclosure.attribute(forName: "url")?.stringValue,
          url.hasPrefix("https://github.com/iomz/TheClipboard/releases/download/") else {
        fputs("Refusing a previous feed that does not belong to The Clipboard. No legacy OTA migration.\n", stderr)
        exit(1)
    }
}
