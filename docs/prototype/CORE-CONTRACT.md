# SermonSetCore ↔ UI contract (prototype)

This is the boundary for the four-looks prototype.

- **Codex (backend)** owns everything under `Packages/SermonSetCore/`, `project.yml`,
  `scripts/`, `SermonSet/Support/` (Info.plist, entitlements), and the sample build
  pipeline that turns `Fixtures/sample-sermons.source.json` into bundled resources.
- **Claude (UI)** owns everything a person sees or touches: all SwiftUI under
  `SermonSet/App`, `SermonSet/Looks`, `SermonSet/Features`, `SermonSet/Components`,
  `SermonSet/Resources` (asset catalog, icon), every user-visible string, and the
  sample sermon *content* in `Fixtures/sample-sermons.source.json`.

Neither side edits the other's files. If the UI needs something the core does not
expose, Claude asks; if the core needs a different shape than below, Codex records
the deviation in `docs/prototype/CORE-NOTES.md` (exact signatures) — the UI will
adapt. Names below are the target public API; small, documented deviations are fine.

Platform: iOS 26.0 deployment target, Xcode 26.6, Swift 6 language mode, strict
concurrency. The core never imports SwiftUI. Domain types never import AVFoundation.

## Product invariants the core must enforce (not the UI)

1. Every owned CardInstance implies a UserSermonHistory entry.
2. Trading (here: *trade preview*) removes a CardInstance from the binder but never
   deletes the Sermon, its history, notes, moments, transcript, or audio.
3. Repeating "keep", pack completion, or card creation is idempotent — no duplicate
   history or binder entries.
4. Original audio is immutable. Derivatives reference `sourceAudioAssetID`.
5. Nothing is uploaded. There is no network code in the core at all.
6. Capture state is persisted *before* the engine starts; audio is written in durable
   segments with a recovery manifest; an interrupted or killed session is recoverable.
7. Generated insights carry transcript revision, generator/runtime name, prompt
   version, and evidence ranges. Low evidence is flagged, never hidden. Never invent
   quotations; never present a paraphrase as a quote.
8. No silent fallback from on-device processing to any cloud service.

## Domain (all `public`, `Codable`, `Hashable`, `Sendable`; `Identifiable` where there is an `id`)

