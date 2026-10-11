import Testing
import Foundation
import CryptoKit
@testable import SermonSetCore
@Suite struct TokenTests {
    static func token(key: P256.Signing.PrivateKey,type: String = "service+jwt",expiry: Date,audience: String = "https://community.test") throws -> String {
        let header = Data("{\"alg\":\"ES256\",\"kid\":\"test\",\"typ\":\"\(type)\"}".utf8).base64URL
        let grant = ServiceGrant(v: 1,aud: audience,id: "service",church: "church",service: "Sunday",startsAt: expiry.addingTimeInterval(-3600),recordingAllowed: true,publicSharingAllowed: false,reviewRequired: true,expiresAt: expiry,exp: floor(expiry.timeIntervalSince1970))
        let payload = try LocalFiles.encoder.encode(grant).base64URL
        let input = "\(header).\(payload)"
        return input + "." + (try key.signature(for: Data(input.utf8))).rawRepresentation.base64URL
    }
    @Test func signatureExpiryAudienceAndUnknownKeys() throws {
        let key = P256.Signing.PrivateKey(), now = Date(timeIntervalSince1970: 1_700_000_000)
        let verifier = ServiceTokenVerifier(keys: [ServerSigningKey(kid: "test",publicKey: ServerPublicKey(key: key.publicKey))],audience: "https://community.test")
        let token = try Self.token(key: key,expiry: now.addingTimeInterval(3600))
        #expect(try verifier.verifyService(token,now: now).recordingAllowed)
        #expect(!(try verifier.verifyService(token,now: now).publicSharingAllowed))
        #expect(throws: TokenVerificationError.self) { try verifier.verifyService(token,now: now.addingTimeInterval(7200)) }
        #expect(throws: TokenVerificationError.self) { try verifier.verifyService(Self.token(key: P256.Signing.PrivateKey(),expiry: now.addingTimeInterval(3600)),now: now) }
        #expect(throws: TokenVerificationError.self) { try verifier.verifyService(Self.token(key: key,expiry: now.addingTimeInterval(3600),audience: "other"),now: now) }
        #expect(throws: TokenVerificationError.self) { try verifier.verifyOffer(token,now: now) }
        #expect(throws: TokenVerificationError.self) { try ServiceTokenVerifier(keys: [],audience: "https://community.test").verifyService(token,now: now) }
    }

    @Test func verifiedOfferLinksRejectForeignURLs() throws {
        let key = P256.Signing.PrivateKey(), now = Date(timeIntervalSince1970: 1700000000)
        let header = Data("{\"alg\":\"ES256\",\"kid\":\"test\",\"typ\":\"offer+jwt\"}".utf8).base64URL
        let grant = OfferGrant(v: 1,aud: "https://community.test",offerID: "offer",cardID: "card",senderID: "sender",exp: now.timeIntervalSince1970+3600)
        let payload = try APIJSON.encoder.encode(grant).base64URL, input = header+"."+payload
        let token = input+"."+(try key.signature(for: Data(input.utf8))).rawRepresentation.base64URL
        let verifier = ServiceTokenVerifier(keys: [ServerSigningKey(kid: "test",publicKey: ServerPublicKey(key: key.publicKey))],audience: "https://community.test")
        let parser = CommunityLinkParser(scheme: "sower",domain: "community.test",verifier: verifier)
        #expect(try parser.parse("sower://offer/"+token,now: now) == .offer(token: token,grant: grant))
        #expect(try parser.parse("https://community.test/t/"+token,now: now) == .offer(token: token,grant: grant))
        #expect(try parser.parse(token,now: now) == .offer(token: token,grant: grant))
        #expect(throws: TokenVerificationError.self) { try parser.parse("https://other.test/t/"+token,now: now) }
        #expect(throws: TokenVerificationError.self) { try parser.parse("sower://offer/"+token+"?extra=1",now: now) }
        #expect(throws: TokenVerificationError.self) { try parser.parse(token,now: now.addingTimeInterval(7200)) }
    }
}
