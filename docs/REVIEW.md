# SermonSetCore prototype review — October 5, 2026

Backend implementation is complete for the assigned prototype boundary. The current core gate passes **37 Swift Testing tests**, the full app builds, and the earlier **2 selected Claude-authored UI journeys passed**. This is Simulator evidence, not physical-iPhone validation. The macOS-host speech attempt below is blocked by missing installed English assets. No commits, pushes, branches, releases, dependency installations, credentials, or application network calls were used.

## Environment and executed commands

Working directory: `/Users/jemmygazhenko/Documents/GitHub/sermonset-ios`.

- `xcodebuild -version`: Xcode 26.6, build 17F113.
- `xcrun --sdk iphonesimulator --show-sdk-version`: 26.5. The installed SDK is not labeled 26.6.
- Destination for every Simulator execution: `platform=iOS Simulator,id=32502FB1-1CBE-4555-B1FE-CF1712B1A45C`, SermonSet Core (Codex), iPhone 17 Pro, iOS 26.5.
- DerivedData: `build/DerivedData-core` only. Other booted simulators were neither operated on nor shut down.

| Exact command | Outcome |
| --- | --- |
| `scripts/dev.sh generate` | Passed; generated SermonSet.xcodeproj with local package, app, independent core checks, package test action, and UI-test target. |
| `scripts/dev.sh test > build/codex/test-first.log 2>&1` | Original run: 23/25 passed. Failed model-availability assumption and Simulator Data Protection expectation. |
| `scripts/dev.sh test > build/codex/test-resume-baseline.log 2>&1` | Resume baseline: reproduced 23/25, exit 65. Original two failures confirmed against the current tree. |
| `scripts/dev.sh test > build/codex/test-platform-fixes.log 2>&1` | 25/26 passed, exit 65. Both original failures fixed; new moment test exposed ISO-8601 whole-second creation-date precision. |
| `scripts/dev.sh test > build/codex/test-complete.log 2>&1` | **30/30 passed**, 3 suites, exit 0, `TEST SUCCEEDED`. Swift Testing execution took 5.758 seconds. Result: `build/logs-core/tests-20261005-011444-85252.xcresult`. |
| `scripts/dev.sh build > build/codex/app-build.log 2>&1` | **Passed**, exit 0, `BUILD SUCCEEDED`. Full current SwiftUI app and core compiled together. |
| `python3 scripts/build-samples.py > build/codex/samples.log 2>&1` | Passed with allowed fallback: requested Kokoro voice assets were absent from the offline cache; installed Samantha generated all 8 samples. No model/package downloads. |
| `python3 scripts/build-samples.py --say > build/codex/samples-final.log 2>&1` | Passed; final sample resources use Samantha at the script's current narration rate. 6,342,936 audio bytes plus JSON, 48 kHz mono AAC at a requested 64 kbps. Current source hash matches generated metadata. |
| `scripts/dev.sh run -SermonSetPreviewData -SermonSetSimulatedCapture > build/codex/preview-run.log 2>&1` | Passed: build, install, and launch on the assigned simulator; launch returned PID 87595. |
| `scripts/dev.sh screenshot build/codex/preview.png > build/codex/preview-screenshot.log 2>&1` | Passed; PNG written under ignored build output. This is startup evidence, not a visual/accessibility sign-off. |

The script expands core checks to the following command (its actual result-bundle path is recorded above and in the log):

```sh
xcodebuild -project SermonSet.xcodeproj -scheme SermonSetCore -configuration Debug \
  -destination 'platform=iOS Simulator,id=32502FB1-1CBE-4555-B1FE-CF1712B1A45C' \
  -derivedDataPath /Users/jemmygazhenko/Documents/GitHub/sermonset-ios/build/DerivedData-core \
  -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -resultBundlePath /Users/jemmygazhenko/Documents/GitHub/sermonset-ios/build/logs-core/tests-20261005-011444-85252.xcresult test
```

Earlier incremental native core builds used this exact command, redirecting respectively to `build/codex/domain-build.log`, `build/codex/capture-build.log`, and `build/codex/adapters-build.log`; all three finished `BUILD SUCCEEDED`. The capture build initially reported converter-closure Sendable warnings; the subsequent adapter and final core builds have no Swift concurrency diagnostics.