```swift
enum SermonType: String, CaseIterable { case hope, wisdom, grace, courage, conviction, worship, mission, restoration }
enum EncounterSource: String { case recorded, imported, sundayPack, trade, shared, sample }
enum TrustState: String { case personalDraft, communityMatched, churchVerified }
enum RightsState: String { case privateOnly, audioAuthorized, officialAudio, disputed, audioRemoved, noAudio }
enum ReviewState: String { case draft, reviewed, rejected }
enum LocationPrecision: String { case venue, city, privateLocation, unknown }
enum AudioAssetKind: String { case original, imported, enhanced, official, sample }

struct Venue { id: UUID; churchName: String?; city: String?; region: String?; country: String?
               latitude: Double?; longitude: Double?; precision: LocationPrecision }

struct Sermon { id: UUID; title: String; preacher: String?; venue: Venue?; serviceDate: Date
                primaryPassage: String?; sermonType: SermonType?; themes: [String]
                summary: String?          // the reviewed "big idea", nil until the listener writes/accepts one
                reflectionPrompt: String? // card-back question
                trustState: TrustState; rightsState: RightsState; isSample: Bool
                canonicalAudioAssetID: UUID?; createdAt: Date; updatedAt: Date }

struct AudioAsset { id: UUID; sermonID: UUID; kind: AudioAssetKind; duration: TimeInterval
                    byteCount: Int64; createdAt: Date; checksumSHA256: String?; sourceAudioAssetID: UUID? }

struct MarkedMoment { id: UUID; sermonID: UUID; audioAssetID: UUID?; time: TimeInterval; note: String?; createdAt: Date }
struct PersonalNote { id: UUID; sermonID: UUID; audioAssetID: UUID?; time: TimeInterval?; text: String; createdAt: Date; updatedAt: Date }

struct TranscriptSegment { id: UUID; start: TimeInterval; end: TimeInterval; text: String; confidence: Double; isFinal: Bool }
struct Transcript { id: UUID /* revision id */; sermonID: UUID; audioAssetID: UUID; revision: Int
                    segments: [TranscriptSegment]; engine: String; createdAt: Date }

struct EvidenceRange { transcriptID: UUID; segmentIDs: [UUID]; start: TimeInterval; end: TimeInterval }
struct Takeaway { id: UUID; text: String; evidence: EvidenceRange?; reviewState: ReviewState; isLowEvidence: Bool }
struct OutlineItem { id: UUID; title: String; start: TimeInterval; evidence: EvidenceRange? }
struct SermonInsights { id: UUID; sermonID: UUID; transcriptID: UUID; transcriptRevision: Int
                        generator: String   // e.g. "Apple Foundation Models (on-device)", "Extractive — no model", "Sample fixture"
                        promptVersion: String?; createdAt: Date; suggestedTitle: String?
                        outline: [OutlineItem]; takeaways: [Takeaway]; scriptureReferences: [String] }

struct CardEdition  { id: UUID; sermonID: UUID; designSeed: Int; editionLabel: String; createdAt: Date }
struct CardInstance { id: UUID; editionID: UUID; sermonID: UUID; serial: Int; acquiredAt: Date; source: EncounterSource }

struct UserSermonHistory { sermonID: UUID; source: EncounterSource; firstEncounteredAt: Date
                           listeningPosition: TimeInterval; lastListenedAt: Date?; completedAt: Date? }

struct LibraryEntry: Identifiable { var id: UUID { sermon.id }; sermon: Sermon; history: UserSermonHistory
                                    audio: AudioAsset?; momentCount: Int; noteCount: Int; ownsCard: Bool }

struct SundayPack { id: String /* ISO week, e.g. "2026-W41" */; title: String; sermons: [Sermon]; isDemo: Bool }

enum MicPermission { case undetermined, granted, denied }
enum CapabilityStatus: Sendable, Hashable { case available, needsDownload, unavailable(reason: String) }
struct CapabilityReport { speechTranscription: CapabilityStatus; onDeviceLanguageModel: CapabilityStatus
                          processingIsOnDevice: Bool /* always true in this prototype */ }

enum JobState: Sendable, Hashable { case idle, running(progress: Double?), done, unavailable(reason: String), failed(message: String) }
struct ProcessingJobs { transcription: JobState; insights: JobState }

enum BackupPreference: String { case deviceBackup /* default: included in the iPhone's own backup */, excludeFromBackup }

struct SermonSetError: Error, Identifiable { id: UUID; title: String; message: String; recoverySuggestion: String? }
// title/message are plain, calm English the UI can show directly (UI may restyle, not rewrite).
```

## `SermonStore` — `@MainActor @Observable public final class`

