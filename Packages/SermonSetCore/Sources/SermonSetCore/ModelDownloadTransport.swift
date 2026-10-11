import Foundation
#if os(iOS)
import UIKit
#endif

/// Public model bytes only. Shared by the optional speech and notes packages.
public enum ModelTransferEvent: Sendable {
    case restorationComplete
    case restored(name: String, token: UUID)
    case activityChanged(isForeground: Bool)
    case progress(token: UUID, bytes: Int64)
    case finished(token: UUID, url: URL)
    case paused(token: UUID, resumeData: Data?)
    case failed(token: UUID, message: String, resumeData: Data?)
}

/// Foreground transfers use a normal session; only outstanding transfers migrate
/// to the background session. Stable tokens survive session/task replacements.
@MainActor public final class ModelDownloadTransport: NSObject, URLSessionDownloadDelegate {
    public var onEvent: (@MainActor @Sendable (ModelTransferEvent) -> Void)?
    public var backgroundCompletion: (@MainActor @Sendable () -> Void)?
    public private(set) var isForeground = true
    nonisolated private let inbox: URL
    private var foregroundSession: URLSession!
    private var backgroundSession: URLSession!
    private let startsTransfers: Bool
    var taskSnapshots: [UUID: URLSessionDownloadTask] { transfers.compactMapValues(\.task) }
    var backgroundPlacements: [UUID: Bool] { transfers.mapValues(\.background) }
    private struct Transfer {
        var name: String
        var request: URLRequest
        var task: URLSessionDownloadTask?
        var generation: UUID
        var background: Bool
    }
    private var transfers: [UUID: Transfer] = [:]
    private var observers: [any NSObjectProtocol] = []
    #if os(iOS)
    private var handoffTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    public convenience init(directory: URL, identifier: String) {
        self.init(directory: directory, identifier: identifier, startsTransfers: true)
    }
    init(directory: URL, identifier: String, startsTransfers: Bool) {
        inbox = directory.appendingPathComponent("Inbox", isDirectory: true)
        self.startsTransfers = startsTransfers
        super.init()
        let foreground = URLSessionConfiguration.default
        foreground.httpMaximumConnectionsPerHost = 4
        foreground.waitsForConnectivity = true
        foreground.timeoutIntervalForResource = 7 * 24 * 60 * 60
        foregroundSession = URLSession(configuration: foreground, delegate: self, delegateQueue: nil)
        #if os(iOS)
        let background: URLSessionConfiguration
        if startsTransfers {
            background = URLSessionConfiguration.background(withIdentifier: identifier)
            background.sessionSendsLaunchEvents = true
            background.isDiscretionary = false
            isForeground = UIApplication.shared.applicationState != .background
            observeActivity()
        } else {
            // Unit tests exercise cancellation/handoff with suspended tasks,
            // without depending on the test host's nsurlsessiond entitlement.
            background = URLSessionConfiguration.default
        }
        #else
        let background = URLSessionConfiguration.default
        #endif
        background.waitsForConnectivity = true
        background.timeoutIntervalForResource = 7 * 24 * 60 * 60
        backgroundSession = URLSession(configuration: background, delegate: self, delegateQueue: nil)
    }

