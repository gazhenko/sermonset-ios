import Foundation
import CryptoKit
import Security

@MainActor public protocol DeviceRequestSigner: AnyObject {
    var publicKey: ServerPublicKey { get }
    func sign(_ bytes: Data) throws -> Data
    func exportPrivateKey() throws -> Data
}
@MainActor public final class MemoryDeviceIdentity: DeviceRequestSigner {
    private let key: P256.Signing.PrivateKey
    public init() { key = P256.Signing.PrivateKey() }
    public init(privateKey: Data) throws { key = try P256.Signing.PrivateKey(rawRepresentation: privateKey) }
    public var publicKey: ServerPublicKey { ServerPublicKey(key: key.publicKey) }
    public func sign(_ bytes: Data) throws -> Data { try key.signature(for: bytes).rawRepresentation }
    public func exportPrivateKey() throws -> Data { key.rawRepresentation }
}
/// Recoverable signing key, encrypted at rest by a Secure Enclave agreement key when available.
@MainActor public final class KeychainDeviceIdentity: DeviceRequestSigner {
    private let key: P256.Signing.PrivateKey
    public let usesSecureEnclaveProtection: Bool
    private struct Record: Codable {
        var version = 1
        var raw: Data?
        var enclave: Data?
        var ephemeral: Data?
        var sealed: Data?
    }
    private static func query(namespace: String) -> [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:namespace,kSecAttrAccount as String:"device-key-v1"]
    }
    public init(namespace: String = "com.gazhenko.sermonset.identity") throws {
        var query = Self.query(namespace: namespace); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary,&result)
        if status == errSecSuccess, let bytes = result as? Data {
            let record = try JSONDecoder().decode(Record.self,from: bytes)
            guard record.version == 1 else { throw Self.failure }
            if let raw = record.raw { key = try P256.Signing.PrivateKey(rawRepresentation: raw); usesSecureEnclaveProtection = false }
            else if let enclave = record.enclave, let ephemeral = record.ephemeral, let sealed = record.sealed {
                let protector = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: enclave)
                let secret = try protector.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: ephemeral))
                let wrapping = secret.hkdfDerivedSymmetricKey(using: SHA256.self,salt: Data(namespace.utf8),sharedInfo: Data("device-at-rest-v1".utf8),outputByteCount: 32)
                let raw = try AES.GCM.open(AES.GCM.SealedBox(combined: sealed),using: wrapping)
                key = try P256.Signing.PrivateKey(rawRepresentation: raw); usesSecureEnclaveProtection = true
            } else { throw Self.failure }
        } else if status == errSecItemNotFound {
            let signing = P256.Signing.PrivateKey()
            let record = try Self.protectedRecord(privateKey: signing.rawRepresentation,namespace: namespace)
            var attributes = Self.query(namespace: namespace)
            attributes[kSecValueData as String] = try JSONEncoder().encode(record)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(attributes as CFDictionary,nil) == errSecSuccess else { throw Self.failure }
            key = signing; usesSecureEnclaveProtection = record.enclave != nil
        } else { throw Self.failure }
    }
    public static func replace(privateKey: Data,namespace: String = "com.gazhenko.sermonset.identity") throws -> KeychainDeviceIdentity {
        _ = try P256.Signing.PrivateKey(rawRepresentation: privateKey)
        // Persist replacement only after validating imported key. Existing entry remains if update fails.
        let record = try protectedRecord(privateKey: privateKey,namespace: namespace)
        let query = query(namespace: namespace)
        let bytes = try JSONEncoder().encode(record)
        let status = SecItemUpdate(query as CFDictionary,[kSecValueData as String:bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query; attributes[kSecValueData as String] = bytes; attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(attributes as CFDictionary,nil) == errSecSuccess else { throw failure }
        } else if status != errSecSuccess { throw failure }
        return try KeychainDeviceIdentity(namespace: namespace)
    }
    private static func protectedRecord(privateKey: Data,namespace: String) throws -> Record {
        var record = Record(raw: privateKey)
        if SecureEnclave.isAvailable {
            let protector = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            let ephemeral = P256.KeyAgreement.PrivateKey()
            let secret = try ephemeral.sharedSecretFromKeyAgreement(with: protector.publicKey)
            let wrapping = secret.hkdfDerivedSymmetricKey(using: SHA256.self,salt: Data(namespace.utf8),sharedInfo: Data("device-at-rest-v1".utf8),outputByteCount: 32)
            record.raw = nil; record.enclave = protector.dataRepresentation; record.ephemeral = ephemeral.publicKey.x963Representation
            record.sealed = try AES.GCM.seal(privateKey,using: wrapping).combined
        }
        return record
    }
    public var publicKey: ServerPublicKey { ServerPublicKey(key: key.publicKey) }
    public func sign(_ bytes: Data) throws -> Data { try key.signature(for: bytes).rawRepresentation }
    public func exportPrivateKey() throws -> Data { key.rawRepresentation }
    private static var failure: SermonSetError { SermonSetError(title: "Device identity unavailable",message: "The app's device key could not be opened. Keep local recordings and use your recovery kit to restore account access.") }
}
public enum SignedRequest {
    public static func canonical(method: String,path: String,accountID: String?,timestamp: Int64,nonce: String,body: Data) -> Data {
        Data(["v1",method.uppercased(),path,accountID ?? "",String(timestamp),nonce,body.sha256Hex].joined(separator: "\n").utf8)
    }
    @MainActor public static func authorize(_ request: inout URLRequest,signer: any DeviceRequestSigner,accountID: String?,now: Date = .now,nonce: String = UUID().uuidString) throws {
        guard let url = request.url, let parts = URLComponents(url: url,resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        let path = parts.percentEncodedPath + (parts.percentEncodedQuery.map { "?"+$0 } ?? "")
        let time = Int64(now.timeIntervalSince1970)
        let signature = try signer.sign(canonical(method: request.httpMethod ?? "GET",path: path,accountID: accountID,timestamp: time,nonce: nonce,body: request.httpBody ?? Data()))
        request.setValue(accountID,forHTTPHeaderField: "X-Account-ID"); request.setValue(String(time),forHTTPHeaderField: "X-Timestamp"); request.setValue(nonce,forHTTPHeaderField: "X-Nonce"); request.setValue(signature.base64URL,forHTTPHeaderField: "X-Signature")
    }
}
public struct RecoveryKit: Codable, Sendable {
    public var version: Int = 1
    public var server: String
    public var accountID: String
    public var publicKey: ServerPublicKey
    var wrappedPrivateKey: WrappedSecret
    @MainActor public static func create(server: String,accountID: String,signer: any DeviceRequestSigner,passphrase: String) throws -> RecoveryKit {
        RecoveryKit(server: server,accountID: accountID,publicKey: signer.publicKey,wrappedPrivateKey: try WrappedSecret.wrap(signer.exportPrivateKey(),passphrase: passphrase))
    }
    @MainActor public func restore(passphrase: String) throws -> MemoryDeviceIdentity {
        guard version == 1 else { throw TokenVerificationError.malformed }
        let identity = try MemoryDeviceIdentity(privateKey: wrappedPrivateKey.open(passphrase: passphrase))
        guard identity.publicKey == publicKey else { throw TokenVerificationError.invalidKey }; return identity
    }
}
