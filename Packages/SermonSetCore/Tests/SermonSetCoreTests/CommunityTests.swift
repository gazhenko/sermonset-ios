import Testing
import Foundation
import CryptoKit
@testable import SermonSetCore
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int,Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do { let (status,data) = try Self.handler!(request)
            client?.urlProtocol(self,didReceive: HTTPURLResponse(url: request.url!,statusCode: status,httpVersion: "HTTP/1.1",headerFields: ["API-Version":"1"])!,cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self,didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError: error) }
    }
    override func stopLoading() {}
    static func session() -> URLSession { let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [StubProtocol.self]; return URLSession(configuration: c) }
}
@Suite(.serialized) @MainActor struct CommunityTests {
    @Test func signingExactBytesAndRecovery() throws {
        let identity = MemoryDeviceIdentity()
        var request = URLRequest(url: URL(string: "https://community.test/v1/offers?q=a%20b&limit=5")!)
        request.httpMethod = "POST"; request.httpBody = Data("{}".utf8)
        try SignedRequest.authorize(&request,signer: identity,accountID: "account",now: Date(timeIntervalSince1970: 1700000000),nonce: "nonce")
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: Data(base64URL: request.value(forHTTPHeaderField: "X-Signature")!)!)
        let canonical = SignedRequest.canonical(method: "POST",path: "/v1/offers?q=a%20b&limit=5",accountID: "account",timestamp: 1700000000,nonce: "nonce",body: Data("{}".utf8))
        #expect(try identity.publicKey.cryptoKey().isValidSignature(signature,for: canonical))
        #expect(!(try identity.publicKey.cryptoKey().isValidSignature(signature,for: canonical+Data([0]))))
        let kit = try RecoveryKit.create(server: "https://community.test",accountID: "account",signer: identity,passphrase: "passphrase")
        #expect(try kit.restore(passphrase: "passphrase").publicKey == identity.publicKey)
        #expect(throws: SermonSetError.self) { try kit.restore(passphrase: "wrong") }
    }
    @Test func offlineCacheAndNoPrivatePayload() async throws {
        let store = SermonStore(configuration: .preview)
        let marker = "SECRET-NOTE-CONTENT"
        _ = try store.addNote(sermonID: store.libraryEntries[0].id,text: marker,time: 1)
        StubProtocol.handler = { request in
            let body = request.httpBody ?? Data()
            #expect(!String(decoding: body,as: UTF8.self).contains("SECRET-NOTE-CONTENT"))
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") != nil)
            return (200,Data("{\"account\":{\"id\":\"a\",\"displayName\":null,\"avatarStyle\":\"abstract\",\"journeyOptIn\":false,\"journeyCity\":null,\"roles\":[]}}".utf8))
        }
        let controller = CommunityController(store: store,configuration: CommunityConfiguration(baseURL: URL(string: "https://community.test")!),signer: MemoryDeviceIdentity(),session: StubProtocol.session())
        try await controller.createAccount()
        #expect(controller.account?.id == "a")
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await controller.refresh()
        #expect(controller.isOffline)
        #expect(controller.account?.id == "a")
        #expect(store.notes(for: store.libraryEntries[0].id).contains { $0.text == marker })
    }
    @Test func mergeMovesCardsAndKeepsPrivateHistory() throws {
        let store = SermonStore(configuration: .preview)
        let remote = CommunitySermon(id: "remote",churchID: nil,title: "Public",preacher: "Speaker",service: nil,serviceDate: .now,primaryPassage: "John 1",themes: [],sermonType: "hope",city: "City",region: nil,country: nil,summary: nil,reflectionPrompt: nil,state: "published",trustLabels: ["Community matched"],audioAvailable: false,canonicalAudioAssetID: nil,fictional: false,createdAt: .now)
        let account = CommunityAccount(id: "a",displayName: nil,avatarStyle: "abstract",journeyOptIn: false,journeyCity: nil,roles: [])
        let card = CommunityCard(id: "c",sermonID: "remote",editionID: "e",edition: "Community",serialNumber: 1,ownerID: "a",version: 1,tradeable: true,createdAt: .now)
        var cache = CommunityCache(server: "https://community.test",account: account,sermons: ["remote":remote],cards: [card],history: [CommunityHistory(sermonID: "remote",source: "discover",firstEncounteredAt: .now)])
        try store.mergeCommunity(cache)
        let id = store.localCommunityID("remote",server: cache.server)
        let note = try store.addNote(sermonID: id,text: "private",time: nil)
        #expect(store.entry(for: id)?.ownsCard == true)
        cache.cards = []; try store.mergeCommunity(cache)
        #expect(store.entry(for: id)?.ownsCard == false)
        #expect(store.notes(for: id).map(\.id) == [note.id])
        #expect(store.isInLibrary(id))
        try store.mergeCommunity(cache); try store.document.validate()
    }
}