```sh
xcodebuild -project SermonSet.xcodeproj -scheme SermonSetCore -configuration Debug \
  -destination 'platform=iOS Simulator,id=32502FB1-1CBE-4555-B1FE-CF1712B1A45C' \
  -derivedDataPath build/DerivedData-core -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build
```

## App journeys and project integration

Executed this exact selection against Claude's UI tests without editing their Swift files:

```sh
xcodebuild -project SermonSet.xcodeproj -scheme SermonSet -configuration Debug \
  -destination 'platform=iOS Simulator,id=32502FB1-1CBE-4555-B1FE-CF1712B1A45C' \
  -derivedDataPath build/DerivedData-core -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO -resultBundlePath build/logs-core/ui-journeys-core.xcresult \
  -only-testing:SermonSetUITests/SermonSetJourneyTests/testRecordMarkNoteStopAndRevisit \
  -only-testing:SermonSetUITests/SermonSetJourneyTests/testEveryLookRendersTheLibrary \
  test > build/codex/ui-journeys.log 2>&1
```

Passed 2/2, exit 0, `TEST SUCCEEDED`:

- `testRecordMarkNoteStopAndRevisit`: 38.311 seconds. Launched with `-SermonSetUITest`, `-SermonSetSimulatedCapture`, and a unique directory; exercised consent UI, recording, two marked moments, note entry, stop/save, revisit, and library persistence across app relaunch. No microphone prompt blocked the journey.
- `testEveryLookRendersTheLibrary`: 26.632 seconds. Preview library rendered under riso, rubric, vespers, and lumen. Screenshots are retained as test attachments in `ui-journeys-core.xcresult`.

The pack/trade **UI** journey was not selected. Its core invariants are covered by Swift Testing. No physical microphone or live AI success is inferred from either UI journey.

`SermonSetUITests` is configured in project.yml and the app Test action alongside the Swift package tests. The independent `SermonSetCore` scheme remains available while UI files change. All three requested alternate-icon asset names are enabled. This inspection passed and showed their entries in the compiled app plist:

```sh
plutil -extract CFBundleIcons json -o - build/DerivedData-core/Build/Products/Debug-iphonesimulator/SermonSet.app/Info.plist
```

## Verified core behavior and platform corrections

Tests exercise atomic store round-trip, preservation/write blocking for corrupt or unknown-schema stores, write-failure rollback, idempotent sample/pack/card keeps, ISO-week pack selection and reload stability, and trade preview retaining history/audio/transcripts/notes/moments. Import copies audio with duration and checksum; deletion removes the copied asset. Export includes private notes and metadata while omitting audio bytes and local audio paths. Backup exclusion flags toggle and persist.

Capture tests use real synthesized AAC files. They check manifest existence, segment finalization, pauses excluding elapsed time, saved annotations referencing the original asset, immutable audio after metadata edits, checksum-verified recovery from a copied session snapshot, rejection of corrupt segments without deleting them, unlisted partial-container handling, dismiss-without-delete, idempotent recovery, injected interruptions/routes/media reset, and capture/playback handoff. The launch-argument combination also has a direct core record → mark → stop test with simulated permission granted.

`updateMoment(_:)` edits only note text, retains original identity/time/audio source/creation time, rejects a mismatched sermon, clears notes with nil, and persists the edited note. Its reload assertions account for version-1 whole-second ISO-8601 date precision while preserving numeric audio timestamps exactly.

Processing tests validate finalized evidence ranges/revisions, low-confidence flags, extractive verbatim output and moment weighting, invalid-citation rejection, invented straight/curly quotations, contraction preservation, bounded Unicode chunks, confidence-sensitive transcript hashing, fallback if a model becomes unavailable during generation, and speech checkpoint retry after relaunch. The original verification compiled the actual Apple adapters and queried availability without invoking inference or asset installation. The follow-up host attempt and Claude's reported model inference are distinguished below.

