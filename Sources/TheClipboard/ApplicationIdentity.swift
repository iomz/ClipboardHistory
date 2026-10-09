import Foundation

enum ApplicationIdentity {
    static func supportDirectory(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent("TheClipboard", isDirectory: true)
    }
}
