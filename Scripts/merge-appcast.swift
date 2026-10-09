import Foundation

// Merge official generate_appcast output; never manufacture signature metadata.
// Archive signatures remain valid because they cover DMG bytes, not this XML.
do {
    let currentURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let previousURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let current = try XMLDocument(contentsOf: currentURL, options: [.nodeLoadExternalEntitiesNever])
    let previous = try XMLDocument(contentsOf: previousURL, options: [.nodeLoadExternalEntitiesNever])
    guard let channel = try current.nodes(forXPath: "/rss/channel").first as? XMLElement,
          let item = channel.elements(forName: "item").first,
          let buildString = item.elements(forName: "sparkle:version").first?.stringValue,
          let build = Int(buildString) else {
        throw NSError(domain: "MergeAppcast", code: 1)
    }
    for case let oldItem as XMLElement in try previous.nodes(forXPath: "/rss/channel/item") {
        guard let oldString = oldItem.elements(forName: "sparkle:version").first?.stringValue,
              let oldBuild = Int(oldString), oldBuild < build else {
            throw NSError(domain: "MergeAppcast", code: 2, userInfo: [NSLocalizedDescriptionKey: "Previous feed must contain only older integer build numbers"])
        }
        channel.addChild(oldItem.copy() as! XMLElement)
    }
    try current.xmlData(options: [.nodePrettyPrint]).write(to: currentURL, options: .atomic)
} catch {
    fputs("Appcast merge failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