- `backupFlagAndFileProtectionPersist` continues to check backup flags on Simulator. Its Data Protection expectation runs only on physical iOS (`os(iOS) && !targetEnvironment(simulator)`). Production code still requests `.completeUntilFirstUserAuthentication` on directories, atomic JSON writes, and audio files. **Data Protection is not verifiable on Simulator.** A passing Simulator test does not prove that protection is applied.
- `realCapabilityReportsRemainOnDeviceWithoutInstallingAssets` asserts on-device reporting, zero asset-preparation calls through a probe wrapping the real speech availability check, idle processing jobs, and no processing checkpoint directory. It makes no assumption about model availability on the host and never calls AssetInventory installation. The baseline host reported the Foundation Models model available, which was a valid runtime result rather than a backend failure.

Build/test output includes Apple's benign AppIntents metadata-extraction notices and Simulator audio LoudnessManager/HAL messages. These are preserved in logs; no physical acoustic fidelity is claimed.

## Capture-start cleanup and service-date follow-up

Rechecked the current tree with `git status --short`; the prototype directories remain untracked. Both independently reported bugs were reproduced through the real public methods before applying their fixes. The initial regression run also caught a test-only full-history equality assertion affected by the documented whole-second ISO-8601 date precision; that assertion now checks unchanged history in memory and compares persisted acquisition time within its supported precision.

`CaptureController.start(_:)` failure now cancels its ticker, stops/drains and clears the engine, and ends its own audio-session ownership. If no audio was captured and no segment exists after stopping, it removes the empty session directory and clears the journal; `.failed(error)` remains visible, and the same controller can immediately start again. Captured audio remains protected: finalized segments, including buffered audio finalized during failure cleanup, retain the journal for `stop()` or `discard()`. Captured nonzero duration also preserves the journal if flushing failed. Engine failure callbacks carry their session ID so a delayed callback from the failed engine cannot interrupt a new recording. The public capture initializer is unchanged; engine-factory injection is internal.

Three new capture tests exercise real `SimulatedCaptureEngine` instances and the production AAC writer:

- An empty engine-start failure stops the injected engine once, deletes its session directory, leaves no recovery/library entry, and supports a new record → mark → stop flow on the same controller. A delayed callback from the previous engine leaves the retry recording active.
- Failure while claiming audio-session ownership occurs after the manifest exists and before engine creation. It removes that empty session, retains the other owner's claim, and permits retry after that owner ends capture. This is an injected ownership conflict, not a physical phone-call test.
- Finalized and buffered-before-failure AAC are checked in both save and discard paths. Cleanup flushes the buffered case, preserves checksum-valid audio, rejects a premature new start, supports saving an immutable original or explicit discard, and permits a later start. Saving/discarding does not stop the already-cleared failed engine again.

`SermonStore.updateSermon(_:)` now accepts `serviceDate`. Its new test checks the observable sermon/library entry and a reopened store, rejects caller changes to stored `createdAt`, and retains acquisition history and the canonical audio reference. No public signatures or schema fields changed.

All commands below used the assigned Codex simulator and `build/DerivedData-core`; the script regenerated the Xcode project. No UI, UI-test, or asset-catalog source files were edited. Exact outcomes:

| Exact command | Outcome |
| --- | --- |
| `scripts/dev.sh test > build/codex/test-start-date-before.log 2>&1` | 33/37 passed; the 4 new tests failed with 17 issues, exit 65, `TEST FAILED`. Includes the test-only date-precision assertion described above. Result: `build/logs-core/tests-20261005-015631-93945.xcresult`. |
| `scripts/dev.sh test > build/codex/test-start-date-complete.log 2>&1` | 37/37 passed, 3 suites, 5.895 seconds, exit 0, `TEST SUCCEEDED`, after cleanup/date fixes and the precision-aware assertion. Result: `build/logs-core/tests-20261005-015923-94350.xcresult`. |
| `scripts/dev.sh test > build/codex/test-start-date-stale-callback-before.log 2>&1` | 36/37 passed, 1 issue, exit 65, `TEST FAILED`. Newly injected delayed callback changed the retry's phase to interrupted. Result: `build/logs-core/tests-20261005-020055-94600.xcresult`. |
| `scripts/dev.sh test > build/codex/test-start-date-final.log 2>&1` | **Final: 37/37 passed**, 3 suites, 5.923 seconds, exit 0, `TEST SUCCEEDED`, including the session-bound callback guard. Result: `build/logs-core/tests-20261005-020206-94802.xcresult`. |
| `scripts/dev.sh build > build/codex/app-build-start-date-final.log 2>&1` | **Final: passed**, exit 0, `BUILD SUCCEEDED`. Full app and core compiled together after both fixes and the callback guard. |

