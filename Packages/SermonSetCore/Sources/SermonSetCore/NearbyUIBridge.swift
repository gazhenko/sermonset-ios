import Foundation
import Observation
@preconcurrency import MultipeerConnectivity

@MainActor @Observable public final class NearbyExchange: NSObject {
    public enum State: Hashable,Sendable { case idle,searching,connected(peerName: String),sent,received(token: String),failed(String) }
    public private(set) var state: State = .idle
    @ObservationIgnored private let peer: MCPeerID
    @ObservationIgnored private var session: MCSession!
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser!
    @ObservationIgnored private var browser: MCNearbyServiceBrowser!
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var receiving = false
    private static let service = "sower-card"
    public init(displayName: String) {
        // Avoid broadcasting a user's account name in discovery; use a short ephemeral listener label.
        peer = MCPeerID(displayName: "Listener-"+UUID().uuidString.prefix(6)); super.init()
        session = MCSession(peer: peer,securityIdentity: nil,encryptionPreference: .required); session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: peer,discoveryInfo: nil,serviceType: Self.service); advertiser.delegate = self
        browser = MCNearbyServiceBrowser(peer: peer,serviceType: Self.service); browser.delegate = self
    }
    public func offer(token: String) {
        stop()
        guard token.utf8.count <= 16_384, token.split(separator: ".").count == 3 else { state = .failed("The offer token could not be read."); return }
        self.token = token; receiving = false; state = .searching; advertiser.startAdvertisingPeer()
    }
    public func receive() { stop(); receiving = true; state = .searching; browser.startBrowsingForPeers() }
    public func stop() { advertiser.stopAdvertisingPeer(); browser.stopBrowsingForPeers(); session.disconnect(); token = nil; receiving = false; state = .idle }
}
private struct NearbyReply: @unchecked Sendable { let call: (Bool,MCSession?) -> Void }
extension NearbyExchange: MCNearbyServiceAdvertiserDelegate,MCNearbyServiceBrowserDelegate,MCSessionDelegate {
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,didReceiveInvitationFromPeer peerID: MCPeerID,withContext context: Data?,invitationHandler: @escaping (Bool,MCSession?) -> Void) {
        let reply = NearbyReply(call: invitationHandler)
        Task { @MainActor [weak self] in guard let self, self.token != nil, self.session.connectedPeers.isEmpty else { reply.call(false,nil); return }; reply.call(true,self.session) }
    }
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser,foundPeer peerID: MCPeerID,withDiscoveryInfo info: [String:String]?) {
        Task { @MainActor [weak self] in guard let self, self.receiving, self.session.connectedPeers.isEmpty else { return }; self.browser.invitePeer(peerID,to: self.session,withContext: nil,timeout: 20); self.browser.stopBrowsingForPeers() }
    }
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser,lostPeer peerID: MCPeerID) {}
    nonisolated public func session(_ session: MCSession,peer peerID: MCPeerID,didChange state: MCSessionState) {
        Task { @MainActor [weak self] in guard let self else { return }; if state == .connected { self.state = .connected(peerName: peerID.displayName); if let token = self.token { do { try self.session.send(Data(token.utf8),toPeers: [peerID],with: .reliable); self.state = .sent; self.advertiser.stopAdvertisingPeer() } catch { self.state = .failed("The offer could not be sent. Use its QR or link.") } } } }
    }
    nonisolated public func session(_ session: MCSession,didReceive data: Data,fromPeer peerID: MCPeerID) {
        guard data.count <= 16_384, let token = String(data: data,encoding: .utf8), token.split(separator: ".").count == 3 else { return }
        Task { @MainActor [weak self] in guard let self, self.receiving else { return }; self.state = .received(token: token); self.receiving = false; self.browser.stopBrowsingForPeers() }
        // UI sends token to previewOffer, which verifies against cached keys and server before any accept.
    }
    nonisolated public func browser(_ browser: MCNearbyServiceBrowser,didNotStartBrowsingForPeers error: any Error) { Task { @MainActor [weak self] in self?.state = .failed("Nearby exchange is unavailable. Use a QR or link.") } }
    nonisolated public func advertiser(_ advertiser: MCNearbyServiceAdvertiser,didNotStartAdvertisingPeer error: any Error) { Task { @MainActor [weak self] in self?.state = .failed("Nearby exchange is unavailable. Use a QR or link.") } }
    nonisolated public func session(_ session: MCSession,didReceive stream: InputStream,withName name: String,fromPeer peerID: MCPeerID) { stream.close() }
    nonisolated public func session(_ session: MCSession,didStartReceivingResourceWithName resourceName: String,fromPeer peerID: MCPeerID,with progress: Progress) {}
    nonisolated public func session(_ session: MCSession,didFinishReceivingResourceWithName resourceName: String,fromPeer peerID: MCPeerID,at localURL: URL?,withError error: (any Error)?) {}
}
