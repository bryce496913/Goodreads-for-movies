# Personal Home and Profile

Home and the anonymous local Profile read the same immutable `DashboardSnapshot`. They do not call a provider or analytics service. Posters read the existing OS response cache only; absent artwork gets the existing accessible row placeholder. Opening a detail/season destination reuses its existing cached-first screen and may refresh metadata through the existing service. No account or recommendations are introduced.

## Definitions

All title identities include media kind and the opaque provider-qualified value. Movie `tmdb:42`, TV `tmdb:42`, and movie `other:42` remain distinct. UUIDs identify diary/review records.

| Display | Definition |
| --- | --- |
| Unique movies watched | Union of movie identities currently marked Watched and movie diary events with a past/today watched date or an unknown watched date. A future-dated event alone does not count. Rewatches count once here. |
| Series with watched episode progress | Distinct TV identities with at least one currently watched episode flag, including specials and retained flags. Series-level Watched status alone creates no episode history. |
| Unique episodes marked watched | Distinct stable EpisodeIDs currently marked watched, including specials and retained unknown/future-date flags. Unmarking removes the episode from this count; this is not an aired-episode percentage. |
| Watchlist / favorites | Distinct library title identities with the exact Watchlist status / independent favorite flag. Favorites count at any status. |
| Personally rated titles | Valid current title ratings, using canonical integer half-stars first, then exact compatible legacy values. Nil and legacy zero are unrated. Invalid values are excluded and reported. |
| Average personal rating | Sum of valid half-star units divided by valid title count and by two; arithmetic mean, displayed to one decimal. Unrated titles are excluded. No valid ratings means unavailable, never zero. |
| Written reviews | Distinct nonempty saved review UUIDs plus nonempty retained legacy review fields. Reads never import, mutate or delete text. Separate saved reviews for the same title remain separate records. |
| Recorded viewing events | Distinct saved event UUIDs, including repeats and undated events. This counts events, not additional unique titles or inferred rewatches. |

Corrupt duplicate library identities use the most recently updated row, then ascending UUID for an exact tie. Duplicate/invalid/unrecognized title counts are surfaced without merging or deleting records. Repeated event/review UUIDs cannot inflate counts. LibraryStore remains the sole writer and rejects ambiguous identity mutations.

## Home and chronology

- **Continue Watching:** at least one watched TV episode flag and unfinished known aired regular episodes, or incomplete saved coverage. Specials are excluded from this section’s aired progress. Next means the first unwatched known-aired episode ordered by season, episode, provider ID, and is shown only with complete regular-season coverage and no undated unwatched episodes. Future episodes are never suggested. If only future episodes remain and known coverage is complete, the series is omitted. When uncertain, show available progress and the last *marked watched* episode, not an invented watch date or next episode. The existing season page is available from a confirmed next episode; the series detail link is always available. Percentages use the existing aired-episode calculation. Lists are ordered by last known mark timestamp, then typed media identity, limited to five.
- **Recently Watched:** up to five dated diary events, newest watched date first, excluding future dates. Undated events remain in History/Profile, not falsely labeled as recent actual watches. Ties use recorded date then UUID. Logging a 2020 watch today does not promote it ahead of a 2025 watch.
- **Watchlist:** five newest saved Watchlist titles by original added date, ties by typed identity. Open Library resets filters and selects the existing Library tab; its current sort is retained. Search shortcut selects the existing Search tab.
- **Recent Personal Activity:** eight latest persisted recording actions: event `recordedAt`, review `editedAt` (including explicitly labeled imports), or rating-specific `ratingUpdatedAt`. Ties use stable activity ID. Watch date is shown separately. Review activity represents the latest saved revision, not an invented edit history. Rating removal can be shown while its library row remains. Status/favorite/metadata timestamps never imply a rating action. There is no fabricated historical activity log.
- **Profile diary:** up to five events using the existing diary policy: watched date, falling back to recorded date only when unknown. Unknown dates are explicitly labeled. Full History retains editing/deletion and existing typed detail routing.

## Persistence and migration

