# SOWER

**Hear it. Keep it. Pass it on.**

A free, private iPhone app for the sermon you just heard. Record it from your seat, come back to the
moments that landed, and pass on a card that points back to the message. Native Swift and SwiftUI
for iOS 26, with an optional community backed by a Cloudflare Worker.

**Website:** [gazhenko.dev/sower](https://gazhenko.dev/sower/) ·
**Church portal:** [sower.gazhenko.dev/church](https://sower.gazhenko.dev/church)

<p align="center"><a href="https://gazhenko.dev/sower/#trailer"><img src="docs/media/teaser.gif" alt="SOWER teaser: a card tilting and turning over, a Sunday Pack being opened, and the app switching between its four looks. Click for the full trailer." width="760"></a></p>

The trailer is filmed from the running app in the iOS Simulator by a scripted UI test and printed in
the website’s one-ink style. It’s silent. The churches and sermons shown are fictional samples.

## What it does

**Hear it.** One big button to record and another to mark the moment something lands. Audio is
saved in durable pieces, so a phone call or a crash can't take the sermon. A church's service QR
code tells you whether recording and sharing are welcome. Voice Focus makes a cleaner copy and
trims to just the sermon; the original is never changed.

**Keep it.** When you stop recording, Apple Intelligence writes the big idea and a short summary on the
iPhone, with takeaways and a question to reflect on; every sentence plays the exact words it came from.
Moments on the timeline, private notes, and an on-device transcript you can correct, made by Parakeet (NVIDIA's
open-source recognizer, with speaker labels) or Apple's built-in recognizer. On far-field room audio Parakeet made
36% fewer errors than Apple's recognizer and beat Whisper large-v3-turbo ([evaluation](docs/build/ASR-EVALUATION.md)). Back up the whole
library to iCloud Drive, Google Drive, or Dropbox through Files, optionally encrypted.

**Pass it on.** Every sermon becomes a card. With a community account (a key on your iPhone, no
email), you can keep sermons churches and listeners shared, open a real Sunday Pack each week,
share your own recordings with the church's permission, and give or swap numbered cards by QR
code, nearby, or link. Trading moves the card; the sermon, your notes, and your moments stay put.

**For churches.** A web portal to claim the church, print service QR codes, review recordings
before anything goes public, publish official audio, and remove audio at any time. Moderators
have their own console with reports, appeals, and an audit log.

## Six looks

SOWER's own look, printed in one violet ink like the website, plus five other complete visual
directions with matching app icons. Screens and behavior are identical in each.

![The Library screen in the SOWER, Riso, Rubric, Vespers, Lumen, and Midnight looks](docs/media/looks-library.jpg)

| Look | Built from |
| --- | --- |
| **SOWER** | The house style and the default: one violet ink on paper, tall compressed Big Shoulders Display, Mona Sans in wide capitals, hairline rules, and card art printed with an ordered dither. |
| **Riso** | A two-ink church zine: condensed poster type, riso inks on cream stock, a hard offset like a second print pass. |
| **Rubric** | A well-used Bible: rubric red, timestamps in the margin like verse numbers, ribbons for marked moments. |
| **Vespers** | Evening prayer: night blue and candlelight, dim enough for a dark sanctuary. |
| **Lumen** | A lit stained-glass window behind iOS 26 Liquid Glass. |
| **Midnight** | A terminal at midnight: SF Mono throughout, a shell prompt before every section, a tmux-style tab bar, ASCII-art landscapes, and syntax colors for each kind of sermon. Cards are source files with line numbers and a status line. |

<details>
<summary><b>More screens</b></summary>

![Sermon page in four looks](docs/media/looks-sermon.jpg)
![Live recording in four looks](docs/media/looks-recording.jpg)
![Takeaways in four looks](docs/media/looks-takeaways.jpg)
![Card viewer in four looks](docs/media/looks-card.jpg)
![Sunday Pack in four looks](docs/media/looks-pack.jpg)
![Atlas in four looks](docs/media/looks-atlas.jpg)

</details>

## Privacy

Recordings, transcripts, notes, moments, and drafts never leave the iPhone unless you put them in a
backup you save yourself. Sharing a sermon is explicit and reviewed: you choose the card's details,
your big idea, or trimmed audio, and audio needs the church's permission. Trading never carries
private material. No analytics, ads, or tracking. Full policy:
[privacy](https://gazhenko.dev/sower/privacy.html).

## Status

Runs on the iOS 26.5 Simulator against a local copy of the server. Not yet tested on a physical
iPhone, and not on the App Store (there's no Apple Developer membership yet, so no push,
Sign in with Apple, or universal links; deep links use the `sower://` scheme).

Verification is recorded in [docs/REVIEW.md](docs/REVIEW.md) and
[docs/build/SERVER-NOTES.md](docs/build/SERVER-NOTES.md).

## Run it

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open SermonSet.xcodeproj   # run the SermonSet scheme on an iPhone 17 Pro simulator
```

Launch arguments: `-SermonSetPreviewData` loads the eight fictional sample sermons,
`-SermonSetLook sower|riso|rubric|vespers|lumen|midnight` picks a look, `-SermonSetSimulatedCapture` records
without a microphone, and `-SowerServer http://127.0.0.1:8787` points the app at a local server.

The server: see [server/README.md](server/README.md) to run it locally with seeded fictional
churches, and [docs/api/API.md](docs/api/API.md) for the contract.

Tests: `scripts/dev.sh test` (core), `cd server && npm test` (Worker), and
`xcodebuild … -only-testing:SermonSetUITests test` (UI journeys; set
`TEST_RUNNER_SOWER_SERVER` to include the community journeys).

## Repository

- `SermonSet/` — the SwiftUI app. `Looks/` holds the six visual systems; `Features/Community/`
  the account, Discover, trading, publishing, and inbox screens.
- `Packages/SermonSetCore/` — capture, storage, playback, Voice Focus, on-device AI adapters,
  identity, the community client, publishing queue, trading, and backups, with tests.
- `server/` — the Cloudflare Worker: D1, R2, signed requests, offers, packs, moderation.
- `web/` — the church portal, moderation console, share and offer pages, and print templates.
- `site/` — the GitHub Pages website. `tools/site/` dithers its art from public-domain paintings.
- `SermonSetUITests/` — end-to-end journeys, the design review tour, and the trailer tour.
- `tools/trailer/` — films the app (`record.sh`), renders plates from the site’s CSS (`plates.py`), and
  cuts the silent trailer (`edit.py`, cut points in `edl.json`).

The codename `SermonSet` remains in module and folder names; everything people see says SOWER.
Sample people, churches, sermons, and voices are fictional.
