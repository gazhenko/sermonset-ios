# SermonSetCore integration notes

The contract is implemented by a native Swift package. Domain values are public, Codable, Hashable, Sendable, and Identifiable where specified, with public initializers in `Domain.swift`. The core does not import SwiftUI and contains no application networking or analytics. Xcode 26.6 ships an iOS 26.5 Simulator SDK in this environment; the deployment target remains iOS 26.0.

## Exact API additions and differences

The store, capture, and playback signatures in `CORE-CONTRACT.md` are retained. Store state is read-only to callers. These additional store methods inherit `SermonStore`'s MainActor isolation:

```swift
public func refreshCapabilities() async
public func prepareSpeechAssets() async throws
public func updateMoment(_ moment: MarkedMoment) throws
```

`updateMoment` changes only an existing moment's `note`, including clearing it with nil. It retains the stored id, sermonID, time, audioAssetID, and createdAt. Unknown IDs or mismatched sermon IDs throw `SermonSetError` and set `lastError`.

`SermonInsights` adds two optional provenance fields:

```swift
public var transcriptChecksumSHA256: String?
public var generatorRuntime: String?

public init(id: UUID = UUID(), sermonID: UUID, transcriptID: UUID,
            transcriptRevision: Int, generator: String, promptVersion: String? = nil,
            createdAt: Date = .now, suggestedTitle: String? = nil,
            outline: [OutlineItem] = [], takeaways: [Takeaway] = [],
            scriptureReferences: [String] = [], transcriptChecksumSHA256: String? = nil,
            generatorRuntime: String? = nil)
```

The initializers retain existing parameter names/defaults. Optional provenance fields decode older version-1 documents without those fields. The hash covers segment identity, times, text, confidence, and finality; runtime identifies the OS and adapter, not a verified Apple model weight version.

The quote-handling and capture-start/service-date follow-ups add no public API signatures or schema fields. Their behavioral changes are described below; the quote-handling follow-up also changes the internal model checkpoint version.

`public func updateSermon(_ sermon: Sermon) throws` now accepts `serviceDate` alongside the other editable metadata. The stored `createdAt`, identity, original audio reference, rights/trust state, and sample flag remain unchanged; `updatedAt` is refreshed. Editing the service date preserves acquisition/listening history. Version-1 date storage remains whole-second ISO-8601.

Public adapter interfaces:

```swift
@MainActor public protocol TranscriptionAdapter: Sendable {
    func capability() async -> CapabilityStatus
    func prepareAssets() async throws
    func transcribe(fileURL: URL, startingAt: TimeInterval,
                    onSegments: @escaping @MainActor @Sendable ([TranscriptSegment]) throws -> Void)
        async throws -> [TranscriptSegment]
}

@MainActor public protocol InsightsAdapter: Sendable {
    func capability() -> CapabilityStatus
    func generate(transcript: Transcript, moments: [MarkedMoment], checkpointDirectory: URL,
                  onProgress: @escaping @MainActor @Sendable (Double) -> Void)
        async throws -> SermonInsights
}
```

Concrete adapters are `SpeechAnalyzerAdapter` and `FoundationModelInsightsAdapter`, each with `public init()`. `ExtractiveInsightsAdapter` exposes `public func generate(transcript: Transcript, moments: [MarkedMoment]) -> SermonInsights`. `EvidenceValidator`, `InsightChunk`, and `InsightChunking` expose deterministic validation/chunking helpers; their exact declarations are in the package sources. Store adapter injection is internal for tests; the UI initializer is still `init(configuration: StoreConfiguration)`.

## Launch configuration and previews

`StoreConfiguration` is a public Sendable, Hashable enum with `.live`, `.preview`, `.uiTest(directory: URL)` and `public static func fromLaunchArguments() -> StoreConfiguration`. `CaptureEngineKind` provides `.live`, `.simulated` and the corresponding public argument reader.

- `-SermonSetPreviewData` selects an in-memory library with all eight samples, two binder cards, fixture moments, and notes. Its temporary files are used only if capture/export is invoked; bundled audio stays in the resource bundle.
- `-SermonSetUITest` selects an isolated on-disk store. An optional `-SermonSetUITestDirectory <absolute-path>` chooses the folder; otherwise the app-temporary `SermonSet-UITest` folder is reused. A new directory starts empty; an existing directory retains data across relaunch for persistence tests. Supply a unique directory for each fresh test.
- `-SermonSetSimulatedCapture` selects the tone-writing engine and grants the controller's simulated permission immediately. It never calls the microphone permission API. It works with either store configuration.
- Preview takes precedence if both preview and UI-test flags are present.

