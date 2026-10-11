# Brand (decided 2026-10-05 by the owner)

- **Name:** SOWER
- **Tagline:** Hear it. Keep it. Pass it on.
- **Meaning:** the parable of the sower (Luke 8:15): those who hear the word, hold it fast, and bear fruit.
  Cards are seeds you pass on; trading is a recommendation; the library is what took root.
- **Principle line (unchanged):** Trade the card. Keep the message.
- **iOS:** display name `SOWER`, bundle id `com.gazhenko.sower`, URL scheme `sower://`
- **Server/web:** one host, `https://sower.gazhenko.dev` (API under `/v1`, share pages `/s/<id>`, offers `/t/<token>`,
  church portal `/church`, moderation `/moderate`). Worker name `sower`, D1 `sower-db`, R2 `sower-audio`, `sower-images`.
- Codename `sermonset` remains in Swift module/package names (`SermonSetCore`) to avoid churn; no user-visible
  string may say SermonSet.
