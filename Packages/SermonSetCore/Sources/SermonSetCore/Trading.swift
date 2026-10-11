import Foundation

public enum TradeOfferKind: String,Codable,Hashable,Sendable { case gift,swap }
public struct CreatedTradeOffer: Codable,Hashable,Sendable { public var offerID: String; public var token: String }
public struct TradeOfferPreview: Decodable,Sendable { public var offer: CommunityOffer; public var card: CommunityCard; public var senderDisplayName: String? }
public enum ReportTarget: String,Codable,Sendable { case sermon,audio,card,account }
public enum ReportReason: String,Codable,Sendable { case rights,privacy,wrongAttribution,misleadingEdit,sensitiveContent,abuse }
public struct ReportReceipt: Decodable,Sendable { public var ok: Bool; public var reportID: String }
public struct BlockedAccount: Decodable,Sendable { public var accountID: String }
extension CommunityController {
    public func createOffer(cardID: String,kind: TradeOfferKind,recipientID: String? = nil,message: String? = nil,expiresAt: Date? = nil,operationID: UUID = UUID()) async throws -> CreatedTradeOffer {
        try ensureIdentity()
        guard let card = cards.first(where: { $0.id == cardID }), card.tradeable, card.ownerID == account?.id else { throw SermonSetError(title: "Card cannot be traded",message: "Only a community card currently owned by your account can be offered.") }
        struct Body: Encodable { var kind: String; var cardID: String; var cardVersion: Int; var recipientID: String?; var message: String?; var expiresAt: Date? }
        return try await client.send("POST","/v1/offers",body: Body(kind: kind.rawValue,cardID: cardID,cardVersion: card.version,recipientID: recipientID,message: message,expiresAt: expiresAt),key: operationID.uuidString)
    }
    public func previewOffer(offerID: String,token: String? = nil) async throws -> TradeOfferPreview {
        try ensureIdentity(); return try await client.request("GET","/v1/offers/"+CommunityClient.escape(offerID)+(token.map { "?token="+CommunityClient.escape($0) } ?? ""))
    }
    public func acceptOffer(_ id: String,token: String? = nil,operationID: UUID? = nil) async throws { try await offerAction(id,action: "accept",token: token,key: operationID?.uuidString) }
    public func declineOffer(_ id: String,token: String? = nil,operationID: UUID? = nil) async throws { try await offerAction(id,action: "decline",token: token,key: operationID?.uuidString) }
    public func cancelOffer(_ id: String,operationID: UUID? = nil) async throws { try await offerAction(id,action: "cancel",token: nil,key: operationID?.uuidString) }
    public func confirmOffer(_ id: String,operationID: UUID? = nil) async throws { try await offerAction(id,action: "confirm",token: nil,key: operationID?.uuidString) }
    private func offerAction(_ id: String,action: String,token: String?,key: String?) async throws {
        try ensureIdentity(); struct Body: Encodable { var token: String? }
        let _: APIReceipt = try await client.send("POST","/v1/offers/"+CommunityClient.escape(id)+"/"+action,body: Body(token: token),key: key)
        await refresh()
    }
    public func proposeSwap(_ id: String,cardID: String,token: String? = nil,operationID: UUID? = nil) async throws {
        try ensureIdentity()
        guard let card = cards.first(where: { $0.id == cardID }), card.tradeable, card.ownerID == account?.id else { throw SermonSetError(title: "Swap card unavailable",message: "Choose a community card you currently own.") }
        struct Body: Encodable { var token: String?; var cardID: String; var cardVersion: Int }
        let _: APIReceipt = try await client.send("POST","/v1/offers/"+CommunityClient.escape(id)+"/propose",body: Body(token: token,cardID: cardID,cardVersion: card.version),key: operationID?.uuidString)
        await refresh()
    }
    public func blockAccount(_ id: String) async throws { try ensureIdentity(); struct Body: Encodable { var accountID: String }; let _: APIReceipt = try await client.send("POST","/v1/blocks",body: Body(accountID: id),key: UUID().uuidString); await refresh() }
    public func unblockAccount(_ id: String) async throws { try ensureIdentity(); let _: APIReceipt = try await client.request("DELETE","/v1/blocks/"+CommunityClient.escape(id),idempotencyKey: UUID().uuidString) }
    public func blockedAccounts() async throws -> [BlockedAccount] { try ensureIdentity(); return try await client.page("/v1/blocks") }
    public func report(target: ReportTarget,targetID: String,reason: ReportReason,timestamp: Double? = nil,details: String? = nil,operationID: UUID = UUID()) async throws -> ReportReceipt {
        try ensureIdentity()
        guard timestamp == nil || (timestamp!.isFinite && timestamp! >= 0) else { throw SermonSetError(title: "Invalid report time",message: "Choose a time within the audio.") }
        struct Body: Encodable { var targetType: String; var targetID: String; var reason: String; var timestamp: Double?; var details: String? }
        return try await client.send("POST","/v1/reports",body: Body(targetType: target.rawValue,targetID: targetID,reason: reason.rawValue,timestamp: timestamp,details: details),key: operationID.uuidString)
    }
}
public enum AppIdentity {
    public static var displayName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Sower" }
    public static var urlScheme: String { Bundle.main.object(forInfoDictionaryKey: "AppURLScheme") as? String ?? "sower" }
}
public enum CommunityLink: Hashable,Sendable { case offer(token: String,grant: OfferGrant),sermon(id: String) }
public struct CommunityLinkParser: Sendable {
    public var scheme: String
    public var domain: String
    public var verifier: ServiceTokenVerifier
    public init(scheme: String = AppIdentity.urlScheme,domain: String,verifier: ServiceTokenVerifier) { self.scheme = scheme; self.domain = domain; self.verifier = verifier }
    public func parse(_ string: String,now: Date = .now) throws -> CommunityLink {
        if !string.contains("://") { return .offer(token: string,grant: try verifier.verifyOffer(string,now: now)) }
        guard let url = URL(string: string), url.user == nil, url.password == nil, url.fragment == nil, url.query == nil else { throw TokenVerificationError.malformed }
        let components = url.pathComponents.filter { $0 != "/" }
        if url.scheme == scheme, url.host == "offer", components.count == 1 { return .offer(token: components[0],grant: try verifier.verifyOffer(components[0],now: now)) }
        if url.scheme == "https", url.host == domain, url.port == nil, components.count == 2, components[0] == "t" { return .offer(token: components[1],grant: try verifier.verifyOffer(components[1],now: now)) }
        if url.scheme == scheme, url.host == "sermon", components.count == 1 { return .sermon(id: components[0]) }
        throw TokenVerificationError.malformed
    }
    public func offerURL(token: String) throws -> URL {
        _ = try verifier.verifyOffer(token)
        guard let url = URL(string: "\(scheme)://offer/\(token)") else { throw TokenVerificationError.malformed }; return url
    }
}