```swift
init(configuration: StoreConfiguration)
// StoreConfiguration:
//   .live                         — Application Support/SermonSet, file protection .completeUntilFirstUserAuthentication
//   .preview                      — in-memory, pre-loaded with the bundled samples (for SwiftUI previews/screenshots)
//   .uiTest(directory: URL)       — isolated on-disk directory, starts empty
// The app reads launch arguments via `StoreConfiguration.fromLaunchArguments()`:
//   -SermonSetPreviewData   → .preview (samples in library, two cards in binder, some moments/notes)
//   -SermonSetUITest        → .uiTest(temp dir)

// State (read-only to the UI)
var libraryEntries: [LibraryEntry]            // sorted serviceDate desc
var mostRecentEntry: LibraryEntry?
var binder: [CardInstance]                    // sorted acquiredAt desc
var lastError: SermonSetError?                // UI shows and can clear via clearError()
var capabilities: CapabilityReport
var backupPreference: BackupPreference
var hasSamplesInLibrary: Bool

func entry(for sermonID: UUID) -> LibraryEntry?
func sermon(_ id: UUID) -> Sermon?
func audioAssets(for sermonID: UUID) -> [AudioAsset]       // original first, then derivatives
func audioURL(for asset: AudioAsset) -> URL?
func moments(for sermonID: UUID) -> [MarkedMoment]          // sorted by time
func notes(for sermonID: UUID) -> [PersonalNote]            // sorted: timestamped by time, then untimed by createdAt
func transcript(for sermonID: UUID) -> Transcript?
func insights(for sermonID: UUID) -> SermonInsights?
func jobs(for sermonID: UUID) -> ProcessingJobs
func edition(for sermonID: UUID) -> CardEdition?
func card(_ id: UUID) -> CardInstance?
func clearError()

// Library mutations (all persist immediately; throw SermonSetError)
func updateSermon(_ sermon: Sermon) throws                  // title, preacher, venue, passage, type, themes, summary, reflectionPrompt
func deleteSermon(_ id: UUID) throws                        // removes local files + card instances for it
func addMoment(sermonID: UUID, time: TimeInterval, note: String?) throws -> MarkedMoment
func deleteMoment(_ id: UUID, sermonID: UUID) throws
func addNote(sermonID: UUID, text: String, time: TimeInterval?) throws -> PersonalNote
func updateNote(_ note: PersonalNote) throws
func deleteNote(_ id: UUID, sermonID: UUID) throws
func recordListening(sermonID: UUID, position: TimeInterval, duration: TimeInterval) // throttled; marks completedAt at ≥95%
func importAudio(from url: URL, title: String?) async throws -> Sermon  // copies (security-scoped), probes duration, kind .imported, source .imported

// Processing (each independently resumable; state observable via jobs(for:))
func transcribe(sermonID: UUID) async          // SpeechAnalyzer/SpeechTranscriber on-device when available, else .unavailable(reason)
func generateInsights(sermonID: UUID) async    // Foundation Models (structured, bounded chunks) when available, else extractive fallback; requires transcript
func setTakeawayReview(sermonID: UUID, takeawayID: UUID, state: ReviewState) throws
func editTakeaway(sermonID: UUID, takeawayID: UUID, text: String) throws   // becomes .reviewed, keeps evidence
func acceptSuggestedTitle(sermonID: UUID) throws

// Cards & collection
@discardableResult func createCard(for sermonID: UUID) throws -> CardInstance   // idempotent: returns the existing owned card
func previewTrade(cardID: UUID) throws          // removes from binder only; library/history/notes untouched
var discoverCatalog: [Sermon]                   // all bundled sample sermons (isSample == true)
func isInLibrary(_ sermonID: UUID) -> Bool
func currentSundayPack(now: Date = .now) -> SundayPack   // 5 samples, deterministic per ISO week, isDemo = true
func keepPack(_ pack: SundayPack) throws        // adds sermons (source .sundayPack) + cards; idempotent
func keepSample(_ sermonID: UUID) throws        // from Discover; adds to library (.sample) + card
func addSampleSermons() throws                  // first-run "explore with samples": adds 2 samples to library + cards
func removeSampleSermons() throws               // removes all isSample sermons from library and binder

// Data & privacy
func exportArchive() throws -> URL              // JSON in temp dir; includes private notes; excludes audio
func setBackupPreference(_ preference: BackupPreference) throws  // toggles isExcludedFromBackup on the recordings dir
func eraseAllData() throws
```

## `CaptureController` — `@MainActor @Observable public final class`

```swift
init(store: SermonStore, engine: CaptureEngineKind = .fromLaunchArguments())  // .live (AVAudioEngine) or .simulated (-SermonSetSimulatedCapture)

enum Phase: Equatable { case idle, preparing, recording, paused, interrupted(reason: String), finishing, failed(SermonSetError) }
var phase: Phase
var elapsed: TimeInterval                 // audio captured so far, excluding pauses; ticks ~10 Hz
var level: Float                          // 0...1, smoothed, for a meter
var levelHistory: [Float]                 // most recent ~96 values, oldest first, for a waveform strip
var inputName: String                     // "iPhone Microphone", "AirPods Pro", "USB Audio"…
var availableStorageBytes: Int64
var estimatedTimeRemaining: TimeInterval  // from free space at the recording bitrate
var sessionMoments: [MarkedMoment]        // moments marked in the live session
var sessionNotes: [PersonalNote]
var recoveryEvents: [String]              // plain-English log: "Phone call paused recording at 12:04", "Switched to AirPods"
var micPermission: MicPermission
var recoverableSessions: [RecoverableSession]   // RecoverableSession { id; startedAt; title?; recoveredDuration; segmentCount }

func requestPermission() async -> Bool
func start(_ draft: CaptureDraft) async throws  // CaptureDraft { title: String?; preacher: String?; churchName: String?; city: String? }
func pause()
func resume() throws
func markMoment(note: String? = nil)
func addNote(_ text: String)
func stop() async throws -> Sermon        // finalizes → original AudioAsset (immutable), Sermon(.personalDraft, .privateOnly), history(.recorded)
func discard() async                      // confirmed by UI first
func recover(_ session: RecoverableSession) async throws -> Sermon
func dismissRecovery(_ session: RecoverableSession) // keeps files until user deletes; just hides prompt
```