    #if os(iOS)
    private func observeActivity() {
        observers = [
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.setForeground(false) }
            },
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.setForeground(true) }
            }
        ]
    }
    #endif

    public func restore() {
        backgroundSession.getAllTasks { [weak self] tasks in
            let downloads = tasks.compactMap { $0 as? URLSessionDownloadTask }
            Task { @MainActor [weak self] in
                guard let self else { return }
                for task in downloads {
                    guard let identity = Self.parse(task.taskDescription), let request = task.originalRequest,
                          self.transfers[identity.token] == nil else { task.cancel(); continue }
                    self.transfers[identity.token] = Transfer(name: identity.name, request: request, task: task, generation: identity.generation, background: true)
                    self.onEvent?(.restored(name: identity.name, token: identity.token))
                }
                self.onEvent?(.restorationComplete)
                if self.isForeground { self.migrateOutstanding() }
            }
        }
    }

    public func start(name: String, url: URL, token: UUID, resumeData: Data?, allowCellular: Bool) {
        var request = URLRequest(url: url)
        request.allowsCellularAccess = allowCellular
        request.allowsExpensiveNetworkAccess = allowCellular
        transfers[token] = Transfer(name: name, request: request, generation: UUID(), background: !isForeground)
        launch(token, resumeData: resumeData)
    }

    private func launch(_ token: UUID, resumeData: Data?) {
        guard var transfer = transfers[token] else { return }
        transfer.background = !isForeground
        let session = isForeground ? foregroundSession! : backgroundSession!
        let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: transfer.request)
        task.taskDescription = "\(transfer.name)|\(token)|\(transfer.generation)"
        transfer.task = task; transfers[token] = transfer
        if startsTransfers { task.resume() }
    }

    /// Also used by deterministic lifecycle tests; app notifications call this.
    public func setForeground(_ value: Bool) {
        guard value != isForeground else { return }
        isForeground = value
        migrateOutstanding()
        onEvent?(.activityChanged(isForeground: value))
    }

    private func migrateOutstanding() {
        #if os(iOS)
        if startsTransfers, !isForeground, !transfers.isEmpty, handoffTask == .invalid {
            handoffTask = UIApplication.shared.beginBackgroundTask(withName: "Model download handoff") { [weak self] in
                Task { @MainActor [weak self] in self?.endHandoff() }
            }
        }
        #endif
        for (token, var transfer) in transfers where transfer.background == isForeground {
            guard let task = transfer.task else { continue }
            // Ignore late delegates from the cancelled task, including its file.
            transfer.generation = UUID(); transfer.task = nil
            transfers[token] = transfer
            let generation = transfer.generation
            task.cancel { [weak self] data in
                Task { @MainActor [weak self] in
                    guard let self, self.transfers[token]?.generation == generation else { return }
                    self.onEvent?(.progress(token: token, bytes: 0))
                    self.launch(token, resumeData: data)
                    self.finishHandoffIfPossible()
                }
            }
        }
        finishHandoffIfPossible()
    }

    public func pause() {
        let pending = transfers; transfers.removeAll()
        for (token, transfer) in pending {
            guard let task = transfer.task else {
                onEvent?(.paused(token: token, resumeData: nil)); continue
            }
            task.cancel { [weak self] data in
                Task { @MainActor [weak self] in self?.onEvent?(.paused(token: token, resumeData: data)) }
            }
        }
        finishHandoffIfPossible()
    }
    public func cancel() {
        let pending = transfers; transfers.removeAll()
        pending.values.forEach { $0.task?.cancel() }
        finishHandoffIfPossible()
    }
    public func discard(token: UUID) {
        transfers.removeValue(forKey: token)?.task?.cancel()
        finishHandoffIfPossible()
    }
    public func invalidate() {
        cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        foregroundSession.invalidateAndCancel()
        backgroundSession.invalidateAndCancel()
    }
    private func finishHandoffIfPossible() {
        #if os(iOS)
        if transfers.values.allSatisfy({ $0.task != nil }) { endHandoff() }
        #endif
    }
    #if os(iOS)
    private func endHandoff() {
        guard handoffTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(handoffTask); handoffTask = .invalid
    }
    #endif

    nonisolated private static func parse(_ description: String?) -> (name: String, token: UUID, generation: UUID)? {
        let parts = (description ?? "").split(separator: "|")
        guard parts.count >= 2, let token = UUID(uuidString: String(parts[1])) else { return nil }
        // Read the pre-parallel downloader's durable task descriptions as well.
        let generation = parts.count == 3 ? UUID(uuidString: String(parts[2])) ?? token : token
        return (String(parts[0]), token, generation)
    }
    private func accepts(_ token: UUID, generation: UUID) -> Bool { transfers[token]?.generation == generation }

    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let identity = Self.parse(downloadTask.taskDescription) else { return }
        Task { @MainActor [weak self] in
            guard let self, self.accepts(identity.token, generation: identity.generation) else { return }
            self.onEvent?(.progress(token: identity.token, bytes: totalBytesWritten))
        }
    }
    nonisolated public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let identity = Self.parse(downloadTask.taskDescription) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        let retained = inbox.appendingPathComponent(identity.token.uuidString + "-" + identity.generation.uuidString)
        do {
            guard (200...299).contains(status) else { throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "The model server returned HTTP \(status). Try again when connected."]) }
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: retained)
            Task { @MainActor [weak self] in
                guard let self, self.accepts(identity.token, generation: identity.generation) else { try? FileManager.default.removeItem(at: retained); return }
                self.transfers[identity.token] = nil
                self.onEvent?(.finished(token: identity.token, url: retained))
            }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in self?.completeFailure(identity.token, generation: identity.generation, message: message, data: nil) }
        }
    }
    nonisolated public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let identity = Self.parse(task.taskDescription) else { return }
        let ns = error as NSError
        guard ns.code != NSURLErrorCancelled else { return }
        let message = ns.localizedDescription, data = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        Task { @MainActor [weak self] in self?.completeFailure(identity.token, generation: identity.generation, message: message, data: data) }
    }
    private func completeFailure(_ token: UUID, generation: UUID, message: String, data: Data?) {
        guard accepts(token, generation: generation) else { return }
        transfers[token] = nil
        onEvent?(.failed(token: token, message: message, resumeData: data))
    }
    nonisolated public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in self?.backgroundCompletion?(); self?.backgroundCompletion = nil }
    }
}
