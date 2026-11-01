# TV season and episode tracking — pass 009

## Metadata and identity

The existing MediaMetadataService and TMDB client now expose TV season catalogues and single-season episode listings. No second API client is created. Series detail responses supply season summaries, including season zero/specials. `/tv/{id}/season/{number}` supplies the complete season list in one endpoint response, not a paginated search. The existing bearer configuration, injected transport, error mapping, timeouts and cancellation apply. Negative seasons, wrong media types, mismatched season responses and duplicate provider episode IDs are rejected. Missing titles have number-based labels; missing air dates, overviews and runtime remain unavailable. Real season endpoints remain unverified here without authorized live configuration.

EpisodeID combines the full provider-qualified TV MediaID with an opaque provider-qualified episode ID. TMDB's stable episode ID identifies the exact episode across seasons; season/episode numbers and titles are display metadata, not the identity key. Thus different providers/series/episodes cannot collide, equal visible titles/numbers do not merge episodes, and an episode moved or renumbered by the provider keeps one watched record. Season lists use a season number only within the owning series.

TVShow adds only an optional seasons field, so previously saved Codable domain snapshots without that field still decode. Season DTOs remain separate from domain/persistence types. Movie metadata and movie detail content are unchanged.

## Local storage and data integrity

Two new SwiftData entities are registered alongside the unchanged Library, Review and ViewingEvent entities:

- StoredTVSeason: exact series identity/season number, names/counts, saved series metadata, episode-list and last-listed-ID snapshots, coverage/source flags and refresh timestamp.
- StoredEpisodeProgress: UUID, exact series/episode key, current watched flag, optional last-marked timestamp, current season number and episode metadata snapshot.

All mutations use the existing main-actor LibraryStore and its dedicated context/explicit transaction/save/rollback path (the generic transaction helper is shared with diary writes). The app's single writer resolves existing exact keys before inserting, rejects duplicate current records, and updates the same record idempotently. Unwatched keeps a false record rather than deleting the saved episode metadata. Application-level uniqueness assumes future features continue using this writer, not competing contexts/imports.

Metadata refresh updates metadata, never the watched flag or watched timestamp. An episode/season omitted from a response stays cached and visible with a previously-loaded indication; coverage becomes incomplete rather than pretending the omitted progress never existed. If an existing stable episode ID appears in another season, metadata moves it to that season without creating a second progress record. Save failures roll back the whole transaction, including any implicit Library row or Watching change.

Opening metadata alone does not create a personal Library entry. Marking an episode watched ensures one TV Library entry; only no-status or Watchlist entries become Watching. Existing Watching, Watched, unknown legacy statuses, favorites, ratings, reviews and diary history remain intact. Unwatching does not automatically change series status. Episode toggles create no generic series diary event or invented episode history. Episode progress never automatically marks the series Watched.

## Eligibility, percentages and completion

Calculations deduplicate stable EpisodeIDs and evaluate date-only air dates against **today at UTC midnight**. An episode dated today is treated as aired; exact broadcast times are not inferred.

- Aired/eligible: known air date on/before today.
- Future: known later date; excluded from the aired denominator and cannot newly be marked watched. Previously saved flags survive a provider date correction and can still be cleared.
- Unknown air date: excluded from the aired denominator, visibly labeled; manual marking is allowed, but season bulk-watched skips it.
- Specials: season zero has its own list, toggles, batch actions and progress, but is excluded from regular-series aggregate totals.

The UI shows **all saved watched flags** separately from **watched known aired episodes**. A percentage is shown only when episode coverage is known and the eligible denominator is positive. For example 3/10 = 30%, 10/10 = 100%, and 0/10 = 0%. Zero eligible episodes produce no percentage or completion claim. Missing totals/listings or retained omitted metadata withhold the percentage rather than guessing.

A successful complete season endpoint can establish a known listing count when the series summary did not provide one. Declared counts larger than the returned list, missing cached entries or mismatching last-listed IDs make coverage incomplete. Series percentage requires every known regular season's full listing and a consistent catalogue count. Loading only one of several seasons cannot show 100% series completion. Regular seasons omitted from the current catalogue stay saved and conservatively make coverage incomplete until metadata is reconciled.

“All known aired episodes watched” / “All known aired regular episodes watched” means only the current known eligibility set. Unknown dates and future releases are shown separately. It does not mean permanent series completion, even at 100%; the provider's series status remains a separate fact. Returning-series and Ended status do not change the math or trigger a user Watched status. Eligibility is recomputed when the UI/store summary is read; there is no notification/background scheduling system.

