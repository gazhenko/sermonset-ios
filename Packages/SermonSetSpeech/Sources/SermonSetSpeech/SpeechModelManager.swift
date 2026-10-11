import Foundation
import Observation
import Network
import SermonSetCore

@MainActor @Observable public final class SpeechModelManager {
    public enum Phase: Equatable, Sendable {
        case notDownloaded(sizeBytes: Int64)
        case downloading(fraction: Double, bytesPerSecond: Double)
        case paused
        case ready(sizeBytes: Int64)
        case failed(message: String)
    }
    public private(set) var state: Phase
    public private(set) var isOnCellular = false
    @ObservationIgnored private var networkReady = true
    public var allowCellular: Bool = false {
        didSet {
            try? SpeechModelFiles.write(Data(allowCellular ? [1] : [0]), to: directory.appendingPathComponent("cellular-policy"))
            if !allowCellular && isOnCellular { pause() }
        }
    }
    public let directory: URL
    public var isReady: Bool { if case .ready = state { true } else { false } }
    public static let backgroundSessionIdentifier = "com.gazhenko.sower.speech.model-download"
    static let parallelDownloads = 4
    @ObservationIgnored private let files: [SpeechModelFile]
    @ObservationIgnored private let downloader: any SpeechDownloader
    @ObservationIgnored private let freeSpace: @Sendable (URL) throws -> Int64
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var active: [UUID: Transfer] = [:]
    @ObservationIgnored private var restored: Set<UUID> = []
    @ObservationIgnored private var installing: Set<UUID> = []
    @ObservationIgnored private var pausePending: Set<UUID> = []
    @ObservationIgnored private var requested = false
    @ObservationIgnored private var restoring = true
    @ObservationIgnored private var wantsPause = false
    @ObservationIgnored private var previousBytes: Int64 = 0
    @ObservationIgnored private var previousTime = Date()
    @ObservationIgnored private var backgroundCompletion: (@MainActor @Sendable () -> Void)?
    private struct Transfer: Codable {
        var fileName: String
        var token: UUID
        var allowCellular: Bool
        var incomingFile: String?
        var bytes: Int64? // Older single-transfer journals decode without this.
    }

