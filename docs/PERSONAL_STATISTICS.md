# Personal statistics and Year in Review — Pass 041

## Existing counts remain unchanged

Profile's existing Viewing Statistics and Home still use `DashboardAggregator.aggregate`. Their lifetime definitions remain: distinct movies with Watched status or qualifying diary events (including undated watches); distinct currently watched episode IDs/series; current watchlist/favorite/rating counts and valid personal-rating average; saved review records; and viewing-event records. See `home-profile-dashboard.md`. These are different measures, not interchangeable watch totals.

A new **Profile → Year in Review** destination extends the same aggregator with `personalStatistics`. It performs no network requests, writes, migrations or analytics collection. No accounts, SDKs, remote tracking, new persistence entities or stored aggregate totals are introduced. Existing four-tab navigation and Home/Profile counts are preserved.

## Definitions and provenance

| Display | Source and counting rule |
| --- | --- |
| Movie/series viewing events | Distinct diary event UUIDs with a known, nonfuture watched date in the selected Gregorian year. Movie and TV MediaIDs remain distinct. |
| Unique movies/series logged | Distinct full typed MediaIDs among those eligible events. Three watches of one movie mean three events and one unique movie. |
| Monthly activity | Eligible events grouped by the saved civil month; twelve buckets always exist, including zeros. Movie and series counts remain separate. |
| Months with movie logs | Number of months with at least one eligible movie event. |
| Busiest movie month | Highest movie-event count; earliest month wins a tie. Unavailable when all months are zero. |
| Personal rating distribution | **Current, all-time** saved Library ratings, one canonical row per MediaID, independent of selected year/status. Ten integer half-star buckets (1–10 units, 0.5–5 stars). Valid legacy stars follow PersonalRating's existing exact conversion. Unrated/legacy zero is separate; invalid values are excluded and counted. |
| Genres of logged titles | Unique movie and series IDs in the selected year's eligible diary, associated with valid genre metadata. A title contributes once per genre; rewatches and duplicate genre labels do not increase that count. Multi-genre titles contribute to several categories, so genre counts must not be summed as viewing-event totals. |
| Episodes marked watched this year/month | Unique, currently watched EpisodeIDs with a trustworthy nonfuture marking timestamp in the selected local year/month. Includes specials. These are marking actions, not verified viewing dates or repeat-watch events. |
| Current watched episode flags | All currently watched episode identities regardless of marking-date availability, independent of selected year and metadata availability. Conflicting duplicate identities are excluded explicitly. |

Ratings do **not** have historical value snapshots. `ratingUpdatedAt` says when the current value was edited, not what the rating was in a past year; it is deliberately absent from this input. A rating without a viewing status still contributes to the current all-time distribution. Editing/clearing a rating updates that distribution for any selected year; it never invents a watch.

`StoredEpisodeProgress.watchedAt` records the most recent transition to watched. Unmarking clears it; marking again replaces it. A generic series Watched status, nil timestamp, imported/backfilled unknown date or a single watched flag cannot establish a historical viewing date or rewatch count. We never assign today's date to an unknown record. A preserved timestamp describes a marking action only; original action provenance beyond that field is unavailable. Unknown and invalid/future timestamps are excluded from dated activity and explained separately; personal flags remain included in overall totals. Metadata expiry cannot delete progress through this read-only calculation.

Undated diary records remain in the diary and lifetime Profile counts but are not assigned to a year based on recordedAt. Invalid/unavailable identities and invalid/future dates are counted as exclusions. These coverage counts describe the whole input, not just one year. Future records are omitted from selectable data years until eligible.

## Years and time zones

Year selection starts with the device's current **Gregorian** year. Available years include current year, selected year and years with eligible diary/episode activity, newest first. Retaining the selected year after its final event is removed permits a meaningful empty state instead of jumping elsewhere. Ratings and unknown dates do not create data years.

Diary watched dates are persisted Gregorian UTC **civil dates**, not instants. We read their Gregorian year/month without shifting them into the prior day when the device is west of UTC. Thus a saved January 1 stays January 1 in every time zone, including leap days. The maximum eligible diary date is today's local Gregorian civil day. Episode marking values are actual instants and use the device time zone; a UTC January 1 mark can correctly belong to local December 31. Recorded-at timestamps are never substituted for either kind of watch date. The screen explicitly states these rules and its episode time zone.

## Genre metadata and retention

Only identity-matching, decodable local Movie/TV snapshots are eligible. Consider selected-year event snapshots and the canonical Library snapshot, choosing the newest usable receipt for each title. Missing data, missing genre names/IDs, expired metadata and unknown/future TMDB receipts become **missing genre coverage**, not an invented Other category. Genre IDs are qualified by the media-provider namespace; each genre's set retains full movie/TV identity. Counts sort descending, then by name and ID; conflicting localized labels for an ID use a deterministic lexical label. Genres are not the user's independent Favorites flag or a recommendation.

TMDB receipts retain their actual retrieval time and existing 150-day ceiling. No receipt is renewed by aggregation, edits, year selection or relaunch. The read-only projection includes the earliest expiry of contributing genre metadata. Expired projections fail readiness checks, are cleared on metadata maintenance and are recomputed without expired labels; the view never presents an obsolete projection during replacement. Existing local maintenance, invalidation and store revisions are reused. No metadata refresh, artwork download, genre archive or new expiry loop is introduced. Persistent artwork remains blocked under the existing rights gate. All calculations work without connectivity using whatever metadata is still eligible locally.