Empty capture/import titles remain empty strings when no title is supplied; the UI owns display placeholders. Edition labels are stored as `Personal` / `Sample`; a pack's title is its ISO-week ID, leaving display phrasing to the UI.

## Persistence and collection

Version 1 uses atomic JSON under Application Support/SermonSet, with recordings and session manifests in separate directories. JSON keeps this local prototype inspectable without dependencies. A mutation validates a copy, writes it atomically, and then publishes observable state. Invalid references, malformed JSON, and unsupported versions preserve the original and a recovery copy, surface `lastError`, and block writes until explicit restore/erase. The implementation currently supports version 1; it does not guess migrations for future versions.

Live files request `.completeUntilFirstUserAuthentication`. Data Protection is not verifiable on Simulator. Device backup includes app data by default; opting out sets exclusion flags on the root, recordings, and sessions directories. Export produces protected temporary JSON with private notes and audio metadata, excludes audio bytes and local audio paths, and excludes the export directory from backup. Dates use whole-second ISO-8601 precision; audio positions and ranges remain numeric with subsecond precision.

Every owned card implies library history. Keep/sample/pack/create-card retries are idempotent, and trade preview removes only the card. Sermon history, original audio, transcripts, insights, moments, and notes remain. This is a local demonstration, not a production trading backend. Edition identity and design seeds are SHA-256-derived from sermon identity. Sunday Packs use ISO weeks in UTC, choose five unique bundled samples, prefer sermons outside the library, and persist the first selection so a keep does not change that week's pack.

## Capture, recovery, and playback

A protected manifest exists before the engine starts. The live AVAudioEngine tap copies input buffers into a bounded serial writer queue, converts supported input formats to 48 kHz mono, writes 96 kbps AAC segments approximately every 30 seconds, closes each container, and checkpoints its SHA-256 checksum in the manifest. The simulated engine uses the same writer and one-second segments to exercise recovery quickly. RMS levels update at approximately 10 Hz with a 96-value history; elapsed time excludes pauses.

If `start(_:)` throws after creating its journal, cleanup cancels the ticker, stops/drains and clears the engine, and releases that session's audio ownership. An empty session with no captured audio is deleted and its journal cleared, so `start(_:)` can retry while `.failed(error)` remains visible. The journal/files are retained when segments exist or captured duration is nonzero, including buffered audio finalized by cleanup; the same controller can save with `stop()` or erase with `discard()`, and a new start remains blocked until then. A directory-removal failure is included in the error's recovery suggestion while retry remains possible. Failure callbacks carry their originating session ID, so a delayed callback from a stopped engine cannot interrupt a later recording. Engine-factory injection is internal for deterministic tests; the public capture initializer is unchanged.

Interruption, resume, route changes, media-services reset, and low-storage conditions preserve completed segments and append events. HFP provides Bluetooth microphone input; A2DP is enabled as an output profile and is not claimed to provide input. Playback pauses synchronously before capture takes the audio session. Playback uses AVAudioPlayer with rate/seek/skip, approximately 4 Hz progress, two-second store throttling, forced pause/seek checkpoints, Now Playing, and remote commands.

Stop/recovery checks completed-segment checksums, streams them into a separate final `.m4a`, hashes the immutable original, and atomically saves the sermon/history/annotations. AAC is decoded and encoded once during concatenation; temporary peak disk use includes both segments and the final original. Finalized session IDs make recovery retries idempotent. Recovery ignores unlisted partial containers; dismissed sessions retain files until explicit erase. A sudden termination may lose the unfinished live segment and queued buffers; the nominal segment interval is 30 seconds, not a measured crash-loss guarantee. Simulator snapshot recovery proves the completed-segment path, not physical crash-proof recording.

## Transcription and insights

