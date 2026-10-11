import Foundation
public struct CommunityShare: Decodable,Sendable { public var shareID: String; public var uploadURL: URL; public var url: URL }
extension CommunityController {
    public func createShare(sermonID: String,renderedPNG: URL,operationID: UUID = UUID()) async throws -> URL {
        try ensureIdentity()
        let scoped = renderedPNG.startAccessingSecurityScopedResource(); defer { if scoped { renderedPNG.stopAccessingSecurityScopedResource() } }
        let size = (try renderedPNG.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let handle = try FileHandle(forReadingFrom: renderedPNG); defer { try? handle.close() }
        guard size > 8, size <= 10_000_000, try handle.read(upToCount: 8) == Data([137,80,78,71,13,10,26,10]) else { throw SermonSetError(title: "Card image unavailable",message: "Choose a rendered PNG card image under 10 MB.") }
        // Existing community sermon only; caller selects a public card renderer, never a private transcript screen.
        _ = try await sermon(sermonID)
        struct Body: Encodable { var sermonID: String; var byteCount: Int; var checksumSHA256: String }
        let response: CommunityShare = try await client.send("POST","/v1/shares",body: Body(sermonID: sermonID,byteCount: size,checksumSHA256: try LocalFiles.checksum(renderedPNG)),key: operationID.uuidString)
        var request = URLRequest(url: response.uploadURL); request.httpMethod = "PUT"; request.setValue("image/png",forHTTPHeaderField: "Content-Type")
        let (_,http) = try await client.session.upload(for: request,fromFile: renderedPNG)
        guard let http = http as? HTTPURLResponse,(200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }; return response.url
    }
}
