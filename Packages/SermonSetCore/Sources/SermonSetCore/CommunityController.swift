import Foundation
import Observation
import AVFoundation

@MainActor @Observable public final class CommunityController {
    public private(set) var state: JobState = .idle
    public private(set) var isOffline = false
    public private(set) var lastError: String?
    public private(set) var account: CommunityAccount?
    public private(set) var discover: [CommunitySermon] = []
    public private(set) var churches: [CommunityChurch] = []
    public private(set) var cards: [CommunityCard] = []
    public private(set) var offers: [CommunityOffer] = []
    public private(set) var inbox: [InboxItem] = []
    public private(set) var atlas: [AtlasPlace] = []
    public private(set) var pack: CommunityPack?
    public var configuration: CommunityConfiguration { client.configuration }
    @ObservationIgnored let client: CommunityClient
    @ObservationIgnored let store: SermonStore
    @ObservationIgnored private var poller: Task<Void,Never>?
    public init(store: SermonStore,configuration: CommunityConfiguration = .fromLaunchArguments(),signer: (any DeviceRequestSigner)? = nil,session: URLSession = .shared) {
        self.store = store; client = CommunityClient(store: store,configuration: configuration,signer: signer,session: session)
        if let cache = store.document.features?.community, cache.server == configuration.audience { apply(cache) }
    }
    private func apply(_ cache: CommunityCache) { account = cache.account; discover = cache.discover; churches = cache.churches; cards = cache.cards; offers = cache.offers; inbox = cache.inbox; atlas = cache.atlas; pack = cache.pack }
    private var cache: CommunityCache { store.document.features?.community.flatMap { $0.server == configuration.audience ? $0 : nil } ?? CommunityCache(server: configuration.audience) }
    func save(_ cache: CommunityCache) throws {
        try store.transaction { if $0.features == nil { $0.features = CoreFeatures() }; $0.features?.community = cache }
        apply(cache)
    }
    func ensureIdentity() throws { if client.signer == nil { client.signer = try KeychainDeviceIdentity() } }
    public func createAccount(displayName: String? = nil,avatarStyle: String = "abstract") async throws {
        try ensureIdentity()
        struct Body: Encodable { var publicKey: ServerPublicKey; var displayName: String?; var avatarStyle: String }
        struct Response: Decodable { var account: CommunityAccount }
        let oldAccountID = client.accountID; client.accountID = nil
        let result: Response
        do { result = try await client.send("POST","/v1/accounts",body: Body(publicKey: client.signer!.publicKey,displayName: displayName,avatarStyle: avatarStyle)) } catch { client.accountID = oldAccountID; throw error }
        client.accountID = result.account.id
        var cache = cache; cache.account = result.account; try save(cache)
    }
    public func updateAccount(displayName: String?,avatarStyle: String,journeyOptIn: Bool = false,journeyCity: String? = nil,hidePastJourneys: Bool = false) async throws {
        try ensureIdentity()
        struct Body: Encodable { var displayName: String?; var avatarStyle: String; var journeyOptIn: Bool; var journeyCity: String?; var hidePastJourneys: Bool }
        let _: APIReceipt = try await client.send("PATCH","/v1/me",body: Body(displayName: displayName,avatarStyle: avatarStyle,journeyOptIn: journeyOptIn,journeyCity: journeyCity,hidePastJourneys: hidePastJourneys),key: UUID().uuidString)
        try await refreshAccount()
    }
    public func deleteAccount() async throws {
        try ensureIdentity(); let _: APIReceipt = try await client.request("DELETE","/v1/me")
        client.accountID = nil; var cache = cache; cache.account = nil; cache.cards = []; cache.offers = []; cache.inbox = []
        try store.mergeCommunity(cache); apply(cache)
    }
    public func refreshAccount() async throws {
        try ensureIdentity(); struct Response: Decodable { var account: CommunityAccount }
        let result: Response = try await client.request("GET","/v1/me")
        var cache = cache; cache.account = result.account; try save(cache); client.accountID = result.account.id
    }
    public func exportRecoveryKit(passphrase: String) throws -> URL {
        guard let account, let signer = client.signer else { throw SermonSetError(title: "Account needed",message: "Create or recover an account first.") }
        let kit = try RecoveryKit.create(server: configuration.audience,accountID: account.id,signer: signer,passphrase: passphrase)
        try LocalFiles.createDirectory(store.exportsDirectory)
        let url = store.exportsDirectory.appendingPathComponent("Recovery-\(UUID()).ssrecovery"); try LocalFiles.write(kit,to: url); return url
    }
    public func importRecoveryKit(from url: URL,passphrase: String) async throws {
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let kit = try LocalFiles.decoder.decode(RecoveryKit.self,from: Data(contentsOf: url))
        guard kit.server == configuration.audience else { throw TokenVerificationError.wrongAudience }
        let recovered = try kit.restore(passphrase: passphrase), old = client.signer, oldID = client.accountID
        client.signer = recovered; client.accountID = kit.accountID
        do {
            struct Response: Decodable { var account: CommunityAccount }
            let response: Response = try await client.request("GET","/v1/me")
            guard response.account.id == kit.accountID else { throw TokenVerificationError.invalidKey }
            // Tests use explicit memory signers; live imports persist only after server verification.
            if old == nil || old is KeychainDeviceIdentity { client.signer = try KeychainDeviceIdentity.replace(privateKey: recovered.exportPrivateKey()) }
            var cache = cache; cache.account = response.account; try save(cache)
        } catch { client.signer = old; client.accountID = oldID; throw error }
    }
    public func linkBrowser() async throws -> BrowserLinkCode { try ensureIdentity(); return try await client.send("POST","/v1/web/link-codes",body: EmptyBody(),key: UUID().uuidString) }
    public func refreshServerKeys() async throws {
        struct Response: Decodable { var keys: [ServerSigningKey] }
        let response: Response = try await client.request("GET","/v1/keys",signed: false); try store.cacheServerKeys(response.keys)
    }
    public func refreshDiscover(filters: DiscoverFilters = DiscoverFilters()) async {
        state = .running(progress: nil)
        do {
            let values: [CommunitySermon] = try await client.page("/v1/discover"+filters.encodedQuery,signed: false)
            var cache = cache; cache.discover = values; for value in values { cache.sermons[value.id] = value }; cache.fetchedAt = .now
            try store.mergeCommunity(cache); apply(cache); isOffline = false; lastError = nil; state = .done
        } catch { failed(error) }
    }
    func rememberForListening(_ sermon: CommunitySermon) throws {
        var cache = cache; cache.sermons[sermon.id] = sermon
        if !cache.history.contains(where: { $0.sermonID == sermon.id }) { cache.history.append(CommunityHistory(sermonID: sermon.id,source: "discover",firstEncounteredAt: .now)) }
        try store.mergeCommunity(cache); apply(cache)
    }
    func failed(_ error: any Error) { isOffline = error is URLError || (error as? CommunityAPIError)?.retryable == true; lastError = error.localizedDescription; state = .failed(message: error.localizedDescription) }
    public func refresh() async {
        state = .running(progress: nil)
        do {
            try ensureIdentity()
            guard client.accountID != nil else { throw SermonSetError(title: "Account needed",message: "Create or recover an account for community sync.") }
            var cache = cache
            cache.cards = try await client.page("/v1/cards")
            cache.history = try await client.page("/v1/library")
            cache.offers = try await client.page("/v1/offers")
            cache.inbox = try await client.page("/v1/inbox")
            let sermonIDs = Set(cache.history.map(\.sermonID)+cache.cards.map(\.sermonID))
            for id in sermonIDs {
                struct Response: Decodable { var sermon: CommunitySermon }
                let response: Response = try await client.request("GET","/v1/sermons/"+CommunityClient.escape(id),signed: false)
                cache.sermons[id] = response.sermon
            }
            cache.fetchedAt = .now; try store.mergeCommunity(cache); apply(cache)
            isOffline = false; lastError = nil; state = .done
        } catch { failed(error) }
    }
    public func foreground() { poller?.cancel(); poller = Task { [weak self] in
        while !Task.isCancelled {
            guard let self else { return }; if self.account != nil { await self.refresh() }
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
        }
    } }
    public func background() { poller?.cancel(); poller = nil }
    public func markInboxRead(_ id: String) async throws { let _: APIReceipt = try await client.send("POST","/v1/inbox/"+CommunityClient.escape(id)+"/read",body: EmptyBody()); await refresh() }
    public func church(_ id: String) async throws -> CommunityChurch { struct Response: Decodable { var church: CommunityChurch }; let response: Response = try await client.request("GET","/v1/churches/"+CommunityClient.escape(id),signed: false); return response.church }
    public func refreshChurches(query: String = "",verifiedOnly: Bool = false) async throws {
        let values: [CommunityChurch] = try await client.page("/v1/churches?q="+CommunityClient.escape(query)+"&verified="+(verifiedOnly ? "true" : "false"),signed: false)
        var cache = cache; cache.churches = values; try save(cache)
    }
    public func churchSermons(_ id: String) async throws -> [CommunitySermon] { try await client.page("/v1/churches/"+CommunityClient.escape(id)+"/sermons",signed: false) }
    public func sermon(_ id: String) async throws -> CommunitySermon { struct Response: Decodable { var sermon: CommunitySermon }; let response: Response = try await client.request("GET","/v1/sermons/"+CommunityClient.escape(id),signed: false); return response.sermon }
    public func keep(_ id: String,source: EncounterSource = .discover) async throws {
        try ensureIdentity(); struct Body: Encodable { var source: String }
        let _: APIReceipt = try await client.send("POST","/v1/sermons/"+CommunityClient.escape(id)+"/keep",body: Body(source: source == .shared ? "shared" : "discover"))
        await refresh()
    }
    public func audioURL(sermonID: String) async throws -> AuthorizedAudio { try ensureIdentity(); return try await client.send("POST","/v1/sermons/"+CommunityClient.escape(sermonID)+"/audio-url",body: EmptyBody(),key: UUID().uuidString) }
    public func refreshSundayPack() async {
        do { try ensureIdentity(); let pack: CommunityPack = try await client.request("GET","/v1/packs/current"); var cache = cache; cache.pack = pack
            for id in pack.sermonIDs { cache.sermons[id] = try await sermon(id) }; try save(cache); isOffline = false
        } catch { failed(error) }
    }
    public var sundayPack: SundayPack {
        guard let pack, !isOffline, !pack.fallback else { return store.currentSundayPack() }
        return SundayPack(id: pack.week,title: pack.season,sermons: pack.sermonIDs.compactMap { cache.sermons[$0].map { store.localCommunitySermon($0,server: configuration.audience) } },isDemo: false)
    }
    public func openSundayPack() async throws {
        if sundayPack.isDemo { try store.keepPack(sundayPack); return }
        guard let pack else { return }; let _: APIReceipt = try await client.send("POST","/v1/packs/"+CommunityClient.escape(pack.week)+"/open",body: EmptyBody()); await refresh()
    }
    public func refreshAtlas() async throws { struct Response: Decodable { var places: [AtlasPlace] }; let response: Response = try await client.request("GET","/v1/atlas",signed: false); var cache = cache; cache.atlas = response.places; try save(cache) }
    public func journey(cardID: String) async throws -> CardJourney { try await client.request("GET","/v1/cards/"+CommunityClient.escape(cardID)+"/journey",signed: false) }
    isolated deinit { poller?.cancel() }
}
struct EmptyBody: Codable,Sendable {}
public struct BrowserLinkCode: Decodable,Sendable { public var code: String; public var expiresAt: Date }
public struct DiscoverFilters: Hashable,Sendable {
    public var query: String; public var type: SermonType?; public var theme: String?; public var churchID: String?; public var city: String?; public var passage: String?; public var verifiedOnly: Bool
    public init(query: String = "",type: SermonType? = nil,theme: String? = nil,churchID: String? = nil,city: String? = nil,passage: String? = nil,verifiedOnly: Bool = false) { self.query = query; self.type = type; self.theme = theme; self.churchID = churchID; self.city = city; self.passage = passage; self.verifiedOnly = verifiedOnly }
    var queryString: [(String,String?)] { [("q",query.isEmpty ? nil : query),("type",type?.rawValue),("theme",theme),("churchID",churchID),("city",city),("passage",passage),("verified",verifiedOnly ? "true" : nil)] }
    var encodedQuery: String { let parts = queryString.compactMap { key,value in value.map { key+"="+CommunityClient.escape($0) } }; return parts.isEmpty ? "" : "?"+parts.joined(separator: "&") }
}
