import Foundation
import CryptoKit
// Read a Sparkle Ed25519 seed file without ever logging its private contents.
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let raw = Data(base64Encoded: data, options: .ignoreUnknownCharacters), raw.count == 32 else {
    fatalError("Expected a base64-encoded 32-byte signing seed")
}
let key = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
print(key.publicKey.rawRepresentation.base64EncodedString())