Live engine: AVAudioSession `.playAndRecord`/`.record` + AVAudioEngine input tap, 48 kHz mono AAC
segments (~30 s each) with a JSON manifest written before start and after each segment; handles
interruptions, route changes, media-services reset; background audio mode. Simulated engine: synthesizes
plausible levels and writes a short tone/silence file so the whole flow works on Simulator and in UI tests.

## `PlaybackController` — `@MainActor @Observable public final class`

```swift
init(store: SermonStore)
var nowPlayingSermonID: UUID?
var isPlaying: Bool
var currentTime: TimeInterval
var duration: TimeInterval
var rate: Float                       // 0.75, 1, 1.25, 1.5, 2
var activeAssetKind: AudioAssetKind?
var isAudioUnavailable: Bool          // e.g. noAudio/audioRemoved — UI shows "Audio unavailable"

func load(sermonID: UUID, autoplay: Bool)   // canonical asset; resumes from history position
func play(sermonID: UUID, from time: TimeInterval)  // used by moments, transcript taps, evidence links
func play(); func pause(); func toggle()
func seek(to time: TimeInterval); func skip(by seconds: TimeInterval); func setRate(_ rate: Float)
func stop()
```
Updates `currentTime` ~4 Hz while playing; writes listening progress via the store; lock-screen
Now Playing info + remote commands.

## Sample content pipeline

Claude writes `Fixtures/sample-sermons.source.json` (schema below). Codex writes
`scripts/build-samples.py` that synthesizes narration with Kokoro TTS (American voices) using the
existing venv at `~/Documents/GitHub/redwall/Tools/voice/.venv` (read-only use; fall back to macOS
`say -v Samantha`), measures exact per-segment timings, concatenates to 48 kHz mono AAC `.m4a`, and
emits `Packages/SermonSetCore/Sources/SermonSetCore/Resources/Samples/{samples.json, <slug>.m4a}`
with real `start`/`end` times. Outline items and takeaway evidence are resolved from segment indexes.

```jsonc
{
  "sermons": [{
    "slug": "peace-in-the-storm",
    "title": "Peace in the Storm", "preacher": "Jonah Reed",
    "voice": "am_michael",                      // Kokoro voice id
    "venue": { "churchName": "Grace Harbor", "city": "Portland", "region": "OR", "country": "US",
               "latitude": 45.5152, "longitude": -122.6784, "precision": "city" },
    "serviceDate": "2026-08-30",
    "primaryPassage": "Mark 4:35–41", "sermonType": "hope", "themes": ["Fear", "Trust"],
    "summary": "…", "reflectionPrompt": "…",
    "trustState": "communityMatched", "rightsState": "audioAuthorized",
    "segments": ["sentence or two…", "…"],      // narrated in order, ~2–3 min total
    "lowConfidenceSegments": [7],               // indexes rendered as low-confidence in the transcript
    "outline": [{ "title": "…", "segment": 0 }],
    "takeaways": [{ "text": "…", "segments": [3, 4] }],
    "scriptureReferences": ["Mark 4:35–41", "Psalm 46:10"],
    "sampleMoments": [{ "segment": 5, "note": "…" }],     // used only by -SermonSetPreviewData
    "sampleNotes": ["…"]
  }]
}
```
All sample people and churches are fictional; every sample sermon has `isSample = true`.
