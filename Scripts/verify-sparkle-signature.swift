import CryptoKit
import Foundation

do {
    let args = CommandLine.arguments
    let plistData = try Data(contentsOf: URL(fileURLWithPath: args[1]))
    let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
    guard let encodedKey = plist["SUPublicEDKey"] as? String,
          let publicKey = Data(base64Encoded: encodedKey) else {
        throw NSError(domain: "SparkleKeyProof", code: 1)
    }
    let message = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let encodedSignature = try String(contentsOfFile: args[3], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
    guard let signature = Data(base64Encoded: encodedSignature), key.isValidSignature(signature, for: message) else {
        throw NSError(domain: "SparkleKeyProof", code: 2)
    }
    print("Keychain signing capability verified against trusted bundle public key. No private key exported.")
} catch {
    fputs("Sparkle signing proof failed. Stop; do not replace or rotate keys.\n", stderr)
    exit(1)
}