The final build/test logs contain no Swift warnings or errors; the benign AppIntents metadata-extraction warning remains. No live microphone, physical call, iPhone Data Protection, or live speech/model inference was exercised in this follow-up. UI journeys were not rerun; the previous UI journey and macOS-host evidence below retain their original scope.

## Quote-handling follow-up and macOS-host speech evidence

Rechecked `git status --short`: the prototype directories and configuration remain untracked in this checkout. The current source already preserved simple `Peter’s` and `don't` cases. Three new regression tests reproduced the remaining quote problems: nested curly single quotes left delimiters behind, a leading U+2019 quote was retained, and the quotation guard missed quoted text spanning a newline. `scripts/dev.sh test > build/codex/test-quotes-before.log 2>&1` ran 33 tests; 31 passed and 2 failed with 3 issues, exit 65. Result: `build/logs-core/tests-20261005-013915-90651.xcresult`.

`EvidenceValidator` now matches nested quotation spans without treating U+2019 or ASCII apostrophes between letters/numbers as delimiters. Paraphrases remove paired and boundary quotation marks while preserving contractions, `Peter’s`, unpaired possessives within a sentence, and internal literal double marks such as `3" nail`. A final isolated probe reproduced the old literal result `Use a 3 nail here.` before removing the blanket double-mark filter; that literal case now has a core regression expectation. The invented-quotation guard checks the original text before stripping, including nested and multiline spans. Tests cover the validator plus actual generated-takeaway validation and the bundled “Breakfast on the Shore” takeaway loader. The model checkpoint's internal prompt/validation version is now `bounded-evidence-v2`, so regeneration does not reuse sanitized v1 chunk outputs. Existing persisted insights and listener edits are not rewritten to guess lost punctuation; preview/sample reload and fresh generation use the corrected validator.

After the quote fix, `scripts/dev.sh test > build/codex/test-quotes-complete.log 2>&1` passed 33/33 in 3 suites, 5.725 seconds, exit 0, `TEST SUCCEEDED`, result `build/logs-core/tests-20261005-014153-91130.xcresult`. `scripts/dev.sh build > build/codex/app-build-quotes.log 2>&1` passed, exit 0, `BUILD SUCCEEDED`. Final commands after the checkpoint-version change are recorded below.

| Exact follow-up command | Outcome |
| --- | --- |
| `scripts/dev.sh test > build/codex/test-quotes-final.log 2>&1` | **33/33 passed**, 3 suites, 5.651 seconds, exit 0, `TEST SUCCEEDED`. Result: `build/logs-core/tests-20261005-014315-91412.xcresult`. |
| `scripts/dev.sh build > build/codex/app-build-quotes-final.log 2>&1` | **Passed**, exit 0, `BUILD SUCCEEDED`. Full app and local package compiled after the quote fix and checkpoint-version change. |
| `scripts/dev.sh test > build/codex/test-quotes-literal-final.log 2>&1` | **Final: 33/33 passed**, 3 suites, 5.770 seconds, exit 0, `TEST SUCCEEDED`. Includes the literal internal double-mark regression. Result: `build/logs-core/tests-20261005-014751-92046.xcresult`. |
| `scripts/dev.sh build > build/codex/app-build-quotes-literal-final.log 2>&1` | **Final: passed**, exit 0, `BUILD SUCCEEDED`. Full app includes the final literal-mark correction and v2 checkpoint invalidation. |

No Swift diagnostics were reported; the app build retained the benign AppIntents metadata-extraction warning. The earlier two UI journeys were not rerun for this backend-only follow-up. No UI or UI-test sources were edited.

Exact isolated literal probe commands, executed before removing the blanket double-mark filter (compilation and process exit 0; printed `literalRetained=false`, reproduced the regression):

