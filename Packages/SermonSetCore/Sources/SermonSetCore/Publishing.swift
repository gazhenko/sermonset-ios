import Foundation
import Observation

public enum PublicationState: String,Codable,Hashable,Sendable,CaseIterable {
    case pendingUpload, uploading, quarantine, validating, pendingRights, approved, published, rejected, disputed, removed, superseded
    public var terminal: Bool { [.published,.rejected,.disputed,.removed,.superseded].contains(self) }
}
public enum PublicationRightsBasis: String,Codable,Sendable { case none,churchReview,serviceQR,official }
public struct PublishChecklist: Codable,Hashable,Sendable {
    public var musicReviewed: Bool; public var prayerRequestsReviewed: Bool; public var childrenReviewed: Bool; public var privateTalkReviewed: Bool
    public init(musicReviewed: Bool = false,prayerRequestsReviewed: Bool = false,childrenReviewed: Bool = false,privateTalkReviewed: Bool = false) { self.musicReviewed = musicReviewed; self.prayerRequestsReviewed = prayerRequestsReviewed; self.childrenReviewed = childrenReviewed; self.privateTalkReviewed = privateTalkReviewed }
    var complete: Bool { musicReviewed && prayerRequestsReviewed && childrenReviewed && privateTalkReviewed }
}
public struct PublishSelection: Hashable,Sendable {
    public var includeReviewedText: Bool; public var audioAssetID: UUID?; public var churchID: String?; public var service: String?
    public var rightsBasis: PublicationRightsBasis; public var serviceToken: String?; public var checklist: PublishChecklist
    public init(includeReviewedText: Bool = false,audioAssetID: UUID? = nil,churchID: String? = nil,service: String? = nil,rightsBasis: PublicationRightsBasis = .none,serviceToken: String? = nil,checklist: PublishChecklist) {
        self.includeReviewedText = includeReviewedText; self.audioAssetID = audioAssetID; self.churchID = churchID; self.service = service; self.rightsBasis = rightsBasis; self.serviceToken = serviceToken; self.checklist = checklist
    }
}
public struct PublishRequest: Codable,Hashable,Sendable {
    public struct Audio: Codable,Hashable,Sendable { public var byteCount: Int64; public var duration: Double; public var checksumSHA256: String; public var contentType: String; public var trimStart: Double; public var trimEnd: Double; public var sourceChecksumSHA256: String }
    public var title: String; public var preacher: String; public var churchID: String?; public var service: String?; public var serviceDate: Date
    public var primaryPassage: String; public var themes: [String]; public var sermonType: String
    public var city: String?; public var region: String?; public var country: String?; public var summary: String?; public var reflectionPrompt: String?
    public var reviewed: Bool; public var checklist: PublishChecklist; public var rightsBasis: PublicationRightsBasis; public var serviceToken: String?; public var audio: Audio?
}
public struct CommunityPublication: Codable,Hashable,Sendable,Identifiable { public var id: String; public var sermonID: String; public var state: PublicationState; public var audioAssetID: String?; public var createdAt: Date }
public struct PublicationJob: Codable,Hashable,Sendable,Identifiable {
    public var id: UUID
    public var localSermonID: UUID
    public var localAudioAssetID: UUID?
    public var server: String
    public var accountID: String
    public var payload: PublishRequest
    public var state: PublicationState = .pendingUpload
    public var publicationID: String?
    public var communitySermonID: String?
    public var uploadURL: URL?
    public var isCancelled: Bool?
    public var uploadTaskID: Int?
    public var attempts: Int = 0
    public var retryAt: Date?
    public var lastError: String?
    public var createdAt: Date = .now
}
extension SermonStore {
    public func buildPublishRequest(sermonID: UUID,selection: PublishSelection,audience: String) throws -> PublishRequest {
        let sermon = try requireSermon(sermonID)
        let preacher = sermon.preacher?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let passage = sermon.primaryPassage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var missingFields: [String] = []
        if sermon.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { missingFields.append("title") }
        if preacher.isEmpty { missingFields.append("preacher") }
        if passage.isEmpty { missingFields.append("passage") }
        if sermon.sermonType == nil { missingFields.append("kind") }
        guard missingFields.isEmpty, let sermonType = sermon.sermonType else {
            throw SermonSetError(title: "Public details need review",message: "Add the missing fields before publishing: \(missingFields.joined(separator: ", ")).")
        }
        guard !sermon.isSample, selection.checklist.complete else { throw SermonSetError(title: "Publication needs review",message: "Review the sensitive-content checklist before publishing your sermon.") }
        guard sermon.title.count <= 200, preacher.count <= 120, passage.count <= 150,
              sermon.themes.count <= 12, sermon.themes.allSatisfy({ !$0.isEmpty && $0.count <= 60 }) else {
            throw SermonSetError(title: "Public details need review",message: "Keep the public title, preacher, passage, and themes within their size limits.")
        }
        var audio: PublishRequest.Audio?
        if let assetID = selection.audioAssetID {
            guard selection.rightsBasis != .none, let churchID = selection.churchID, !churchID.isEmpty, let asset = document.audio[assetID], asset.sermonID == sermonID, asset.kind == .enhanced, let provenance = derivativeProvenance(for: assetID), trimWindow(for: provenance.sourceAssetID) == provenance.trim, let file = audioURL(for: asset), asset.byteCount <= 200_000_000, asset.duration <= 10_800, asset.duration > 0, let checksum = asset.checksumSHA256, try LocalFiles.checksum(file) == checksum else { throw SermonSetError(title: "Audio needs review",message: "Audio publication requires a rights basis and an explicitly trimmed Voice Focus derivative, at most 200 MB and 3 hours.") }
            if selection.rightsBasis == .serviceQR {
                guard let token = selection.serviceToken else { throw TokenVerificationError.malformed }
                let grant = try verifyServiceToken(token,audience: audience)
                guard grant.publicSharingAllowed, grant.church == churchID, grant.service == selection.service, abs(grant.startsAt.timeIntervalSince(sermon.serviceDate)) <= 86_400 else { throw SermonSetError(title: "Sharing permission unavailable",message: "This service QR does not permit sharing this sermon.") }
            }
            audio = PublishRequest.Audio(byteCount: asset.byteCount,duration: asset.duration,checksumSHA256: checksum,contentType: "audio/mp4",trimStart: provenance.trim.start,trimEnd: provenance.trim.end,sourceChecksumSHA256: provenance.sourceChecksum)
        }
        let venue = Self.privacySafeVenue(sermon.venue)
        return PublishRequest(title: sermon.title,preacher: preacher,churchID: selection.churchID,service: selection.service,serviceDate: sermon.serviceDate,primaryPassage: passage,themes: sermon.themes,sermonType: sermonType.rawValue,city: venue?.city,region: venue?.region,country: venue?.country,summary: selection.includeReviewedText ? sermon.summary : nil,reflectionPrompt: selection.includeReviewedText ? sermon.reflectionPrompt : nil,reviewed: true,checklist: selection.checklist,rightsBasis: selection.rightsBasis,serviceToken: selection.serviceToken,audio: audio)
    }
    public var publishingJobs: [PublicationJob] { (document.features?.publications ?? [:]).values.sorted { $0.createdAt > $1.createdAt } }
}
public struct UploadCompletion: Sendable { public var jobID: UUID; public var status: Int?; public var error: String? }
@MainActor public protocol PublicationUploadTransport: AnyObject {
    func start(jobID: UUID,url: URL,file: URL) throws -> Int
    func restore() async -> [UUID:Int]
    func cancel(jobID: UUID)
    var onCompletion: (@MainActor @Sendable (UploadCompletion) -> Void)? { get set }
}
private final class UploadDelegate: NSObject,URLSessionTaskDelegate,@unchecked Sendable {
    let completion: @Sendable (UploadCompletion) -> Void
    let finished: @Sendable () -> Void
    init(completion: @escaping @Sendable (UploadCompletion) -> Void,finished: @escaping @Sendable () -> Void) { self.completion = completion; self.finished = finished }
    func urlSession(_ session: URLSession,task: URLSessionTask,didCompleteWithError error: (any Error)?) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        completion(UploadCompletion(jobID: id,status: (task.response as? HTTPURLResponse)?.statusCode,error: error?.localizedDescription))
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { finished() }
}
@MainActor public final class BackgroundPublicationUploader: PublicationUploadTransport {
    public var onCompletion: (@MainActor @Sendable (UploadCompletion) -> Void)?
    public var onBackgroundEventsFinished: (@MainActor @Sendable () -> Void)?
    public let identifier: String
    private var tasks: [UUID:URLSessionUploadTask] = [:]
    private var delegate: UploadDelegate!
    private var session: URLSession!
    public init(identifier: String = (Bundle.main.bundleIdentifier ?? "com.gazhenko.sermonset")+".publishing") {
        self.identifier = identifier
        delegate = UploadDelegate(completion: { @Sendable [weak self] completion in Task { @MainActor [weak self] in self?.tasks[completion.jobID] = nil; self?.onCompletion?(completion) } },finished: { @Sendable [weak self] in Task { @MainActor [weak self] in self?.onBackgroundEventsFinished?() } })
        #if os(iOS)
        let config = URLSessionConfiguration.background(withIdentifier: identifier); config.sessionSendsLaunchEvents = true
        #else
        let config = URLSessionConfiguration.default
        #endif
        config.isDiscretionary = false; config.waitsForConnectivity = true
        session = URLSession(configuration: config,delegate: delegate,delegateQueue: nil)
    }
    public func start(jobID: UUID,url: URL,file: URL) throws -> Int {
        guard tasks[jobID] == nil else { return tasks[jobID]!.taskIdentifier }
        var request = URLRequest(url: url); request.httpMethod = "PUT"; request.setValue("audio/mp4",forHTTPHeaderField: "Content-Type")
        let task = session.uploadTask(with: request,fromFile: file); task.taskDescription = jobID.uuidString; tasks[jobID] = task; task.resume(); return task.taskIdentifier
    }
    public func restore() async -> [UUID:Int] {
        var result: [UUID:Int] = [:]
        for task in await session.allTasks { if let upload = task as? URLSessionUploadTask, let id = task.taskDescription.flatMap(UUID.init(uuidString:)) { tasks[id] = upload; result[id] = task.taskIdentifier } }
        return result
    }
    public func cancel(jobID: UUID) { tasks[jobID]?.cancel(); tasks[jobID] = nil }
}
@MainActor @Observable public final class PublishingController {
    public private(set) var state: JobState = .idle
    public var jobs: [PublicationJob] { store.publishingJobs }
    public private(set) var publications: [CommunityPublication] = []
    @ObservationIgnored private let store: SermonStore
    @ObservationIgnored private let community: CommunityController
    @ObservationIgnored private let uploader: any PublicationUploadTransport
    @ObservationIgnored private var running = false
    @ObservationIgnored private var submitting: Set<UUID> = []
    @ObservationIgnored private var retryTask: Task<Void,Never>?
    public init(store: SermonStore,community: CommunityController,uploader: (any PublicationUploadTransport)? = nil) {
        self.store = store; self.community = community; self.uploader = uploader ?? BackgroundPublicationUploader()
        self.uploader.onCompletion = { [weak self] completion in Task { @MainActor [weak self] in await self?.uploadCompleted(completion) } }
    }
    public func handleBackgroundSession(identifier: String,completion: @escaping @MainActor @Sendable () -> Void) {
        guard let uploader = uploader as? BackgroundPublicationUploader, uploader.identifier == identifier else { completion(); return }
        uploader.onBackgroundEventsFinished = completion
    }
    @discardableResult public func enqueue(sermonID: UUID,selection: PublishSelection,confirmed: Bool) throws -> PublicationJob {
        guard confirmed, let account = community.account else { throw SermonSetError(title: "Confirmation needed",message: "Confirm exactly what you want to publish with your community account.") }
        let payload = try store.buildPublishRequest(sermonID: sermonID,selection: selection,audience: community.configuration.audience)
        let job = PublicationJob(id: UUID(),localSermonID: sermonID,localAudioAssetID: selection.audioAssetID,server: community.configuration.audience,accountID: account.id,payload: payload)
        try save(job); return job
    }
    private func save(_ job: PublicationJob) throws { try store.transaction { if $0.features == nil { $0.features = CoreFeatures() }; if $0.features?.publications == nil { $0.features?.publications = [:] }; $0.features?.publications?[job.id] = job } }
    public func cancel(_ id: UUID) throws {
        guard var job = jobs.first(where: { $0.id == id }), !submitting.contains(id), [.pendingUpload,.uploading].contains(job.state) else { throw SermonSetError(title: "Publication already submitted",message: "Only an unsubmitted or uploading publication can be cancelled. Report or request removal of already submitted content.") }
        job.isCancelled = true; job.retryAt = nil; try save(job); uploader.cancel(jobID: id)
    }
    public func retry(_ id: UUID) async { guard var job = jobs.first(where: { $0.id == id }), !job.state.terminal, job.isCancelled != true else { return }; job.retryAt = nil; job.lastError = nil; try? save(job); await process() }
    public func process(now: Date = .now) async {
        guard !running else { return }; running = true; state = .running(progress: nil); defer { running = false }
        let restored = await uploader.restore()
        for original in jobs where original.isCancelled != true && !original.state.terminal && original.server == community.configuration.audience && original.accountID == community.account?.id && (original.retryAt == nil || original.retryAt! <= now) {
            var job = original
            do {
                try community.ensureIdentity()
                if job.publicationID == nil {
                    struct Response: Decodable { var publicationID: String; var sermonID: String; var audioAssetID: String?; var uploadURL: URL? }
                    submitting.insert(job.id)
                    defer { submitting.remove(job.id) }
                    let response: Response = try await community.client.send("POST","/v1/publications",body: job.payload,key: job.id.uuidString)
                    job.publicationID = response.publicationID; job.communitySermonID = response.sermonID; job.uploadURL = response.uploadURL
                    job.state = job.payload.audio == nil ? .pendingRights : .uploading; try save(job)
                }
                if job.payload.audio != nil && [.pendingUpload,.uploading].contains(job.state) {
                    if let task = restored[job.id] { job.uploadTaskID = task; try save(job); continue }
                    guard let id = job.localAudioAssetID, let asset = store.document.audio[id], let file = store.audioURL(for: asset), let uploadURL = job.uploadURL, try LocalFiles.checksum(file) == job.payload.audio?.checksumSHA256 else { throw SermonSetError(title: "Upload audio unavailable",message: "The reviewed enhanced file is missing or changed. Your original is preserved.") }
                    job.state = .uploading; job.lastError = nil; try save(job)
                    job.uploadTaskID = try uploader.start(jobID: job.id,url: uploadURL,file: file); try save(job)
                } else if job.state == .quarantine { try await complete(&job) }
                else { try await refresh(&job) }
            } catch { fail(&job,error: error,now: now) }
        }
        state = .done; scheduleRetry()
    }
    private func scheduleRetry() {
        retryTask?.cancel()
        let active = jobs.filter { $0.isCancelled != true && !$0.state.terminal && $0.server == community.configuration.audience && $0.accountID == community.account?.id }
        let due = active.compactMap { job -> Date? in
            if let date = job.retryAt { return date == .distantFuture ? nil : date }
            if [.quarantine,.validating,.pendingRights,.approved].contains(job.state) { return Date.now.addingTimeInterval(45) }
            return nil
        }.min()
        guard let due else { return }
        let seconds = max(1,min(3600,due.timeIntervalSinceNow))
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            await self?.process()
        }
    }
    private func complete(_ job: inout PublicationJob) async throws {
        guard let id = job.publicationID else { return }
        let _: APIReceipt = try await community.client.send("POST","/v1/publications/"+CommunityClient.escape(id)+"/complete",body: EmptyBody(),key: "complete-"+job.id.uuidString)
        try await refresh(&job)
    }
    private func refresh(_ job: inout PublicationJob) async throws {
        guard let id = job.publicationID else { return }; struct Response: Decodable { var publication: CommunityPublication }
        let response: Response = try await community.client.request("GET","/v1/publications/"+CommunityClient.escape(id))
        job.state = response.publication.state; job.lastError = nil; job.retryAt = nil; try save(job)
    }
    private func fail(_ job: inout PublicationJob,error: any Error,now: Date) {
        job.attempts += 1; job.lastError = error.localizedDescription
        let transient = error is URLError || (error as? CommunityAPIError)?.retryable == true
        job.retryAt = transient ? now.addingTimeInterval(min(3600,pow(2,Double(min(job.attempts,10)))*5)) : .distantFuture
        try? save(job); state = .failed(message: error.localizedDescription); scheduleRetry()
    }
    private func uploadCompleted(_ result: UploadCompletion) async {
        guard var job = jobs.first(where: { $0.id == result.jobID }), !job.state.terminal, job.isCancelled != true else { return }
        do {
            guard result.error == nil, let status = result.status, (200..<300).contains(status) else { throw CommunityAPIError(code: "upload_failed",message: result.error ?? "Upload could not finish. Retry the reviewed file.",status: result.status ?? 503) }
            job.uploadTaskID = nil; job.state = .quarantine; try save(job)
            guard job.server == community.configuration.audience, job.accountID == community.account?.id else { return }
            try await complete(&job)
        } catch { fail(&job,error: error,now: .now) }
    }
    public func refreshPublications() async throws { publications = try await community.client.page("/v1/publications") }
    isolated deinit { retryTask?.cancel() }
}
