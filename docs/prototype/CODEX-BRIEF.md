# Codex brief — SermonSetCore backend for the four-looks prototype

You are the backend engineer. Claude (a separate agent, working in this same checkout
right now) builds every screen, view, visual style, and user-facing string. You build the
non-visual engine the UI binds to. Goal: a working native iOS prototype of SermonSet on
the iOS Simulator, with real recording, recovery, import, playback, local persistence,
on-device transcription/insight adapters, and card/pack/trade-preview logic.

## Read first

1. `AGENTS.md` and `README.md` in this repo (`~/Documents/GitHub/sermonset-ios`).
2. `docs/prototype/CORE-CONTRACT.md` — **the public API you implement.** This is the
   most important file. Match its names and shapes; record any deviation with exact
   signatures in `docs/prototype/CORE-NOTES.md`.
3. Product knowledge base (read-only): `~/Documents/GitHub/sermonset/CONTEXT.md`,
   `~/Documents/GitHub/sermonset/AGENTS.md`, and in `~/Documents/GitHub/sermonset/docs/`:
   `data-model.md`, `audio-and-publishing.md`, `on-device-ai.md`, `privacy-rights-and-moderation.md`,
   `collection-trading-and-atlas.md`.
4. Current plan (supersedes older docs where they conflict):
   `~/Documents/Obsidian Git/Obsidian Git/obsidian/knowledge-base/wiki/sources/2026-09-05 SermonSet Product And Engineering Handoff.md`
   — especially §5 (native interfaces, capture, 4,096-token context), §6, §7 invariants.
5. Reference toolchain conventions (read-only): `~/Developer/ios-pipeline`
   (`project.yml`, `Packages/AppCore`, `scripts/ios`).

## Ownership — do not cross

You own and may create/edit:
- `project.yml` (XcodeGen; regenerate `SermonSet.xcodeproj` with `/opt/homebrew/bin/xcodegen`)
- `Packages/SermonSetCore/**` (sources, resources, tests)
- `SermonSet/Support/**` (Info.plist, entitlements — no Swift files)
- `scripts/**`, `docs/REVIEW.md`, `docs/prototype/CORE-NOTES.md`

You must **not** create or edit anything in `SermonSet/App`, `SermonSet/Looks`,
`SermonSet/Features`, `SermonSet/Components`, `SermonSet/Resources`, or
`Fixtures/sample-sermons.source.json`. Do not write SwiftUI. Do not write user-facing
copy beyond plain error titles/messages in `SermonSetError` and the Info.plist strings
given below (use them verbatim).

## Project setup

- XcodeGen `project.yml`: app target `SermonSet` (iOS app, sources `SermonSet/` excluding
  `SermonSet/Support/Info.plist` from compile, resources include `SermonSet/Resources`),
  local Swift package `Packages/SermonSetCore` (library product `SermonSetCore`, with
  resources), scheme `SermonSet` with the package test target included in its Test action.
- Bundle id `com.gazhenko.sermonset`, display name `SermonSet`, version 0.1.0 (1),
  deployment target iOS 26.0, iPhone only, portrait, Swift 6 language mode,
  `SWIFT_APPROACHABLE_CONCURRENCY = YES`, app target `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
  No code signing needed for Simulator (`CODE_SIGNING_ALLOWED=NO` is fine for sim builds).
- `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; launch screen `UILaunchScreen` with
  `UIColorName = LaunchBackground` (Claude supplies the asset catalog).
- `UIBackgroundModes = [audio]`.
- Info.plist strings — use verbatim:
  - `NSMicrophoneUsageDescription`: "SermonSet records the sermons you choose to capture. Recordings stay private on this iPhone unless you decide otherwise."
  - `NSSpeechRecognitionUsageDescription`: "SermonSet transcribes your recordings on this iPhone so you can search and revisit what was preached."
- No third-party dependencies. No network code anywhere in the core. No analytics.

## What to build (in this order — keep the package compiling at every step)

1. **Domain + persistence**: types from the contract; a versioned on-disk store (JSON
   documents or SQLite — your call, justify in CORE-NOTES) under Application Support with
   file protection, atomic writes, schema version, corrupt-file preservation (never
   silently overwrite a corrupt store; surface `lastError`). `StoreConfiguration`
   `.live`, `.preview`, `.uiTest(directory:)`, `fromLaunchArguments()`.
   **As soon as the public domain types and `SermonStore` signatures compile, write
   `docs/prototype/CORE-NOTES.md`** with the exact public API so Claude can align early.
2. **Collection logic**: cards, editions (personal edition per sermon, deterministic
   `designSeed` from the sermon id), binder, trade preview, Sunday Pack (deterministic per
   ISO week, 5 samples, prefer ones not yet in the library), keep/keepPack/samples,
   idempotency. Invariants 1–3 from the contract with tests.