## Concurrency, invalidation and performance

`PersonalStatisticsInput.capture` runs on the main actor and copies already loaded LibraryStore scalar/COW fields in one pass. It does not refetch SwiftData. It excludes private review text, artwork URLs, live ModelContexts/models, episode JSON and rating-edit timestamps. JSON genre decoding, dictionaries, sets, counting and sorting run in a cancellable detached task in the existing aggregation service. Genre payloads for unrelated Library titles are not decoded.

`PersonalStatisticsModel` publishes UI state on the main actor. Selection/revision generations and cancellation checks reject obsolete work even if an injected aggregator ignores cancellation. Input capture happens only after readiness checks. Revision, metadata invalidation, year, time-zone change, civil-day change, clock rollback or contributing genre expiry invalidate the projection. Ordinary renders and unchanged minute maintenance ticks do not recopy or reaggregate the store. A fresh evaluation instant is sampled once when a revision task starts, so an episode just marked after the last maintenance tick appears immediately; the observation key stays stable.

Expected work is linear in titles/events/episode rows plus sorting genre/year labels, with sets keyed by full identity and fixed twelve-month/ten-rating outputs. No device latency or memory improvement is claimed without measurement. Copying many already-loaded scalar rows still has main-actor cost; metadata decoding can scale with selected-year diary snapshots. Real-device profiling is still needed.

The test-only benchmark fixture contains **1,000 titles with genre JSON, 5,000 diary events and 10,000 episode records**. It expects 2,000 movie + 2,000 series events in 2020, 1,000 undated events, 40 unique movies + 40 unique series, 800 valid current ratings, genre counts 80/40, and 5,000 current episode marks in 2026. The fixture's date pattern intentionally leaves twenty title IDs with only undated events. Empty and small fixtures are also covered. No fixture seeds production data.

## Validation evidence and remaining work

Cloud checks:

- Project parses; all references resolve; all three targets include their complete Swift sources.
- Grammar syntax parsing passes for **171 Swift files**. This is not Swift compilation/type checking.
- Original build configurations and PBXProject settings are preserved; only file/group/source membership changes.
- Existing design-token checks pass for nine assets, four appearances and 44 intended text contrast pairs.
- `git diff --check` passes. Persistence schemas, personal mutation services, metadata networking and existing dashboard aggregation remain unchanged.
- `scripts/validate-v06.sh simulator-unavailable` reports expected exit **69 / UNVERIFIED**, requiring macOS, Xcode and an installed simulator.

Added **25 unit/benchmark methods and 3 UI tests**. Coverage includes empty/small/large inputs; year/month/rewatch/unique identity; leap years and time-zone boundaries; all half-star buckets, invalid/unrated/legacy values and current-rating limitations; multi-genre/duplicate/missing/expired metadata; reliable/unknown/conflicting episode dates; offline capture and persisted edits; projection caching/expiry; stale replacement/cancellation; and Profile navigation/year selection/chart text/empty states. Repository totals are 464 unit/benchmark and 95 UI methods.

**Native tests, charts/layout/accessibility, screenshots and benchmark timings remain unverified for this revision.** This Linux workspace has no Swift compiler, Apple SDK, Xcode, simulator or connected iPhone access. No native build/test ran and no measurement or screenshot is fabricated. Earlier owner-reported device test passes apply only to earlier code.

On the owner's Mac, run the shared MovieTracker scheme's full Test action, including PersonalStatisticsTests, PersonalStatisticsConcurrencyTests, PersonalStatisticsBenchmarks and PersonalStatisticsUITests, plus existing Dashboard/Diary/Rating/TV regressions. Use README's `xcodebuild test` command with an installed simulator destination. To collect comparable measurements, run PersonalStatisticsBenchmarks in Release repeatedly on the same destination; preserve XCTest clock/memory results with hardware/OS/Xcode/configuration. There is no arbitrary timing threshold or preexisting Year in Review baseline.

Example benchmark command (replace the destination with an installed simulator UUID and use a fresh result path):

```sh
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -configuration Release -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -only-testing:MovieTrackerTests/PersonalStatisticsBenchmarks \
  -resultBundlePath /tmp/PersonalStatistics041.xcresult CODE_SIGNING_ALLOWED=NO
```

UI tests use the existing DEBUG-only DashboardUITestImport with test-owned JSON and isolated in-memory persistence, never the real personal store. They attach an actual chart screenshot when executed. Manually check Profile/back navigation, changing years while calculation is active, dated/undated rewatches, rating edits, missing/expired genres, offline use and episode toggles followed by immediate return. Verify compact/large phones, light/dark, largest Dynamic Type, VoiceOver and high contrast. Charts have text labels plus complete native text rows and legends; values are not communicated only through color. No custom animations are added. Review chart rendering on native devices before accepting accessibility/layout criteria.

No GitHub Xcode CI, merge, TestFlight action or Pass 042 is included.


## V0.7 integration follow-up — Pass 043

The [V0.7 test plan](V0.7_TEST_PLAN.md) maps this feature to existing and new cross-feature regressions and records current execution limits. Production behavior, migration definitions, metadata receipts and personal backup formats are unchanged in the stabilization pass. Supported cloud static checks pass; native functional, disk/relaunch, accessibility and performance results remain unverified for this revision. Persistent artwork remains separately blocked.
