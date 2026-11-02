# Personal data export and restore — pass 018

## Export

Open **Profile → Settings → Export or Restore Personal Data → Export My Data**. The app captures local personal values, validates and encodes a complete JSON buffer, decodes it again for verification, then opens the native document exporter. Choose where to save it and wait for the success message. Canceling the picker does not report failure or alter saved data. A failed preparation is never offered as a complete backup, and an empty exporter document cannot be written.

This is a **manual export**, not automatic backup. The app does not upload to a server or integrate a third-party backup service. Native Files destinations can include providers you choose; their storage/network behavior is controlled by that provider. For offline export, choose a local destination. Keep a separate copy outside the app's container before deleting the app. A file saved inside an app-owned Documents folder may also disappear with that app. No automatic recovery after deletion is promised.

## Restore and confirmation

Choose **Restore from Backup**, select an available `.json` file in the native picker, and wait for full parsing/validation. A cloud-only file may need downloading through its Files provider; locally available files work offline. A restore preview shows new Library/review/viewing/progress/season-anchor counts, the number of kept/skipped records, and conflict reasons without showing review text. The first 50 reasons are displayed with the total count; all conflicts use the same rule.

Choose **Confirm Merge — Keep Existing Data** to acknowledge that rule and save, or **Cancel** to make no changes. There is no replace-all or overwrite mode. A success message appears only after the single persistence save returns. If anything changes the store revision while preparing or reviewing the preview—including maintenance—confirmation rejects the stale plan. Select the file again for a fresh preview; it never silently applies a different merge from the one reviewed.

## Data inventory

| Included personal values | Excluded values |
| --- | --- |
| Library record UUID and exact MediaID; membership is presence of that record | Provider titles, synopsis, genres, release dates, runtime, cast, series status/counts |
| Optional Watchlist/Watching/Watched status, independent favorite flag | Posters/backdrops, artwork references/URLs, downloads and caches |
| Validated integer half-star units, rating update timestamp | Metadata receipts/backoff, provider configuration and raw JSON snapshots |
| Retained legacy review/note column, added/updated timestamps | TMDB credentials, Keychain contents, authentication headers |
| Review UUID, exact MediaID, private text, created/edited timestamps, event association and legacy-import flag | Device/advertising identifiers, analytics, navigation preferences |
| Viewing-event UUID, exact MediaID, optional watched date, recorded/updated timestamps; every repeat watch remains separate | SQLite files/journals, SwiftData internal identifiers/schema representations |
| Episode-progress UUID, typed provider episode identity, structural season number, watched flag and optional marked date | Provider episode title/number, overview, runtime and air date |
| Minimal UUID/typed series ID/number season anchors needed to navigate personal episode progress | Pure season/episode cache bodies with no personal progress |

There is no separate viewing-event notes column in the current model. The existing legacy review/note and written review text are preserved, not invented or reinterpreted. Reviews/events remain valid without a Library parent; removing a Library row before export does not discard those standalone histories. A rating without a viewing status remains independent after restore. Imported legacy/unknown namespaces also retain identifier-only detail actions when no metadata adapter is available. Movie and TV IDs sharing a provider number remain distinct.

The format is separate from `PersonalDataArchive` / `PersonalData.json` generated internally during migration-backup maintenance. Those internal recovery files are **not public version-1 backups** and are rejected by this importer. Their permissive historical recovery behavior was left unchanged. No SwiftData schema migration is required.

## Version 1 format

Supported import/export version: **1**. Envelope fields:

| Field | Requirement |
| --- | --- |
| `format` | Required string `MovieTracker.personal-backup` |
| `version` | Required integer `1`; another version is rejected before decoding its records |
| `dateEncoding` | Required string `secondsSince2001-01-01T00:00:00Z` |
| `exportedAt` | Required finite numeric timestamp in that encoding |
| `applicationVersion` | Optional application short-version string; not a device identifier |
| `library`, `reviews`, `viewings`, `episodeProgress`, `seasonAnchors` | Required arrays, including for an empty backup |

Dates are **Double seconds since 2001-01-01 00:00:00 UTC**, the explicit reference epoch used by Foundation Date Codable. This documented numeric representation avoids losing fractional timestamps through a second-only ISO 8601 formatter. It requires no Apple API to read: Unix seconds = encoded seconds + 978307200. Absent optional dates remain absent/nil; no watch date is synthesized from a recorded date. Arrays sort by record UUID and object keys sort lexically for repeatable encoding of the same snapshot/timestamp. Export timestamp changes naturally between exports.