```sh
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos26.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path build/codex/speech-host/ModuleCache \
  Packages/SermonSetCore/Sources/SermonSetCore/Domain.swift \
  Packages/SermonSetCore/Sources/SermonSetCore/Evidence.swift \
  build/codex/speech-host/QuoteProbe.swift -o build/codex/speech-host/quote-probe \
  > build/codex/speech-host/quote-compile.log 2>&1
build/codex/speech-host/quote-probe > build/codex/speech-host/quote-before.log
```

**macOS-host evidence only, not iPhone evidence:** macOS 26.4 (25E246), Apple silicon (`arm64`), Apple Swift 6.3.3. A throwaway harness in ignored `build/codex/speech-host/` compiles the unmodified production `Domain.swift` and `SpeechAdapter.swift`, avoiding changes to the package or iOS target. The production adapter was invoked against the bundled `open-hands.m4a`, readable at 48 kHz with 5,045,685 frames and a duration of 105.1184375 seconds.

Exact compilation and attempt commands:

```sh
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos26.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -module-cache-path build/codex/speech-host/ModuleCache \
  Packages/SermonSetCore/Sources/SermonSetCore/Domain.swift \
  Packages/SermonSetCore/Sources/SermonSetCore/SpeechAdapter.swift \
  build/codex/speech-host/Attempt.swift -o build/codex/speech-host/attempt \
  > build/codex/speech-host/compile.log 2>&1
build/codex/speech-host/attempt \
  Packages/SermonSetCore/Sources/SermonSetCore/Resources/Samples/open-hands.m4a \
  > build/codex/speech-host/attempt.log 2>&1
```

Compilation passed, exit 0. The harness exited 0 after reporting a **blocked transcription**, not successful inference:

- `SpeechTranscriber.isAvailable == true`; supported equivalent locale is `en_US`.
- `AssetInventory.status(forModules:) == .supported`, rather than `.installed`; production `capability()` returned `.needsDownload`.
- Production `transcribe(fileURL:startingAt:onSegments:)` threw `SermonSetError(title: "Speech unavailable", message: "On-device English speech assets are unavailable. The recording has been preserved.")` before creating the analyzer.
- **Zero segments produced; timestamp sanity and confidence presence are not verifiable.** The live SpeechAnalyzer result path could not run on this host without installing English assets. No asset reservation, preparation, installation, microphone access, or speech-authorization prompt was invoked. Legacy speech authorization was `.notDetermined` (raw value 0).

This establishes compilation, file readability, and the runtime asset blocker; it does not establish live transcription correctness. The harness and logs remain under ignored build output for inspection.

**Attributed observation from Claude's Simulator UI run, reported in the follow-up:** `generateInsights` using Apple Foundation Models on-device produced three takeaways with valid evidence timestamps, a low-evidence flag, and an outline from the “Breakfast on the Shore” sample transcript. Codex did not independently repeat that inference run. It demonstrates the reported model path on Simulator with a fixture transcript; it does not validate live speech transcription or physical-iPhone inference quality.

## Remaining evidence limits

**Blocked / not executed on physical iPhone:** Data Protection enforcement before/after unlock, actual microphone capture, Bluetooth/USB route quality, real phone-call recovery, lock-screen/background endurance, low-space exhaustion, long-session recovery loss bounds, battery/heat/memory, SpeechAnalyzer accuracy/time alignment, and Foundation Models inference quality. These require an authorized physical-device run; this assignment used the designated simulator and macOS host, without release signing.

The 30-second live segment interval is a nominal recovery design, not a measured crash-proof guarantee. Finalization temporarily needs disk space for both segments and the final original, and AAC concatenation decodes/re-encodes captured segments once. The provided sample text currently narrates to 88–105 seconds; original fixture content was preserved. AI citation validity is tested structurally, not as proof of semantic truth. Draft insights remain reviewable. No cloud fallback, public uploads, real trading, analytics, or enhancement implementation was added.

The ownership boundary was retained: core/package, project generation, scripts, support plist, and backend documentation were edited; Claude's app/views/components/asset catalog/source fixture/UI tests were not edited by Codex. Public additions and operational details are in `docs/prototype/CORE-NOTES.md`.
