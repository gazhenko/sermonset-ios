import Foundation
import Testing
@testable import SermonSetCore

@MainActor @Suite struct ModelDownloadTransportTests {
    @Test func outstandingForegroundTasksMigrateAndPauseWithoutNetwork() async throws {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/TestFixtures/\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = ModelDownloadTransport(directory: directory, identifier: "com.gazhenko.sower.test.\(UUID())", startsTransfers: false)
        defer { transport.invalidate() }
        transport.setForeground(true)
        let tokens = (0..<4).map { _ in UUID() }
        var pauses: Set<UUID> = [], failures = 0, activity: [Bool] = []
        transport.onEvent = { event in
            switch event {
            case .paused(let token, _): pauses.insert(token)
            case .failed: failures += 1
            case .activityChanged(let foreground): activity.append(foreground)
            default: break
            }
        }
        for (index, token) in tokens.enumerated() {
            transport.start(name: "file-\(index)", url: URL(string: "https://example.invalid/file-\(index)")!, token: token, resumeData: nil, allowCellular: false)
        }
        #expect(transport.taskSnapshots.count == 4 && transport.backgroundPlacements.values.allSatisfy { !$0 })
        #expect(transport.taskSnapshots.values.allSatisfy { $0.state == .suspended && $0.originalRequest?.allowsCellularAccess == false && $0.originalRequest?.allowsExpensiveNetworkAccess == false })
        transport.setForeground(false)
        for _ in 0..<100 {
            if transport.taskSnapshots.count == 4 && transport.backgroundPlacements.values.allSatisfy({ $0 }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(transport.taskSnapshots.count == 4 && transport.backgroundPlacements.values.allSatisfy { $0 })
        transport.setForeground(true)
        for _ in 0..<100 {
            if transport.taskSnapshots.count == 4 && transport.backgroundPlacements.values.allSatisfy({ !$0 }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(transport.taskSnapshots.count == 4 && transport.backgroundPlacements.values.allSatisfy { !$0 })
        #expect(activity == [false, true])
        transport.pause()
        for _ in 0..<100 {
            if pauses.count == 4 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(pauses == Set(tokens) && failures == 0 && transport.taskSnapshots.isEmpty)
    }
}
