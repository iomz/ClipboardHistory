import Foundation

// Test XML merge mechanics with copies of actual generated metadata, never a
// publishable fake release. All fixtures are removed when this process exits.
let tool = CommandLine.arguments[1]
let feed = URL(fileURLWithPath: CommandLine.arguments[2])
let work = FileManager.default.temporaryDirectory.appendingPathComponent("TheClipboard-merge-tests-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: work) }

func merge(_ current: URL, _ previous: URL) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    process.arguments = [tool, current.path, previous.path]
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

let options: XMLNode.Options = [.nodeLoadExternalEntitiesNever]
let previous = try XMLDocument(contentsOf: feed, options: options)
let originalItems = try previous.nodes(forXPath: "/rss/channel/item")
precondition(!originalItems.isEmpty, "Need generated release items")
let original = originalItems[0] as! XMLElement
let next = previous.copy() as! XMLDocument
let nextItem = try next.nodes(forXPath: "/rss/channel/item")[0] as! XMLElement
let nextChannel = try next.nodes(forXPath: "/rss/channel")[0] as! XMLElement
// Official generation yields only the current release before merge. Simulate
// that shape even when the supplied feed already contains multiple releases.
for extra in nextChannel.elements(forName: "item").dropFirst().reversed() {
    nextChannel.removeChild(at: extra.index)
}
let oldBuild = Int(original.elements(forName: "sparkle:version")[0].stringValue!)!
nextItem.elements(forName: "sparkle:version")[0].stringValue = String(oldBuild + 1)
let currentURL = work.appendingPathComponent("current.xml")
try next.xmlData().write(to: currentURL)
let successStatus = try merge(currentURL, feed)
precondition(successStatus == 0, "Merge should accept older build")
let merged = try XMLDocument(contentsOf: currentURL, options: options)
let mergedItems = try merged.nodes(forXPath: "/rss/channel/item")
precondition(mergedItems.count == originalItems.count + 1, "Merge lost item")
for (index, originalNode) in originalItems.enumerated() {
    let retained = mergedItems[index + 1] as! XMLElement
    let originalItem = originalNode as! XMLElement
    for name in ["sparkle:version", "sparkle:shortVersionString", "sparkle:minimumSystemVersion", "sparkle:hardwareRequirements"] {
        precondition(retained.elements(forName: name).first?.stringValue == originalItem.elements(forName: name).first?.stringValue)
    }
    let retainedEnclosure = retained.elements(forName: "enclosure")[0]
    let originalEnclosure = originalItem.elements(forName: "enclosure")[0]
    for name in ["url", "length", "sparkle:edSignature"] {
        precondition(retainedEnclosure.attribute(forName: name)?.stringValue == originalEnclosure.attribute(forName: name)?.stringValue, "Merge changed \(name)")
    }
}
let identicalURL = work.appendingPathComponent("identical.xml")
try previous.xmlData().write(to: identicalURL)
let rejectedStatus = try merge(identicalURL, feed)
precondition(rejectedStatus != 0, "Merge should reject same/newer build")
print("Appcast merge checks passed: older metadata/signatures/URLs preserved; non-older builds rejected.")
