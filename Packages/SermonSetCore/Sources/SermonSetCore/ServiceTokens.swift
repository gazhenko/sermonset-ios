import Foundation
import CryptoKit

public struct ServerPublicKey: Codable, Hashable, Sendable {
    public var kty: String = "EC"
    public var crv: String = "P-256"
    public var x: String
    public var y: String
    public init(x: String,y: String) { self.x = x; self.y = y }
    public init(key: P256.Signing.PublicKey) {
        let bytes = key.x963Representation
        x = Data(bytes[1..<33]).base64URL; y = Data(bytes[33..<65]).base64URL
    }
    public func cryptoKey() throws -> P256.Signing.PublicKey {
        guard kty == "EC", crv == "P-256", let a = Data(base64URL: x), let b = Data(base64URL: y), a.count == 32, b.count == 32 else { throw TokenVerificationError.invalidKey }
        return try P256.Signing.PublicKey(x963Representation: Data([4])+a+b)
    }
}
public struct ServerSigningKey: Codable, Hashable, Sendable {
    public var kid: String
    public var alg: String
    public var publicKey: ServerPublicKey
    public init(kid: String,alg: String = "ES256",publicKey: ServerPublicKey) { self.kid = kid; self.alg = alg; self.publicKey = publicKey }
}
public struct ServiceGrant: Codable, Hashable, Sendable {
    public var v: Int
    public var aud: String
    public var id: String
    public var church: String
    public var service: String
    public var startsAt: Date
    public var recordingAllowed: Bool
    public var publicSharingAllowed: Bool
    public var reviewRequired: Bool
    public var expiresAt: Date
    public var exp: Double
}
public struct OfferGrant: Codable, Hashable, Sendable {
    public var v: Int
    public var aud: String
    public var offerID: String
    public var cardID: String
    public var senderID: String
    public var exp: Double
}
public enum TokenVerificationError: Error, LocalizedError, Sendable {
    case malformed, invalidKey, unknownKey, invalidSignature, wrongAudience, expired, wrongType
    public var errorDescription: String? {
        switch self {
        case .malformed: "This QR token could not be read."
        case .invalidKey, .unknownKey: "Refresh server keys online before verifying this QR token."
        case .invalidSignature: "This QR token has an invalid signature."
        case .wrongAudience: "This QR token belongs to another community server."
        case .expired: "This QR token has expired."
        case .wrongType: "This is a different kind of QR token."
        }
    }
}
extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+",with: "-").replacingOccurrences(of: "/",with: "_").replacingOccurrences(of: "=",with: "") }
    init?(base64URL: String) {
        guard !base64URL.isEmpty, base64URL.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }), base64URL.count%4 != 1 else { return nil }
        let padded = base64URL.replacingOccurrences(of: "-",with: "+").replacingOccurrences(of: "_",with: "/") + String(repeating: "=",count: (4-base64URL.count%4)%4)
        self.init(base64Encoded: padded)
        guard self.base64URL == base64URL else { return nil }
    }
    var sha256Hex: String { SHA256.hash(data: self).map { String(format: "%02x",$0) }.joined() }
}
public struct ServiceTokenVerifier: Sendable {
    public var keys: [ServerSigningKey]
    public var audience: String
    public init(keys: [ServerSigningKey],audience: String) { self.keys = keys; self.audience = audience }
    struct Header: Decodable { var alg: String; var kid: String; var typ: String }
    private func payload(_ token: String,type: String) throws -> Data {
        guard token.utf8.count <= 16_384 else { throw TokenVerificationError.malformed }
        let parts = token.split(separator: ".",omittingEmptySubsequences: false)
        guard parts.count == 3, let headerData = Data(base64URL: String(parts[0])), let payload = Data(base64URL: String(parts[1])), let signature = Data(base64URL: String(parts[2])), signature.count == 64, let header = try? JSONDecoder().decode(Header.self,from: headerData), header.alg == "ES256" else { throw TokenVerificationError.malformed }
        guard header.typ == type else { throw TokenVerificationError.wrongType }
        guard let key = keys.first(where: { $0.kid == header.kid && $0.alg == "ES256" }) else { throw TokenVerificationError.unknownKey }
        let valid = try key.publicKey.cryptoKey().isValidSignature(P256.Signing.ECDSASignature(rawRepresentation: signature),for: Data("\(parts[0]).\(parts[1])".utf8))
        guard valid else { throw TokenVerificationError.invalidSignature }; return payload
    }
    public func verifyService(_ token: String,now: Date = .now) throws -> ServiceGrant {
        let grant = try LocalFiles.decoder.decode(ServiceGrant.self,from: payload(token,type: "service+jwt"))
        guard grant.v == 1, grant.aud == audience else { throw TokenVerificationError.wrongAudience }
        guard grant.exp.isFinite, grant.exp > now.timeIntervalSince1970, grant.expiresAt > now, abs(grant.expiresAt.timeIntervalSince1970-grant.exp) < 1, grant.expiresAt > grant.startsAt else { throw TokenVerificationError.expired }
        return grant
    }
    public func verifyOffer(_ token: String,now: Date = .now) throws -> OfferGrant {
        let grant = try LocalFiles.decoder.decode(OfferGrant.self,from: payload(token,type: "offer+jwt"))
        guard grant.v == 1, grant.aud == audience else { throw TokenVerificationError.wrongAudience }
        guard grant.exp.isFinite, grant.exp > now.timeIntervalSince1970 else { throw TokenVerificationError.expired }; return grant
    }
}
extension SermonStore {
    public var cachedServerKeys: [ServerSigningKey] { document.features?.serverKeys ?? [] }
    public func cacheServerKeys(_ keys: [ServerSigningKey]) throws {
        guard Set(keys.map(\.kid)).count == keys.count else { throw TokenVerificationError.invalidKey }
        for key in keys { guard key.alg == "ES256" else { throw TokenVerificationError.invalidKey }; _ = try key.publicKey.cryptoKey() }
        try transaction { if $0.features == nil { $0.features = CoreFeatures() }; $0.features?.serverKeys = keys }
    }
    public func verifyServiceToken(_ token: String,audience: String,now: Date = .now) throws -> ServiceGrant { try ServiceTokenVerifier(keys: cachedServerKeys,audience: audience).verifyService(token,now: now) }
}
