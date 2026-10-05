import Foundation

struct CaptureSegment: Codable, Hashable, Sendable {
    var filename: String
    var duration: TimeInterval
    var checksumSHA256: String
}
struct CaptureManifest: Codable, Sendable {
    var schemaVersion = 1
    var id = UUID()
    var sermonID = UUID()
    var audioAssetID = UUID()
    var startedAt = Date.now
    var draft: CaptureDraft
    var segments: [CaptureSegment] = []
    var moments: [MarkedMoment] = []
    var notes: [PersonalNote] = []
    var events: [String] = []
    var dismissed = false
    var completed = false
    var duration: TimeInterval { segments.reduce(0) { $0 + $1.duration } }
}

/// The manifest may be checkpointed by the serial audio writer and the main actor.
/// Every read/update is locked; audio-framework objects stay in the writer's queue.
final class CaptureJournal: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private var value: CaptureManifest
    var url: URL { directory.appendingPathComponent("manifest.json") }
    var manifest: CaptureManifest { lock.withLock { value } }

    init(directory: URL, manifest: CaptureManifest) throws {
        self.directory = directory; self.value = manifest
        try LocalFiles.createDirectory(directory)
        try LocalFiles.write(manifest, to: directory.appendingPathComponent("manifest.json"))
    }
    private init(directory: URL, loaded: CaptureManifest) { self.directory = directory; self.value = loaded }
    static func load(_ directory: URL) throws -> CaptureJournal {
        let manifest = try LocalFiles.decoder.decode(CaptureManifest.self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json")))
        guard manifest.schemaVersion == 1, manifest.segments.allSatisfy({ $0.filename == URL(fileURLWithPath: $0.filename).lastPathComponent && !$0.filename.contains("..") && $0.duration.isFinite && $0.duration > 0 }), Set(manifest.segments.map(\.filename)).count == manifest.segments.count else { throw SermonSetError(title: "Recovery manifest unavailable", message: "A recording manifest could not be read. All session files have been preserved.") }
        return CaptureJournal(directory: directory, loaded: manifest)
    }
    func update(_ mutate: (inout CaptureManifest) -> Void) throws {
        try lock.withLock {
            var next = value
            mutate(&next)
            try LocalFiles.write(next, to: url)
            value = next
        }
    }
}
