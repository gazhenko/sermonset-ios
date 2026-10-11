import Foundation
import Observation
@preconcurrency import MultipeerConnectivity

private struct InvitationReply: @unchecked Sendable {
    // Framework hands this single-use callback to one MainActor task; never accessed concurrently.
    let call: (Bool, MCSession?) -> Void
}
public struct NearbyPeer: Hashable,Sendable,Identifiable { public var id: String; public var displayName: String }
@MainActor @Observable public final class NearbyExchangeController: NSObject {
    public private(set) var state: JobState = .idle
    public private(set) var peers: [NearbyPeer] = []
    public private(set) var receivedToken: String?
    public private(set) var receivedGrant: OfferGrant?
    @ObservationIgnored private let verifier: ServiceTokenVerifier
    @ObservationIgnored private let identity = MCPeerID(displayName: "Listener-"+UUID().uuidString.prefix(6))
    @ObservationIgnored private var session: MCSession!
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser!
    @ObservationIgnored private var browser: MCNearbyServiceBrowser!
    @ObservationIgnored private var known: [String:MCPeerID] = [:]
    @ObservationIgnored private var pending: [String:String] = [:]
    public static let serviceType = "sermon-card"
    public init(verifier: ServiceTokenVerifier) {
        self.verifier = verifier; super.init()
        session = MCSession(peer: identity,securityIdentity: nil,encryptionPreference: .required); session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: identity,discoveryInfo: nil,serviceType: Self.serviceType); advertiser.delegate = self
        browser = MCNearbyServiceBrowser(peer: identity,serviceType: Self.serviceType); browser.delegate = self
    }
    public func start() { state = .running(progress: nil); advertiser.startAdvertisingPeer(); browser.startBrowsingForPeers() }
    public func stop() { advertiser.stopAdvertisingPeer(); browser.stopBrowsingForPeers(); session.disconnect(); known = [:]; pending = [:]; peers = []; state = .idle }
    public func send(token: String,to peer: NearbyPeer) throws {
        _ = try verifier.verifyOffer(token)
        guard let target = known[peer.id] else { throw SermonSetError(title: "Listener unavailable",message: "Keep both nearby screens open and try again.") }
        if session.connectedPeers.contains(target) { try session.send(Data(token.utf8),toPeers: [target],with: .reliable) }
        else { pending[peer.id] = token; browser.invitePeer(target,to: session,withContext: nil,timeout: 20) }
    }
    public func clearReceived() { receivedToken = nil; receivedGrant = nil }
}
extension NearbyExchangeController: MCNearbyServiceAdvertiserDelegate,MCNearbyServiceBrowserDelegate,MCSessionDelegate {
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,didReceiveInvitationFromPeer peerID: MCPeerID,withContext context: Data?,invitationHandler: @escaping (Bool,MCSession?) -> Void) {
        // Invitation handling is synchronous; entry to start() is the user's nearby opt-in.
        let reply = InvitationReply(call: invitationHandler)
        Task { @MainActor [weak self] in guard let self, case .running = self.state else { reply.call(false,nil); return }; reply.call(true,self.session) }
    }
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,didNotStartAdvertisingPeer error: any Error) { Task { @MainActor [weak self] in self?.state = .failed(message: "Nearby exchange is unavailable. Share the offer QR or link instead.") } }
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser,foundPeer peerID: MCPeerID,withDiscoveryInfo info: [String:String]?) {
        Task { @MainActor [weak self] in guard let self else { return }; self.known[peerID.displayName] = peerID; self.peers = self.known.map { NearbyPeer(id: $0.key,displayName: $0.value.displayName) }.sorted { $0.id < $1.id } }
    }
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser,lostPeer peerID: MCPeerID) { Task { @MainActor [weak self] in self?.known[peerID.displayName] = nil; self?.peers.removeAll { $0.id == peerID.displayName } } }
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser,didNotStartBrowsingForPeers error: any Error) { Task { @MainActor [weak self] in self?.state = .failed(message: "Nearby exchange is unavailable. Share the offer QR or link instead.") } }
    nonisolated public func session(_ session: MCSession,peer peerID: MCPeerID,didChange state: MCSessionState) {
        guard state == .connected else { return }
        Task { @MainActor [weak self] in guard let self, let token = self.pending.removeValue(forKey: peerID.displayName) else { return }; do { try self.session.send(Data(token.utf8),toPeers: [peerID],with: .reliable) } catch { self.state = .failed(message: "The offer could not be sent. Try its QR or link.") } }
    }
    nonisolated public func session(_ session: MCSession,didReceive data: Data,fromPeer peerID: MCPeerID) {
        guard data.count <= 16_384, let token = String(data: data,encoding: .utf8) else { return }
        Task { @MainActor [weak self] in guard let self else { return }; do { self.receivedGrant = try self.verifier.verifyOffer(token); self.receivedToken = token } catch { self.state = .failed(message: error.localizedDescription) } }
    }
    nonisolated public func session(_ session: MCSession,didReceive stream: InputStream,withName name: String,fromPeer peerID: MCPeerID) { stream.close() }
    nonisolated public func session(_ session: MCSession,didStartReceivingResourceWithName resourceName: String,fromPeer peerID: MCPeerID,with progress: Progress) {}
    nonisolated public func session(_ session: MCSession,didFinishReceivingResourceWithName resourceName: String,fromPeer peerID: MCPeerID,at localURL: URL?,withError error: (any Error)?) {}
}
