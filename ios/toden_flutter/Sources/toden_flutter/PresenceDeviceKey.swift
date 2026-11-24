import Foundation
import Security

/// The presence device's P-256 key in the Secure Enclave (user token design
/// rev 4, section 14). The private key never leaves the Enclave and cannot be
/// exported. It is usable after the first unlock with no biometry or passcode
/// prompt, so background code can sign while the phone sits locked.
///
/// With no Secure Enclave (a simulator, an old Mac) there is no key: `create`
/// answers nil and presence runs as before, with no refresh and no seals.
enum PresenceDeviceKey {
  static let tagPrefix = "co.toden.flutter.presence.device."

  /// What is asked of the Keychain, as plain values XCTest can read.
  struct Request: Equatable {
    let keyType: String
    let sizeInBits: Int
    let secureEnclave: Bool
    let permanent: Bool
    let accessible: String
    let privateKeyUsageOnly: Bool
    let biometryOrPasscode: Bool
  }

  static let request = Request(
    keyType: kSecAttrKeyTypeECSECPrimeRandom as String,
    sizeInBits: 256,
    secureEnclave: true,
    permanent: true,
    accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
    privateKeyUsageOnly: true,
    biometryOrPasscode: false
  )

  /// The SecKeyCreateRandomKey attributes built from `request` for `tag`.
  static func attributes(tag: String) -> [String: Any]? {
    guard
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, .privateKeyUsage, nil)
    else { return nil }
    return [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: request.sizeInBits,
      kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: request.permanent,
        kSecAttrApplicationTag as String: Data(tag.utf8),
        kSecAttrAccessControl as String: access,
      ] as [String: Any],
    ]
  }

  struct Created {
    let tag: String
    let publicKey: String
    let keyStorage: String
  }

  /// A new key under a new tag (one key, one registration), or nil.
  static func create() -> Created? {
    let tag = tagPrefix + UUID().uuidString
    guard let attributes = attributes(tag: tag),
          let key = SecKeyCreateRandomKey(attributes as CFDictionary, nil),
          let pub = SecKeyCopyPublicKey(key),
          let point = SecKeyCopyExternalRepresentation(pub, nil) as Data?,
          let spki = PresenceDeviceRules.spki(fromX963: point)
    else {
      delete(tag: tag)
      return nil
    }
    return Created(tag: tag, publicKey: spki.base64EncodedString(), keyStorage: "secure_enclave")
  }

  private static func find(tag: String) -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: Data(tag.utf8),
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecReturnRef as String: true,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let found = item else { return nil }
    return (found as! SecKey)
  }

  /// ECDSA-SHA256 over `text`, base64 DER (X9.62), or nil when the key is gone
  /// or locked before the first unlock.
  static func sign(tag: String, text: String) -> String? {
    guard let key = find(tag: tag),
          let signature = SecKeyCreateSignature(
            key, .ecdsaSignatureMessageX962SHA256, Data(text.utf8) as CFData, nil) as Data?
    else { return nil }
    return signature.base64EncodedString()
  }

  static func delete(tag: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: Data(tag.utf8),
    ]
    SecItemDelete(query as CFDictionary)
  }
}
