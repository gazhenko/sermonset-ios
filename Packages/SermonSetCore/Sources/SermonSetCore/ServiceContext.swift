import Foundation
extension SermonStore {
    public func serviceToken(for sermonID: UUID) -> String? { document.features?.serviceTokens?[sermonID] }
    public func setServiceToken(_ token: String?,for sermonID: UUID) throws {
        _ = try requireSermon(sermonID)
        guard token == nil || token!.utf8.count <= 16_384 else { throw TokenVerificationError.malformed }
        try transaction { if $0.features == nil { $0.features = CoreFeatures() }; if $0.features?.serviceTokens == nil { $0.features?.serviceTokens = [:] }; $0.features?.serviceTokens?[sermonID] = token }
    }
}