    public convenience init(directory: URL = SpeechModelConfiguration.directory) {
        self.init(directory: directory, files: SpeechModelConfiguration.files,
                  downloader: SpeechBackgroundDownloader(directory: directory, identifier: Self.backgroundSessionIdentifier),
                  freeSpace: { try $0.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0 })
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular) || path.isExpensive
            let ready = path.status == .satisfied
            Task { @MainActor [weak self] in self?.updateNetwork(isOnCellular: cellular, ready: ready) }
        }
        networkReady = false
        monitor.start(queue: DispatchQueue(label: "com.gazhenko.sower.speech.model-download.network"))
    }
    init(directory: URL, files: [SpeechModelFile], downloader: any SpeechDownloader, freeSpace: @escaping @Sendable (URL) throws -> Int64) {
        self.directory = directory; self.files = files; self.downloader = downloader; self.freeSpace = freeSpace
        let total = files.reduce(0) { $0 + $1.sizeBytes }
        let ready = FileManager.default.fileExists(atPath: directory.appendingPathComponent("verified-\(SpeechModelConfiguration.revision)").path)
            && files.allSatisfy { SpeechModelFiles.matchesSize($0, directory: directory) }
        state = ready ? .ready(sizeBytes: total) : .notDownloaded(sizeBytes: total)
        do {
            try SpeechModelFiles.prepare(directory)
            if let policy = try? Data(contentsOf: directory.appendingPathComponent("cellular-policy")) { allowCellular = policy.first == 1 }
            if !ready, let data = try? Data(contentsOf: transferURL) {
                let decoder = JSONDecoder()
                let saved = (try? decoder.decode([Transfer].self, from: data))
                    ?? (try? decoder.decode(Transfer.self, from: data)).map { [$0] } ?? []
                for transfer in saved where files.contains(where: { $0.name == transfer.fileName }) { active[transfer.token] = transfer }
                if !active.isEmpty { state = .paused }
            }
            if !ready, files.contains(where: { SpeechModelFiles.matchesSize($0, directory: directory) || FileManager.default.fileExists(atPath: resumeURL($0).path) }) { state = .paused }
            downloader.onEvent = { [weak self] in self?.handle($0) }
            downloader.restore()
        } catch { state = .failed(message: "The model folder could not be prepared: \(error.localizedDescription)") }
    }
    isolated deinit { monitor?.cancel() }
    public func start() {
        guard !isReady else { return }
        requested = true; wantsPause = false
        pump()
    }
    private func pump() {
        guard requested, !isReady, !restoring, pausePending.isEmpty else { return }
        if !networkReady || (isOnCellular && !allowCellular) { state = .paused; return }
        do {
            let missing = files.filter { !SpeechModelFiles.matchesSize($0, directory: directory) }
            if missing.isEmpty, active.isEmpty, installing.isEmpty {
                try SpeechModelFiles.write(Data(SpeechModelConfiguration.revision.utf8), to: verifiedURL)
                state = .ready(sizeBytes: totalBytes); requested = false; return
            }
            // Background delivery finishes outstanding work without enqueueing
            // the rest of the manifest into the OS's slow background scheduler.
            guard downloader.isForeground else { return }
            let remaining: Int64 = missing.reduce(0) { $0 + $1.sizeBytes }
            let temporary: Int64 = missing.map(\.sizeBytes).sorted(by: >).prefix(Self.parallelDownloads).reduce(0, +)
            let required: Int64 = remaining + temporary + 512 * 1024 * 1024
            guard try freeSpace(directory) >= required else {
                fail("Free at least \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)) on this iPhone to download the model safely."); return
            }
            let next = missing.filter { file in !active.values.contains { $0.fileName == file.name } }
                .prefix(max(0, Self.parallelDownloads - active.count))
            if active.isEmpty { previousBytes = completedBytes; previousTime = Date() }
            for file in next {
                let token = UUID()
                active[token] = Transfer(fileName: file.name, token: token, allowCellular: allowCellular, bytes: 0)
                try saveJournal() // Identity is durable before URLSession starts.
                let policy = try? Data(contentsOf: resumePolicyURL(file)).first
                let resume = policy == (allowCellular ? 1 : 0) ? try? Data(contentsOf: resumeURL(file)) : nil
                downloader.start(file: file, token: token, resumeData: resume, allowCellular: allowCellular)
            }
            showProgress()
        } catch { fail("The model download could not start: \(error.localizedDescription)") }
    }
    public func pause() {
        requested = false; wantsPause = true
        guard !isReady else { return }
        state = .paused
        pausePending.formUnion(Set(active.keys).subtracting(installing))
        downloader.pause()
    }
    public func cancel() {
        requested = false; wantsPause = false; pausePending.removeAll(); active.removeAll()
        downloader.cancel(); try? saveJournal()
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("Inbox"))
        for file in files {
            try? FileManager.default.removeItem(at: resumeURL(file))
            try? FileManager.default.removeItem(at: resumePolicyURL(file))
        }
        if !isReady { state = .notDownloaded(sizeBytes: totalBytes) }
    }
    public func delete() {
        cancel()
        do {
            try FileManager.default.removeItem(at: directory); try SpeechModelFiles.prepare(directory)
            state = .notDownloaded(sizeBytes: totalBytes)
        } catch { state = .failed(message: "The model could not be deleted: \(error.localizedDescription)") }
    }
    public func handleBackgroundEvents(identifier: String, completion: @escaping @MainActor @Sendable () -> Void) {
        guard identifier == Self.backgroundSessionIdentifier, let background = downloader as? SpeechBackgroundDownloader else { completion(); return }
        background.backgroundCompletion = { [weak self] in
            guard let self else { completion(); return }
            self.backgroundCompletion = completion; self.finishBackgroundEvents()
        }
    }
    func updateNetwork(isOnCellular: Bool, ready: Bool = true) {
        self.isOnCellular = isOnCellular; networkReady = ready
        if (!ready || (isOnCellular && !allowCellular)) && requested { pause(); requested = true; wantsPause = false }
        if ready && (!isOnCellular || allowCellular) && requested { pump() }
    }
    private var totalBytes: Int64 { files.reduce(0) { $0 + $1.sizeBytes } }
    private var completedBytes: Int64 { files.filter { SpeechModelFiles.matchesSize($0, directory: directory) }.reduce(0) { $0 + $1.sizeBytes } }
    private var receivedBytes: Int64 { completedBytes + active.values.reduce(0) { sum, transfer in
        guard let file = files.first(where: { $0.name == transfer.fileName }), !SpeechModelFiles.matchesSize(file, directory: directory) else { return sum }
        return sum + min(file.sizeBytes, max(0, transfer.bytes ?? 0))
    } }
    private func showProgress() {
        guard requested, !wantsPause else { return }
        let bytes = receivedBytes, now = Date(), elapsed = now.timeIntervalSince(previousTime)
        state = .downloading(fraction: Double(bytes) / Double(max(1, totalBytes)), bytesPerSecond: elapsed > 0 ? Double(max(0, bytes - previousBytes)) / elapsed : 0)
        previousBytes = bytes; previousTime = now
    }
    private var verifiedURL: URL { directory.appendingPathComponent("verified-\(SpeechModelConfiguration.revision)") }
    private var transferURL: URL { directory.appendingPathComponent("transfer.json") }
    private func resumeURL(_ file: SpeechModelFile) -> URL { directory.appendingPathComponent("Transfers/" + file.name.replacingOccurrences(of: "/", with: "_") + ".resume") }
    private func resumePolicyURL(_ file: SpeechModelFile) -> URL { directory.appendingPathComponent("Transfers/" + file.name.replacingOccurrences(of: "/", with: "_") + ".resume-policy") }
    private func saveJournal() throws {
        if active.isEmpty { try? FileManager.default.removeItem(at: transferURL) }
        else { try SpeechModelFiles.write(try JSONEncoder().encode(active.values.sorted { $0.fileName < $1.fileName }), to: transferURL) }
    }
    private func finishBackgroundEvents() {
        guard installing.isEmpty else { return }
        backgroundCompletion?(); backgroundCompletion = nil
    }
    private func fail(_ message: String) {
        requested = false; wantsPause = true
        pausePending.formUnion(Set(active.keys).subtracting(installing))
        downloader.pause()
        state = .failed(message: message)
    }
    private func saveResume(_ data: Data?, transfer: Transfer) throws {
        guard let file = files.first(where: { $0.name == transfer.fileName }), let data else { return }
        try SpeechModelFiles.write(data, to: resumeURL(file))
        try SpeechModelFiles.write(Data(transfer.allowCellular ? [1] : [0]), to: resumePolicyURL(file))
    }
    private func handle(_ event: SpeechDownloadEvent) {
        switch event {
        case .activityChanged(let foreground):
            if foreground { pump() }
        case .restorationComplete:
            restoring = false
            let inbox = directory.appendingPathComponent("Inbox")
            let retained = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
            for (token, transfer) in active where !installing.contains(token) {
                let incoming = transfer.incomingFile.flatMap { name in
                    name == URL(fileURLWithPath: name).lastPathComponent ? inbox.appendingPathComponent(name) : nil
                } ?? retained.first { $0.lastPathComponent == token.uuidString || $0.lastPathComponent.hasPrefix(token.uuidString + "-") }
                if let incoming, FileManager.default.fileExists(atPath: incoming.path) {
                    requested = !wantsPause; handle(.finished(token: token, url: incoming))
                } else if !restored.contains(token) { active[token] = nil }
            }
            do { try saveJournal(); pump() } catch { fail("The model download checkpoint could not be saved.") }
        case let .restored(name, token):
            guard let transfer = active[token], transfer.fileName == name, !isReady else { downloader.discard(token: token); return }
            restored.insert(token); requested = !wantsPause
            if wantsPause || !networkReady || (isOnCellular && !allowCellular) {
                let resumeWhenReady = !wantsPause
                pause(); wantsPause = !resumeWhenReady; requested = resumeWhenReady; return
            }
            showProgress()
        case let .progress(token, bytes):
            guard active[token] != nil, !pausePending.contains(token), !installing.contains(token) else { return }
            active[token]?.bytes = max(0, bytes); showProgress()
        case let .paused(token, data):
            guard let transfer = active[token] else { return }
            do { try saveResume(data, transfer: transfer); active[token] = nil; pausePending.remove(token); try saveJournal(); pump() }
            catch { fail("The partial model download could not be saved. Try the download again.") }
        case let .failed(token, message, data):
            guard let transfer = active[token] else { return }
            do { try saveResume(data, transfer: transfer); active[token] = nil; pausePending.remove(token); try saveJournal(); fail(message) }
            catch { fail("The partial model download could not be saved. Try the download again.") }
        case let .finished(token, url):
            guard let transfer = active[token], let file = files.first(where: { $0.name == transfer.fileName }) else { try? FileManager.default.removeItem(at: url); return }
            guard !installing.contains(token) else { return }
            active[token]?.incomingFile = url.lastPathComponent; active[token]?.bytes = file.sizeBytes
            do { try saveJournal() }
            catch { fail("The model download checkpoint could not be saved."); return }
            installing.insert(token); pausePending.remove(token)
            Task { [weak self] in
                defer { self?.installing.remove(token); self?.finishBackgroundEvents(); self?.pump() }
                do {
                    try await Task.detached { try SpeechModelFiles.verify(file, at: url) }.value
                    guard let self, self.active[token] != nil else { try? FileManager.default.removeItem(at: url); return }
                    let target = self.directory.appendingPathComponent(file.name)
                    try SpeechModelFiles.prepare(target.deletingLastPathComponent())
                    if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                    try FileManager.default.moveItem(at: url, to: target)
                    #if os(iOS)
                    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
                    #endif
                    try? FileManager.default.removeItem(at: self.resumeURL(file))
                    try? FileManager.default.removeItem(at: self.resumePolicyURL(file))
                    self.active[token] = nil; self.pausePending.remove(token)
                    try self.saveJournal(); self.showProgress()
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    guard let self, self.active[token] != nil else { return }
                    self.active[token] = nil; self.pausePending.remove(token); try? self.saveJournal()
                    self.fail((error as? SermonSetError)?.message ?? "The model file could not be saved. Try the download again.")
                }
            }
        }
    }
}
