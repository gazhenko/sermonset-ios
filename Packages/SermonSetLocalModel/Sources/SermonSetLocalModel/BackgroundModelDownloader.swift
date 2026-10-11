import Foundation
import SermonSetCore

typealias ModelDownloadEvent = ModelTransferEvent

@MainActor protocol ModelDownloader: AnyObject {
    var onEvent: (@MainActor @Sendable (ModelDownloadEvent) -> Void)? { get set }
    var isForeground: Bool { get }
    func restore()
    func start(file: LocalModelFile, token: UUID, resumeData: Data?, allowCellular: Bool)
    func pause()
    func cancel()
    func discard(token: UUID)
}
extension ModelDownloader {
    var isForeground: Bool { true }
    func discard(token: UUID) {}
}

@MainActor final class BackgroundModelDownloader: ModelDownloader {
    private let transport: ModelDownloadTransport
    var onEvent: (@MainActor @Sendable (ModelDownloadEvent) -> Void)? {
        get { transport.onEvent }
        set { transport.onEvent = newValue }
    }
    var isForeground: Bool { transport.isForeground }
    var backgroundCompletion: (@MainActor @Sendable () -> Void)? {
        get { transport.backgroundCompletion }
        set { transport.backgroundCompletion = newValue }
    }
    init(directory: URL, identifier: String) { transport = ModelDownloadTransport(directory: directory, identifier: identifier) }
    isolated deinit { transport.invalidate() }
    func restore() { transport.restore() }
    func start(file: LocalModelFile, token: UUID, resumeData: Data?, allowCellular: Bool) {
        transport.start(name: file.name, url: LocalModelConfiguration.downloadURL(file), token: token, resumeData: resumeData, allowCellular: allowCellular)
    }
    func pause() { transport.pause() }
    func cancel() { transport.cancel() }
    func discard(token: UUID) { transport.discard(token: token) }
}
