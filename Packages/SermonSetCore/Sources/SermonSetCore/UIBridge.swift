import Foundation
public struct OfferTicket: Sendable { public var offerID: String; public var token: String; public var shareURL: URL; public var appURL: URL }
public struct OfferPreview: Sendable { public var offer: CommunityOffer; public var card: CommunityCard; public var sermon: CommunitySermon; public var senderDisplayName: String? }
extension CommunityController {
    public func sendReport(targetType: String,targetID: String,reason: String,timestamp: Double?,details: String?) async throws {
        guard let target = ReportTarget(rawValue: targetType), let reason = ReportReason(rawValue: reason) else { throw SermonSetError(title: "Report needs review",message: "Choose a supported report reason and target.") }
        _ = try await report(target: target,targetID: targetID,reason: reason,timestamp: timestamp,details: details)
    }
    public func createOffer(cardID: String,kind: String,message: String?,recipientID: String?,operationID: UUID? = nil) async throws -> OfferTicket {
        guard let kind = TradeOfferKind(rawValue: kind) else { throw TokenVerificationError.malformed }
        let version = cards.first { $0.id == cardID }?.version ?? 0
        let key = operationID ?? LocalFiles.stableUUID("offer:\(configuration.audience):\(account?.id ?? ""):\(cardID):\(version):\(kind.rawValue):\(recipientID ?? ""):\(message ?? "")")
        let offer = try await createOffer(cardID: cardID,kind: kind,recipientID: recipientID,message: message,operationID: key)
        guard let share = URL(string: configuration.audience+"/t/"+CommunityClient.escape(offer.token)), let app = URL(string: AppIdentity.urlScheme+"://offer/"+offer.token) else { throw TokenVerificationError.malformed }
        return OfferTicket(offerID: offer.offerID,token: offer.token,shareURL: share,appURL: app)
    }
    public func previewOffer(id: String?,token: String) async throws -> OfferPreview {
        let grant = try ServiceTokenVerifier(keys: store.cachedServerKeys,audience: configuration.audience).verifyOffer(token)
        guard id == nil || id == grant.offerID else { throw TokenVerificationError.malformed }
        let preview = try await previewOffer(offerID: grant.offerID,token: token)
        return OfferPreview(offer: preview.offer,card: preview.card,sermon: try await sermon(preview.card.sermonID),senderDisplayName: preview.senderDisplayName)
    }
    public func proposeSwap(_ id: String,token: String?,cardID: String) async throws { try await proposeSwap(id,cardID: cardID,token: token) }
    public func confirmSwap(_ id: String) async throws { try await confirmOffer(id) }
    public func block(accountID: String) async throws { try await blockAccount(accountID); try await refreshBlocks() }
    public func unblock(accountID: String) async throws { try await unblockAccount(accountID); try await refreshBlocks() }
    public var blockedAccountIDs: [String] { store.document.features?.blockedAccountIDs ?? [] }
    public func refreshBlocks() async throws {
        let ids = try await blockedAccounts().map(\.accountID)
        try store.transaction { if $0.features == nil { $0.features = CoreFeatures() }; $0.features?.blockedAccountIDs = ids }
    }
    public func tradeHistory(for cardID: String) -> [CommunityOffer] { offers.filter { $0.cardID == cardID || $0.proposedCardID == cardID }.sorted { $0.createdAt < $1.createdAt } }
    public func communityCard(forLocalCard id: UUID) -> CommunityCard? { cards.first { store.localCommunityID($0.id,server: configuration.audience) == id } }
    public func createShareLink(sermonID: String,cardImagePNG: Data) async throws -> URL {
        try LocalFiles.createDirectory(store.exportsDirectory)
        let file = store.exportsDirectory.appendingPathComponent("Share-\(UUID()).png")
        try cardImagePNG.write(to: file,options: .atomic); try LocalFiles.protect(file); defer { try? FileManager.default.removeItem(at: file) }
        return try await createShare(sermonID: sermonID,renderedPNG: file)
    }
}