3. **Capture** (`CaptureController`, live + simulated engines): persist session manifest
   before start; AVAudioSession (`.playAndRecord`, mode `.default`, allow Bluetooth HFP and
   A2DP input where sensible) + AVAudioEngine input tap → 48 kHz mono AAC segments (~30 s)
   with manifest updates; level metering (smoothed RMS → 0…1) and `levelHistory`;
   interruption (phone call) → `.interrupted` then auto/explicit resume appending a
   recovery event; route change → update `inputName` + event; media-services reset;
   free-space checks + `estimatedTimeRemaining`; stop → concatenate segments into one
   immutable original `.m4a` (or keep segments + composition — your call) with SHA-256;
   create Sermon/history/moments/notes. On launch, detect unfinished manifests →
   `recoverableSessions`; `recover` builds the Sermon from completed segments.
   Simulated engine (`-SermonSetSimulatedCapture` launch arg) produces believable
   levels and a real short audio file so the flow works in Simulator/UI tests.
4. **Playback** (`PlaybackController`): AVPlayer/AVAudioPlayer, rate, seek, skip,
   progress persistence, Now Playing + remote commands, audio session handoff with capture.
5. **Import**: `importAudio(from:title:)` — security-scoped copy, duration probe, checksum.
6. **Transcription adapter**: protocol + `SpeechAnalyzer`/`SpeechTranscriber` (iOS 26)
   implementation with runtime availability (locale `en_US`, asset installation via
   `AssetInventory`; expose needsDownload and add `func prepareSpeechAssets() async throws`
   to the store if needed). File-based transcription of the original asset into
   `TranscriptSegment`s with times and confidence. If unavailable → `.unavailable(reason)`.
   Never fall back to a server. Must compile against the Xcode 26.6 SDK; guard all calls.
7. **Insights adapter**: protocol + Foundation Models implementation (`SystemLanguageModel`
   availability; `@Generable` structured output; bounded transcript chunks that fit the
   4,096-token context; every takeaway/outline item cites segment indexes; validate and
   drop invalid citations; flag low evidence; no quotation marks around paraphrase).
   Extractive fallback when the model is unavailable (verbatim segment excerpts, marked
   moments weighted higher), generator "Extractive — no model".
8. **Sample pipeline**: `scripts/build-samples.py` per the contract (Kokoro via
   `~/Documents/GitHub/redwall/Tools/voice/.venv/bin/python` with `KPipeline(lang_code='a')`,
   read-only use of that venv; fallback `say`; ffmpeg/afconvert available). Claude is writing
   `Fixtures/sample-sermons.source.json` concurrently — if it is not there yet, build and test
   the pipeline against a tiny fixture of your own under `Packages/SermonSetCore/Tests/`, finish
   other work, and check back for the real file (it will appear within ~30 minutes). Run the
   pipeline on the real file and commit-ready the outputs into the package resources. Keep the
   bundle small (64 kbps mono AAC). The loader maps samples into Sermon/AudioAsset(kind .sample)/
   Transcript/SermonInsights(generator "Sample fixture")/moments/notes; samples are
   `isSample = true`, `rightsState` as given.
9. **Tests** (Swift Testing): store round-trip & corruption preservation, idempotent keep/pack/
   createCard, trade preview keeps history/notes/moments, capture manifest recovery with the
   simulated engine, segment finalization, evidence-range validation, extractive fallback when
   model unavailable, no-invented-quote guard, export excludes audio and includes notes,
   backup flag toggling, deterministic Sunday Pack.

## Build & test rules

- Use only simulator `32502FB1-1CBE-4555-B1FE-CF1712B1A45C` ("SermonSet Core (Codex)",
  iPhone 17 Pro, iOS 26.5). Claude uses a different one — never touch, erase, or shut down
  other simulators.
- DerivedData: `build/DerivedData-core` only.
- Provide `scripts/dev.sh` with subcommands: `generate`, `build`, `test`, `run [launch args…]`
  (build, install, launch on a simulator), `screenshot <png>`; each honoring `SIM_UDID` and
  `DERIVED_DATA` env vars (Claude will run it with its own values).
- Claude's UI files will change while you work and may briefly not compile. Your gate is: the
  `SermonSetCore` package builds and its tests pass on the simulator. Also try the full app
  build; if it fails only because of UI files, note it and move on — do not edit UI files.
- Record exact commands and outcomes in `docs/REVIEW.md`. Simulator results are not device
  evidence — say so. Never claim a check passed that you did not run.
- Do not commit, push, or create branches. Do not modify anything outside this repo except
  build products under `build/`.

## Finish

End with a concise summary: what works, exact public API deviations from the contract,
test results, how to run (`scripts/dev.sh …`), known gaps/risks.
