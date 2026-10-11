import Foundation
import Testing
@testable import SermonSetLocalModel

@MainActor private final class ParallelDownloader: ModelDownloader {
    var onEvent: (@MainActor @Sendable (ModelDownloadEvent) -> Void)?
    var starts: [(LocalModelFile, UUID)] = []
    var live: Set<UUID> = []
    var isForeground = true
    func restore() { onEvent?(.restorationComplete) }
    func start(file: LocalModelFile, token: UUID, resumeData: Data?, allowCellular: Bool) {
        starts.append((file, token)); live.insert(token)
    }
    func pause() {
        let tokens = live; live.removeAll()
        for token in tokens { onEvent?(.paused(token: token, resumeData: Data("resume".utf8))) }
    }
    func cancel() { live.removeAll() }
}

@MainActor @Suite struct LocalParallelDownloadTests {
    @Test func foregroundStartsFourFilesAndAggregatesBytes() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/TestFixtures/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = ParallelDownloader()
        let files = (0..<6).map { LocalModelFile(name: "file-\($0)", sizeBytes: Int64(($0 + 1) * 10)) }
        let manager = LocalModelManager(directory: root, files: files, downloader: transport, freeSpace: { _ in .max })
        manager.start()
        #expect(transport.starts.count == 4)
        for (file, token) in transport.starts { transport.onEvent?(.progress(token: token, bytes: file.sizeBytes / 2)) }
        if case let .downloading(fraction, _) = manager.state {
            #expect(abs(fraction - 50.0 / 210.0) < 0.00001)
        } else { Issue.record("Expected byte progress") }
        manager.pause(); #expect(manager.state == .paused && transport.live.isEmpty)
        manager.start(); #expect(transport.starts.count == 8)
        manager.cancel(); #expect(transport.live.isEmpty)
    }
    @Test func outOfOrderCompletionRefillsOnlyInForegroundAndRestoresAllInboxFiles() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/TestFixtures/\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let transport = ParallelDownloader(), bytes = Data("test".utf8)
        let files = (0..<6).map { LocalModelFile(name: "file-\($0)", sizeBytes: 4) }
        let manager = LocalModelManager(directory: root, files: files, downloader: transport, freeSpace: { _ in .max })
        manager.start(); #expect(transport.starts.count == 4)
        let first = transport.starts[0].1, fourth = transport.starts[3].1
        transport.isForeground = false; transport.onEvent?(.activityChanged(isForeground: false))
        let incoming = root.appendingPathComponent("incoming-fourth"); try bytes.write(to: incoming)
        transport.onEvent?(.finished(token: fourth, url: incoming))
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("file-3").path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(transport.starts.count == 4)
        transport.isForeground = true; transport.onEvent?(.activityChanged(isForeground: true))
        for _ in 0..<100 {
            if transport.starts.count == 5 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(transport.starts.count == 5 && transport.starts.last?.0.name == "file-4")
        // Simulate termination after delegate retention, before actor delivery.
        let inbox = root.appendingPathComponent("Inbox"); try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        for (_, token) in transport.starts where token != fourth { try bytes.write(to: inbox.appendingPathComponent(token.uuidString)) }
        #expect(first != fourth)
        let restored = ParallelDownloader()
        let reopened = LocalModelManager(directory: root, files: files, downloader: restored, freeSpace: { _ in .max })
        for _ in 0..<100 {
            if restored.starts.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(restored.starts.count == 1 && restored.starts.first?.0.name == "file-5")
        let last = try #require(restored.starts.first?.1)
        let lastFile = root.appendingPathComponent("last"); try bytes.write(to: lastFile)
        restored.onEvent?(.finished(token: last, url: lastFile))
        for _ in 0..<100 {
            if reopened.isReady { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(reopened.isReady)
    }
}