An empty example (timestamp is an example, not runtime evidence):

```json
{
  "format": "MovieTracker.personal-backup",
  "version": 1,
  "dateEncoding": "secondsSince2001-01-01T00:00:00Z",
  "exportedAt": 788918400.1234567,
  "applicationVersion": "0.5.0",
  "library": [],
  "reviews": [],
  "viewings": [],
  "episodeProgress": [],
  "seasonAnchors": []
}
```

Identifiers use `{ "kind": "movie" | "tvShow", "value": "tmdb:72" }`. Provider namespace-qualified values remain opaque and unchanged; different namespaces/media kinds are different identities. Existing nonempty legacy opaque values are preserved without guessing a missing provider namespace. Episode identities use `{ "seriesID": <TV MediaID>, "providerValue": "tmdb:episode:1" }`. UUIDs use standard JSON strings.

Per-record required fields:

- Library: `id`, `mediaID`, `favorite`, `addedAt`, `updatedAt`. Optional `status` (`watchlist`, `watching`, `watched`; nil means no status), `ratingHalfStarUnits` (1…10; nil means unrated), `ratingUpdatedAt`, `legacyReview`. Watching is accepted only for TV.
- Review: `id`, `mediaID`, nonblank `text`, `createdAt`, `editedAt`, `isLegacyImport`; optional `viewingEventID`.
- Viewing: `id`, `mediaID`, `recordedAt`, `updatedAt`; optional `watchedDate`.
- Progress: `id`, `episodeID`, nonnegative `seasonNumber`, `isWatched`; optional `watchedAt` (must be absent for an unwatched flag; a watched flag may have an unknown marked date).
- Season anchor: `id`, TV `seriesID`, nonnegative `number`. Every progress record needs a matching series/season anchor. Missing historical cached seasons get a deterministic minimal anchor using the first associated progress UUID; no metadata is fabricated.

Valid legacy star values are exported as exact half-star units; legacy zero becomes unrated. Invalid existing ratings, identities or integrity conflicts block export/restore preparation instead of silently omitting personal data or clamping it. The public format does not preserve invalid legacy floating-point encodings; the existing internal recovery mechanism remains separate.

The application-version string is informational; compatibility is controlled by the export format version. Unknown extra fields in a version-1 file are ignored by the decoder and never imported/re-exported as metadata or credentials. Required known fields and relationships still validate. Unknown versions are rejected with a version-specific message; there is no best-effort future-schema conversion. Future changes must explicitly version and test the format. No other app's JSON or raw database is supported.

## Non-destructive merge rules

| Incoming record | Match / deterministic result |
| --- | --- |
| Library title | Exact MediaID. Keep the entire local row, including a nil rating/status; do not fill/replace fields or change its UUID/dates. New titles use incoming UUIDs. |
| Review | Stable review UUID. Existing text/identity/dates/association stay unchanged. A missing UUID is added only if its event link remains valid and unclaimed in the merged state. |
| Viewing event | Stable event UUID. Keep existing identity/watched/recorded/updated dates; different UUIDs represent distinct repeat watches even for the same title/date. |
| Episode progress | Exact typed series/provider episode ID. Keep existing flag, marked date, structural season and local UUID even if the incoming record is newer. |
| Season anchor | Series ID + season number. Reuse existing anchor/cache without replacing metadata. Add missing anchors only for newly added progress. |
| UUID used by a different local title/episode/season identity | Skip the incoming row/dependent progress with an explicit conflict reason; never let uniqueness upsert replace the local record. |
| Incoming review linked to a locally conflicting event or an already-linked event | Skip the entire incoming review and explain why; do not silently detach or reassign it. |

Exact duplicates are kept without a conflict reason; differing matched personal values produce a conflict reason. Reimporting the same backup adds nothing after a successful import. `Keep Existing Data` is the only strategy in this pass. If the user wants different local values, cancel and edit explicitly; no replace option is implied. Summary counts include minimal structural anchors separately from Library membership. Deliberately skipped conflicts are distinct from a failed/partial transaction.

## Validation, isolation and transaction safety