## Screens, season actions and offline use

TV Details reuse the existing route and add a Seasons section with name/number, declared count, saved watched count, percentage when valid and known-aired completion label. A selected season opens a native episode List. Title/number/air date/overview/runtime and a directly accessible watched toggle are available without an episode detail screen. Text wraps with Dynamic Type and no fixed text height. Movie Details do not show this UI.

“Mark Aired Episodes Watched” requires confirmation and changes only known aired episodes in the selected season. “Mark Season Unwatched” is the clear reversal action, also confirmed; it clears all saved watched flags for that season, including manually marked unknown-date episodes. It is not an exact historical undo stack. Other seasons and personal data remain unchanged. Batch writes fetch existing progress once and commit once, rather than saving per row; watch IDs are deduplicated before mutation. No cross-series/complex bulk actions are added.

Library → TV Episode Progress lists previously loaded series from the saved metadata, including ones with no personal Library row. This keeps offline season browsing reachable after relaunch or explicit Library removal. The same MediaDestination/detail architecture is reused; no competing TV detail client/route exists. Previously loaded episodes and watched state remain editable offline. Failed requests leave saved data visible with retry/refresh actions. Initial complete series metadata is reused; explicit Refresh Seasons retrieves the provider catalogue. Older saved Library detail snapshots cannot overwrite newer persisted catalogues. Network task cancellation and generation checks prevent late responses from updating caches.

Only loaded data is available offline; unloaded season episode lists are not invented. There is no automatic fetch of every season on a series page, so series coverage/percentage may remain unknown until those season lists are loaded. Provider caching/retention and attribution requirements from metadata-provider.md remain release prerequisites; this implementation does not establish content rights. No images/stills downloader or custom image cache is introduced.

## Migration and validation limits

The existing Library/rating/review/diary entities and fields are retained. New entity tables and an optional Codable metadata field are additive; there is no destructive migration, default-store deletion/recreation, cascade relationship or progress cleanup on metadata omissions. Existing-store migration is intended to be lightweight but **has not been executed against pre-009 stores** here. Validate recoverable old-store copies on macOS before release. Current-schema reopen tests do not prove an old-schema upgrade.

Added **18 TV progress tests**, **3 provider tests** and **4 UI tests**, for **140 total test methods**. Coverage includes identity, duplicate prevention, individual toggles, percentages/completion, specials/future/unknown dates, batch watched/unwatched, existing personal data/status preservation, metadata omission/moves, offline mutation/reopening, save rollback, catalogue coverage/staleness, late cancellation, provider boundaries, TV navigation and movie regression.

Passed in this Linux host: Swift grammar parsing for all **76 Swift source/test files**, OpenStep project/reference/file/source membership checks, shared scheme/asset checks and whitespace validation. Parsing does not type-check Swift, expand macros, compile an iOS app or execute tests.

**All 140 tests, iOS builds, runtime UI/accessibility/save/relaunch, live-provider requests and pre-009 migration remain unverified.** Swift compiler/Xcode/Apple SDK/simulators are unavailable. No GitHub Xcode CI was added. DEBUG-only existing fixtures include specials, aired/unknown/future episodes and dedicated UUID persistent stores; they do not run real network calls or erase normal user data.

Run locally from the checkout root in Bash with an installed simulator UUID:

```bash
set -euo pipefail
xcodebuild -version
xcrun simctl list devices available
TV_CHECK_DIR="$(mktemp -d /tmp/MovieTracker-tv-progress.XXXXXX)"
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -derivedDataPath "$TV_CHECK_DIR/DerivedData" \
  -resultBundlePath "$TV_CHECK_DIR/Progress.xcresult" \
  -only-testing:MovieTrackerTests/TVProgressTests \
  -only-testing:MovieTrackerTests/MetadataServiceTests \
  -only-testing:MovieTrackerUITests/TVProgressUITests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$TV_CHECK_DIR/test.log"
```

Confirm **43 selected methods** execute (18 progress + 21 provider + 4 UI), then run all 140 without only-testing filters. These commands are unexecuted instructions. Manually review compact/large iPhones, dark/light and largest Dynamic Type, VoiceOver toggle descriptions, empty/special seasons, missing dates/totals, future episodes, explicit batch confirmations/reversal, error/offline states, cold relaunch, metadata omissions/new episodes, earlier Library snapshots, preserved personal data, migration and unchanged movie flows. No genuine simulator screenshots are available here.

Episode-level public reviews, notifications and streaming-service availability are not implemented.