The sole schema addition is optional `StoredLibraryEntry.ratingUpdatedAt` with nil default. LibraryStore sets it only when an explicit personal rating value changes, including clearing. Repeating the same rating, changing status/favorite, or refreshing metadata does not advance it. Existing valid legacy ratings still count but have no inferred activity timestamp. No backfill, store reset, deletion, new model, or destructive migration occurs.

This relies on SwiftData’s additive optional-field migration. The new current-schema reopen test does **not** prove migration from an installed pre-011 schema. On macOS, open a copy of an existing pre-011 library and verify counts, ratings, reviews, events and episode flags; existing ratings must retain nil rating timestamps until changed. Never replace the actual user store to test migration.

## Refresh and performance

Root retains one DashboardModel for both tabs. A successful LibraryStore revision triggers one scalar/COW input copy on the main actor. JSON decoding, identity grouping, arithmetic and sorting run in a detached user-initiated task on immutable Sendable values, never on SwiftData models or contexts. Cancellation plus a generation token prevents stale work from publishing. Same revision/UTC day skips input capture and recomputation. Foregrounding rechecks the UTC day so aired eligibility can advance without a write. Cancellation retains the last consistent snapshot. Read failures show a visible warning and retry rather than fresh-looking zero counts.

Aggregation groups progress by series once, and decodes each cached season during background work. Work is approximately O(records + episode metadata + sorting), with O(records + metadata) snapshot memory. Section sizes are bounded to five/eight. LibraryStore’s existing revision/reload mechanism is unchanged; the dashboard adds no fetches on tab switches or redraws. Capturing scalar snapshots still scales with store size on main actor and must be profiled for much larger libraries.

`DashboardTests` creates 100 movies, 50 series, 1,000 watched episode flags, 50 additional unwatched aired episodes, 30 ratings and eight diary events. It checks expected counts and section limits and includes an XCTest `measure` case. The fixture lives in the unit-test target. UI dataset definitions live in `DashboardUITests`; a generic DEBUG importer accepts full JSON values only with both UI-test flags and an isolated in-memory store, and refuses the persistent UI-test-store path. Normal launches have no seed path or dataset. No production analytics dependency exists.

**Performance findings:** grouping/revision caching and background decoding are verified by source inspection only. No runtime timings, memory measurements or responsiveness results are available in Linux; the performance test has not run. No threshold or speed claim is made.

## Validation and screenshots

Cloud checks on 2026-11-01: project parses, all file references resolve, source membership in all three targets is complete, Swift grammar parses for 89 Swift files, asset JSON parses, and `git diff --check` passes. These are not compilation/type checking. There are 24 new aggregation/persistence/model tests and four new dashboard UI tests; repository total is 187 test methods. **All XCTest, iOS builds, migration runs, simulator runs and accessibility checks remain unrun here.** Xcode version and simulator destinations verified: none; neither Xcode, Swift nor Apple SDKs are installed. No GitHub Xcode CI was added.

Run locally with an installed simulator UUID (substitute a dedicated local result path):

```sh
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -only-testing:MovieTrackerTests/DashboardTests \
  -only-testing:MovieTrackerUITests/DashboardUITests \
  -resultBundlePath /tmp/MovieTrackerDashboard.xcresult CODE_SIGNING_ALLOWED=NO
```

Then run the full shared scheme using the README command to check earlier navigation/library features. Record Xcode version, compact and large installed simulator destinations, XCTest output and measured performance locally. Inspect light/dark modes, largest accessibility text size, VoiceOver statistic labels, long title wrapping, back navigation, tab preservation, offline cold launch, foreground refresh, and immediate updates after rating/review/diary/status/episode changes. Confirm no provider calls originate from dashboard aggregation and no fake content appears in normal launches.

The UI suite keeps screenshot attachments named `Home-empty`, `Profile-empty`, `Home-populated`, and `Profile-populated` in its xcresult. Profile images capture the currently scrolled portion; capture additional screenfuls manually for the full list and accessibility sizes. **Actual screenshots are unavailable in this environment and have not been fabricated.** Attach exported simulator images to the PR after the local run.