English SpeechAnalyzer/SpeechTranscriber support and installed AssetInventory state are checked at runtime. Capability refresh never calls asset preparation. Only explicit `prepareSpeechAssets()` requests Apple's system asset installation; no installation was invoked during verification. Unavailable speech produces an observable unavailable job and retains audio. File transcription stores finalized text, times, and confidence in protected checkpoints; retry continues at the last finalized range. Transcript revisions are retained for old insight evidence. Speech permission and actual timestamp alignment still require device validation. The macOS 26.4 Apple-silicon host attempt compiled and invoked the same production adapter on `open-hands.m4a`, but English assets were `.supported`, not `.installed`, so it reported `.needsDownload` and produced no segments. Live result timestamps/confidence remain unverified; exact evidence is in `docs/REVIEW.md`.

Foundation Models availability is independent of speech and may vary on Simulator or a physical device. Each chunk uses a fresh structured `@Generable` session with a conservative UTF-8 input bound, schema/instruction overhead, a 600-token response budget, and safety reserve inside the 4,096-token context. iOS 26.4+ token-count APIs are availability guarded. Durable chunk checkpoints are bound to transcript hash, prompt/validation version (`bounded-evidence-v2`), and runtime. V1 chunks are ignored on regeneration so older sanitized output is not reused. Invalid or nonfinal citations are dropped, low-confidence evidence is flagged, and invented quoted strings are rejected before quote stripping, including nested and multiline spans. Generated and sample paraphrases remove paired or boundary quotation delimiters while retaining U+2019 and ASCII apostrophes within words (`Peter’s`, `don't`); unpaired possessives and literal internal double marks within a sentence remain intact. Existing saved insights and listener edits are not rewritten to reconstruct missing punctuation. Semantic quality still requires listener review; valid IDs alone do not establish a correct paraphrase.

Claude reported a Simulator UI run where the real on-device Foundation Models adapter generated three evidence-linked takeaways, a low-evidence flag, and an outline for the bundled “Breakfast on the Shore” transcript. That attributed observation is recorded separately from Codex's deterministic tests and the blocked host speech attempt. Physical-device AI validation remains outstanding.

If the model is unavailable before or during generation, the store uses verbatim finalized excerpts, weights source-matching marked moments higher, and records generator `Extractive — no model`. Neither adapter has a cloud fallback. Transcription and insights can be retried independently; observable jobs reset to idle on relaunch while durable checkpoints remain available for retry.

## Sample resources and verification commands

`scripts/build-samples.py` reads Claude's source fixture without modifying it, tries cached Kokoro assets in the existing read-only venv with offline flags, and falls back to installed macOS Samantha. It measures 48 kHz PCM segment lengths before encoding 64 kbps mono AAC, checks output timing/format, and writes `samples.json` plus `.m4a` files. Eight current samples occupy 6,342,936 audio bytes; their measured lengths are 88–105 seconds with the provided text and voice. They are shorter than the brief's approximate 2–3 minute content target; source content was retained. The loader marks them as samples, retains supplied rights/trust metadata, resolves evidence indexes, and records generator `Sample fixture`.

```sh
scripts/dev.sh generate
scripts/dev.sh test
scripts/dev.sh build
scripts/dev.sh run -SermonSetPreviewData -SermonSetSimulatedCapture
scripts/dev.sh run -SermonSetUITest -SermonSetSimulatedCapture
scripts/dev.sh screenshot build/sermonset-core.png
python3 scripts/build-samples.py
```

All commands honor `SIM_UDID` and `DERIVED_DATA` where applicable; defaults are the assigned Codex simulator and `build/DerivedData-core`. `SermonSetCore` is an independent scheme using `SermonSetCoreChecks`, a native test bundle compiling the same Swift Testing files against the package without UI sources. The app scheme includes the package test target and Claude's `SermonSetUITests` target. `TEST_SCHEME=SermonSet scripts/dev.sh test` selects that full scheme. Alternate AppIcon-Rubric, AppIcon-Vespers, and AppIcon-Lumen assets are enabled. Exact executed commands and evidence boundaries are recorded in `docs/REVIEW.md`.

The current core gate passes 37/37 tests and the full app build. Four regressions added for capture-start/service-date behavior cover failure before engine creation, empty engine-start cleanup/retry, delayed callbacks from the old engine, finalized/buffered AAC through save and discard, and service-date persistence with immutable creation dates. Existing quote regressions cover apostrophes, nested/boundary quotes, whole curly-quoted sentences, multiline invented quotations, generated output validation, and sample takeaway loading. These deterministic checks do not assert model availability or live transcription success on the host.
