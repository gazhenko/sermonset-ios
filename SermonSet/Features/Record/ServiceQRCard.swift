import SermonSetCore
import SwiftUI

/// A church's printed service code: it says whether recording and sharing are welcome. Verified on
/// this iPhone against the church's signing key, so it works without a connection once keys are cached.
struct ServiceQRCard: View {
    @Environment(\.look) private var look
    @Environment(SermonStore.self) private var store
    @Environment(CommunityController.self) private var community
    @Binding var verified: VerifiedService?
    @State private var scanning = false

    var body: some View {
        Group {
            if let verified {
                grantPanel(verified)
            } else {
                Button { scanning = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.title2)
                            .foregroundStyle(look.palette.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scan the service QR code")
                                .font(look.type.headline)
                                .foregroundStyle(look.palette.ink)
                            Text("If your church printed one, it tells you whether recording and sharing are welcome.")
                                .font(look.type.caption)
                                .foregroundStyle(look.palette.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(look.palette.inkTertiary)
                    }
                }
                .buttonStyle(.plain)
                .lookPanel(padding: 14)
                .accessibilityIdentifier("record.scanService")
            }
        }
        .sheet(isPresented: $scanning) {
            QRScanSheet(title: "Service QR code", hint: "Point the camera at the code your church printed in the bulletin or on a screen.") { code in
                await verify(code)
            }
            .lookScoped(look)
        }
    }

    private func grantPanel(_ service: VerifiedService) -> some View {
        let grant = service.grant
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Service code checked", systemImage: "checkmark.seal.fill")
                    .font(look.type.headline)
                    .foregroundStyle(look.palette.positive)
                Spacer()
                Button("Remove") { verified = nil }
                    .font(look.type.callout)
                    .foregroundStyle(look.palette.accent)
                    .accessibilityLabel("Remove service code")
            }
            Text(service.churchName.map { "\(grant.service) at \($0)" } ?? grant.service)
                .font(look.type.body)
                .foregroundStyle(look.palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(grant.startsAt.formatted(date: .abbreviated, time: .shortened))
                .font(look.type.caption)
                .foregroundStyle(look.palette.inkSecondary)
            VStack(alignment: .leading, spacing: 6) {
                permission(grant.recordingAllowed, yes: "Recording is welcome", no: "The church asks that this service not be recorded")
                permission(grant.publicSharingAllowed, yes: grant.reviewRequired ? "Sharing is welcome after the church reviews it" : "Sharing is welcome", no: "Recordings from this service stay private")
            }
        }
        .lookPanel(padding: 14)
        .accessibilityElement(children: .contain)
    }

    private func permission(_ allowed: Bool, yes: String, no: String) -> some View {
        Label(allowed ? yes : no, systemImage: allowed ? "checkmark.circle" : "xmark.circle")
            .font(look.type.callout)
            .foregroundStyle(allowed ? look.palette.ink : look.palette.record)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func verify(_ code: String) async -> String? {
        let token = QRDecoder.token(from: code)
        let audience = community.configuration.audience
        func attempt() throws -> ServiceGrant { try store.verifyServiceToken(token, audience: audience) }
        do {
            let grant: ServiceGrant
            do {
                grant = try attempt()
            } catch TokenVerificationError.unknownKey, TokenVerificationError.invalidKey {
                // A new church key: fetch the current keys once, then check again.
                try await community.refreshServerKeys()
                grant = try attempt()
            }
            let name = community.churches.first { $0.id == grant.church }?.name
            verified = VerifiedService(token: token, grant: grant, churchName: name)
            if name == nil, let church = try? await community.church(grant.church) {
                verified = VerifiedService(token: token, grant: grant, churchName: church.name)
            }
            return nil
        } catch TokenVerificationError.wrongType {
            return "That’s a card code, not a service code. Open it from Collection to receive the card."
        } catch let error as TokenVerificationError {
            return error.localizedDescription
        } catch {
            return "Couldn’t check this code. Connect to the internet once so \(AppBrand.name) can fetch the church’s key, then try again."
        }
    }
}

struct VerifiedService: Equatable {
    var token: String
    var grant: ServiceGrant
    var churchName: String?
}
