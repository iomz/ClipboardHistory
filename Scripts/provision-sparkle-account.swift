import CryptoKit
import Foundation
import Security

// OWNER-AUTHORIZED OPERATION ONLY. Compile is safe; running accesses private
// material and creates a login-Keychain item. Never invoked by build scripts.
func stop(_ message: String, status: OSStatus? = nil) -> Never {
    fputs(message + (status.map { " (OSStatus \($0))" } ?? "") + "\n", stderr)
    exit(1)
}
let args = CommandLine.arguments
guard args.count == 3, !args[1].isEmpty else {
    stop("Usage: provision-sparkle-account source-account Info.plist")
}
let destinationAccount = "com.iomz.TheClipboard"
guard args[1] != destinationAccount else { stop("Source must differ from destination") }
let infoData: Data
do { infoData = try Data(contentsOf: URL(fileURLWithPath: args[2])) }
catch { stop("Cannot read application metadata") }
guard let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
      info["CFBundleIdentifier"] as? String == destinationAccount,
      let publicString = info["SUPublicEDKey"] as? String,
      let approvedPublic = Data(base64Encoded: publicString), approvedPublic.count == 32 else {
    stop("Invalid identity or embedded public key")
}
var keychain: SecKeychain?
let loginPath = NSHomeDirectory() + "/Library/Keychains/login.keychain-db"
let openStatus = SecKeychainOpen(loginPath, &keychain)
guard openStatus == errSecSuccess, let keychain else { stop("Cannot open login Keychain", status: openStatus) }
func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "https://sparkle-project.org",
     kSecAttrAccount as String: account,
     kSecAttrProtocol as String: kSecAttrProtocolSSH,
     kSecMatchSearchList as String: [keychain],
     kSecMatchLimit as String: kSecMatchLimitOne]
}
var destinationQuery = query(destinationAccount)
destinationQuery[kSecReturnAttributes as String] = true
let existingStatus = SecItemCopyMatching(destinationQuery as CFDictionary, nil)
guard existingStatus == errSecItemNotFound else {
    stop("Destination exists or cannot be checked; nothing changed", status: existingStatus)
}
var sourceQuery = query(args[1])
sourceQuery[kSecReturnData as String] = true
var result: CFTypeRef?
let readStatus = SecItemCopyMatching(sourceQuery as CFDictionary, &result)
guard readStatus == errSecSuccess, let encoded = result as? Data,
      let seed = Data(base64Encoded: encoded), seed.count == 32 else {
    stop("Cannot read supported 32-byte signing seed; nothing changed", status: readStatus)
}
guard let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed),
      privateKey.publicKey.rawRepresentation == approvedPublic else {
    stop("Source key does not match approved public key; nothing changed")
}
// Preserve encoded key bytes exactly; SecItemAdd fails on a racing duplicate.
// No SecItemUpdate/Delete, disk export, random key generation or fallback.
let addition: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "https://sparkle-project.org",
    kSecAttrAccount as String: destinationAccount,
    kSecAttrProtocol as String: kSecAttrProtocolSSH,
    kSecUseKeychain as String: keychain,
    kSecAttrIsSensitive as String: true,
    kSecAttrIsPermanent as String: true,
    kSecAttrLabel as String: "Private key for signing Sparkle updates",
    kSecAttrDescription as String: "private key",
    kSecAttrComment as String: "Public key (SUPublicEDKey): " + publicString,
    kSecValueData as String: encoded
]
let addStatus = SecItemAdd(addition as CFDictionary, nil)
guard addStatus == errSecSuccess else { stop("New item creation failed; source unchanged", status: addStatus) }
print("Approved key copied to The Clipboard signing account. Source item and backup unchanged; no private export.")