Import reads a security-scoped selected URL in bounded chunks, decodes the entire supported envelope, validates all records and relationships, then constructs the complete plan against a captured local revision. Limits are **32 MiB JSON**, **100,000 combined records/anchors**, **1 MiB per written review**, and **1,024 UTF-8 bytes per opaque ID**. Export uses the same limits so it does not offer a file this importer cannot read. Working local snapshots must also be valid and within the record limit. These are resource bounds, not measured performance thresholds. Oversized, malformed, duplicate-identity, missing-ID, invalid-rating, nonfinite-date and dangling/cross-media/duplicate-review-link inputs are rejected before mutation. No private decoder paths or review text are included in error messages/logs.

ModelContext and SwiftData objects remain on the main actor. Main-actor capture copies personal scalars; detached workers encode/decode/validate/plan Sendable values. Cancellation/generation checks prevent obsolete prepared work from being presented. Confirmation rechecks the local revision, then calls the shared `LibraryStore.writeTransaction` with no suspension points inside it. The dedicated context has autosave disabled. All planned inserts and the full integrity audit precede **one explicit save**, with no intermediate per-record saves. A thrown operation/save rolls back and reloads committed state, including indexes; success is reported after save returns. Existing provider-expiry maintenance can still remove expired metadata during that transaction; it does not replace existing personal fields.

This uses the existing single local persistent store/context save boundary, not a claimed distributed transaction. Native failure injection and disk-store tests are authored but **unrun** here; power-loss/device filesystem behavior has not been tested. Concurrent external writers remain unsupported: an external import/context must complete and explicitly reload before further LibraryStore operations, as established in pass 016. Large confirmed imports still perform serial model construction, audit and save on the main actor; maximum-size responsiveness has not been benchmarked.

## Metadata, privacy and limitations

Restored personal records contain no provider bodies or artwork and remain accessible offline via identifier placeholders. Stable IDs allow the existing authorized, context-driven metadata refresh later; import does not fetch metadata or invent cached season coverage, episode completion, release dates or viewing dates. Existing 30/150-day policy and artwork restrictions remain unchanged. No provider content is made permanent in a backup.

Backups are **plain JSON, not encrypted**. They contain private text and viewing dates. Protect files, choose destinations carefully, and share only intentionally. The app emits no backup/review-content diagnostics and uses no automatic remote upload. Encoding is verified in memory before presenting the native exporter; file delivery uses the OS document mechanism and its success/failure result. This is not a guarantee against interrupted storage or a provider misreporting completion. Keep separate copies and verify that an exported file can be selected and previewed. There is no password, automatic schedule, automatic cloud backup or automatic app-deletion recovery.

## Tests and execution evidence

Added **34 unit methods**: 20 BackupRestoreTests and 14 BackupValidationTests, plus deterministic test fixtures. Cases include empty/populated/deterministic JSON export, fractional dates, personal-only contents, complete round trip, repeated import, status/rating/favorite/episode conflicts, review/date preservation, repeat watches, UUID/event/season collisions, missing/invalid/duplicate identifiers, invalid relationships/ratings/text/dates, malformed/foreign/unsupported files, size bounds, cancellation, unknown-field exclusion, invalid local legacy ratings, model preview/cancel/confirm, offline generation/import, and picker cancellation.

Temporary disk-backed regressions cover successful restore/reopen and injected save failure after staging every entity, asserting existing records survive and no inserted review/event/progress persists. No test touches real application user storage. The old internal archive tests remain separate.

**All XCTest remains UNRUN** on the Linux worker without Swift/Apple frameworks. Repository inventory: **338 methods, 298 unit-target (including existing benchmarks), 40 UI**. Passed static validation: project parsing/reference resolution/source membership across three targets; Swift grammar parsing of 131 files (not type checking/macros); resource metadata/privacy parsing; documentation links and whitespace. No Xcode/device builds, simulator/signing checks, or GitHub Xcode CI were run/added.

Locally run BackupRestoreTests and BackupValidationTests plus existing LibraryStore, diary/rating/progress, disk-integrity and migration regressions. Manually verify native Files export/import in Settings, cancel both pickers and preview, inspect a personal-only JSON backup, acknowledge conflicts, change local data while previewing, restore into an empty test installation offline, and reopen after termination. Verify Dynamic Type/VoiceOver and error/success feedback. Native picker lifecycle, actual device persistence and max-size responsiveness remain unverified.
