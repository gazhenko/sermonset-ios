# SermonSet prototype — four looks

A working native SwiftUI prototype of SermonSet (iOS 26, Swift 6) with one shared engine and
four complete visual directions. Built on branch `prototype/four-looks`.

- **Backend** (`Packages/SermonSetCore`, `project.yml`, `scripts/`, Info.plist): written by Codex
  (gpt-6.1-sol, xhigh) against [CORE-CONTRACT.md](./CORE-CONTRACT.md). Notes: [CORE-NOTES.md](./CORE-NOTES.md).
- **Everything a person sees or touches** (`SermonSet/App`, `Looks`, `Components`, `Features`,
  `Resources`, app icons, all copy, the sample sermon content, UI tests): written by Claude.

## Run it

```sh
cd ~/Documents/GitHub/sermonset-ios
xcodegen generate
open SermonSet.xcodeproj          # Run the SermonSet scheme on an iPhone 17 Pro simulator
```

Or from the command line (`scripts/dev.sh` honors `SIM_UDID` and `DERIVED_DATA`):

```sh
SIM_UDID=<simulator> scripts/dev.sh run                       # first launch: onboarding + empty library
SIM_UDID=<simulator> scripts/dev.sh run -SermonSetPreviewData # samples, cards, moments preloaded
```

Useful launch arguments:

| Argument | Effect |
| --- | --- |
| `-SermonSetLook riso\|rubric\|vespers\|lumen` | Start in a look (also switchable in Settings and onboarding) |
| `-SermonSetPreviewData` | In-memory store with all eight samples, two cards, sample moments and notes |
| `-SermonSetSimulatedCapture` | Simulated microphone (Simulator-friendly; real capture uses AVAudioEngine) |
| `-SermonSetUITest` | Isolated on-disk store for tests |
| `-SermonSetScreen sermon\|transcript\|record\|recording\|discover\|pack\|binder\|atlas\|card\|settings\|onboarding\|playing` | Open a screen directly for review |
| `-SermonSetLookLab [back]` | Card lab: every look's card side by side |

## The four looks

Each look is a complete identity — palette, type, shape, chrome, card art, record screen,
level meter, rows, and app icon — grounded in something from the sermon's own world. The
information architecture and behavior are identical across all four.

| Look | Grounding | Type | Palette | Signature moments |
| --- | --- | --- | --- | --- |
| **Riso** | Risograph church zine / gig poster (the documented card direction) | Futura Condensed ExtraBold + Avenir Next | Cream stock, ink, acid lime, ultraviolet, coral, cobalt | Misregistered overprint titles, halftone suns, hard ink offsets, torn-paper card backs, halftone level meter |
| **Rubric** | Liturgical book: rubrication, verse numbers, ribbons | Iowan Old Style, small caps | Bible-paper white, iron-gall ink, rubric red, gilt; card colors from the liturgical calendar | Illuminated initials, marginal timestamps, ribbon bookmarks for moments, dotted-leader table of contents, seismograph meter |
| **Vespers** | Evening prayer in a dark sanctuary — built to be quiet in a pew | Optima | Night blue, parchment, candle amber, gold foil | Gold arched-window line art, foil that moves with tilt, a candle-glow level meter, dim-screen option |
| **Lumen** | Stained glass meets iOS 26 Liquid Glass | SF Pro Expanded | Leaded jewel glass: cobalt, ruby, amber, emerald, violet | A lit window behind real Liquid Glass chrome, Voronoi glass-pane card art, jewel level bars |

## What works

- First-run onboarding (promises → choose a look → start: record, import, samples, or empty).
- **Record**: consent check, optional details, private-on-device label, large timer, live level
  meter, *Mark this moment*, timestamped notes, pause/resume, hide-and-keep-recording pill,
  stop → saved → open sermon. Recovery banner for interrupted sessions.
- **Library**: per-look hero ("pick up where you left off"), search, source filters, rows.
- **Sermon**: per-look header, player with moments on the scrubber, speed, ±15/30, mark at the
  current time; moments; evidence-linked takeaways (keep / edit / set aside, "Hear it at 0:48");
  outline; scripture; transcript preview and full transcript with follow-along and low-confidence
  marking; private notes (optionally timestamped); card; trust and rights explanations; edit sheet.
- **Discover**: free weekly Sunday Pack (tear or tap to open, reveal one by one, reveal all, skip,
  keep all) and the eight sample sermons with a preview sheet.
- **Collection**: Binder grid, interactive 3D card viewer (tilt, flip, share image, listen,
  practice-a-trade that removes the card but keeps the sermon), and the library-driven Atlas
  (city-level pins, place list, unknown/private bucket).
- **Settings**: look picker with live previews, matching app icons, backup choice (iPhone backup by
  default; iCloud Drive / Google Drive / Dropbox listed as coming later per the owner's decision),
  on-device capability status, sample management, export, erase.
- Mini player with lock-screen controls (core), Reduce Motion fallbacks, VoiceOver labels.

## Honest limits

- Simulator only. No physical-iPhone recording, battery, thermal, or long-duration evidence yet.
- Trading is a local preview; there is no backend, account, or real exchange.
- Sunday Pack is a deterministic demo of fictional samples, not production issuance.
- Sample people, churches, and sermons are fictional; sample audio is synthesized narration.
- Transcription and takeaway drafting depend on on-device Apple capabilities and report when
  they are unavailable; nothing falls back to a server.

## UI verification (Claude, 2026-10-05)

All on the iOS 26.5 Simulator (iPhone 17 Pro, Xcode 26.6). None of this is physical-iPhone evidence.

- Clean build of the app target: no warnings in UI code.
- `SermonSetUITests` (5 journeys, all passing):
  ```sh
  xcodebuild -project SermonSet.xcodeproj -scheme SermonSet \
    -destination "platform=iOS Simulator,name=<iPhone 17 Pro simulator>" \
    -only-testing:SermonSetUITests test
  ```
  1. Empty library → consent check gates Record → simulated recording → two marked moments → timestamped
     note → stop and save → open sermon shows both moments → relaunch keeps everything.
  2. Explore with samples → Sunday Pack (tear, reveal, reveal all, keep all) → binder → practice a trade →
     the card leaves the binder and the library count is unchanged.
  3. Recording killed mid-sermon → relaunch offers recovery → the recovered audio (with its marked
     moment) becomes a sermon.
  4. First run: onboarding → choose a look → Record a sermon opens the recorder.
  5. The library renders in all four looks.
- Every screen screenshotted in all four looks, plus Dynamic Type at AX extra-extra-extra-large
  (tab bars cap their type and offer the Large Content Viewer; heroes stack vertically).
- An independent review of the UI code found 12 issues (failed-save lockout, mic permission refresh,
  errors hidden behind modals, empty-pack crash, misleading location label, and others); all were fixed,
  with two backend parts handed to Codex.
- VoiceOver structure: hidden tabs are removed from the hierarchy; controls drawn in capitals or small
  caps keep natural-case labels; decorative misregistration copies are hidden.
- On-device AI: in the Simulator, Apple Foundation Models (on-device) drafted three takeaways and an
  outline from a sample transcript, each linked to a playable time, with one flagged as a weak match.
- On-device speech: `SpeechTranscriber` reports unavailable in the Simulator; the app says so and hides
  the action. Live transcription still needs a real iPhone.
