# What Should I Watch? (Pass 033)

## Entry and behavior

Library → **What Should I Watch?** uses the current Watchlist by default. It is independent of Library's search/status/sort controls. There is no new tab, recommendation service, account, or provider API. A native source picker can explicitly choose any custom collection, including its watched/statusless members. Deleted collections remain visibly unavailable with an empty pool rather than silently switching sources.

The result contains title, type, year, genres and movie runtime when locally known, a cache-only poster, Open Details, Pick Again, and Return to Filters. Open Details uses the existing `MediaDestination` / `SavedMediaNavigation` route. Opening Details may perform the existing metadata refresh; entering discovery, filtering and choosing never does. A pick does not change status, favorites, ratings, reviews, diary entries, progress or collection ordering.

Source, filters and the current pick live in a Library-owned observable model. They survive returning from Details, tab switches, and leaving/reopening discovery while the Library view remains alive. They are not persisted across application termination. Returning to filters or changing filters/source does not erase or automatically replace the current pick; Show Current Pick returns to it. Reset explicitly starts over. If an item's lease expires, its identity remains selected while provider fields become unavailable. Pick Again may legitimately select the same title: sampling is uniform and independent, not a shuffled queue.

## Eligibility and filters

- Identity is the complete `MediaID` (media kind plus namespaced provider value). Deduplication occurs before sampling. Movie and TV numeric-ID collisions remain distinct.
- Watchlist includes only `LibraryStatus.watchlist`. Watching/Watched, favorites and rating-only records are not implicitly included. Collection source uses existing indexed memberships, preserves their order, and supports identity-only references even after the Library row is removed.
- Media: All / Movies / TV Shows, sharing Library's `matchesMedia` semantics.
- Genres: **OR** across selected provider-qualified genre IDs; combined with other filters using AND. Available choices come only from valid local metadata in the selected source. A selection stays selected if a source change no longer offers that genre; Clear Genres/Clear Filters removes it.
- Years: optional inclusive lower/upper bounds. Equal bounds select one year. Only 1–9999 with lower ≤ upper are valid. Missing years fail an active bound; they are never replaced with zero.
- Runtime: Any length or movies up to 90/120/150/180 minutes, inclusive. An active limit excludes TV shows and movies without a positive known runtime. The UI explains this even when TV Shows is selected. Episode runtime and episode count never become a series runtime.
- Without metadata-dependent filters, incomplete/expired titles remain eligible as identity placeholders. Unknown genres/year/runtime fail only filters requiring those values. Empty Watchlist/collection and filtered No matches have distinct guidance.

## Local data, retention and artwork

`WatchDiscoveryModel` copies scalar snapshots on the main actor from existing LibraryStore arrays and indexed `entry/events/reviews/seasons/members` lookups. It does not fetch a second SwiftData collection or create a ModelContext. Only immutable Sendable inputs cross to a cancellable detached worker. The worker decodes exact-ID metadata, chooses the newest valid receipt, applies `MetadataPolicy.mayDisplay` (150-day TMDB lease), and builds candidates. Missing/future/expired TMDB receipts and malformed/mismatched snapshots provide no filterable metadata. Personal columns are never used to renew a metadata lease.

The existing pick is independently rehydrated on source revisions so a metadata clear cannot resurrect an old selected snapshot, even when filters/source have changed. Its identity is retained. Source projections are cached by source, store revision and metadata-maintenance reference date. Filter edits reuse the decoded source and available genre list; unchanged task keys do no work on body redraw. Library's deterministic Recently Added sorter orders the default pool using identity placeholders; collection order is preserved. All filtering and random selection are local/read-only. Cancellation plus generation/request checks prevent old work from publishing or picking an obsolete pool.

Production uses unbiased `Int.random(in:)` over unique eligible indices; tests inject an index selection closure. There are no network/provider/transport dependencies in the model or projection.

Artwork reuses `LibraryCachedPoster`: only a matching saved thumbnail URL backed by valid local metadata can read the bounded shared memory cache. It never downloads images. **Pass 030's licensing gate remains BLOCKED**: no disk artwork cache, URLCache fallback, guaranteed restart artwork, or expanded retention. Missing/evicted artwork uses the existing accessible placeholder. Local metadata and personal data remain usable offline; full remote Details may show the existing cached/error experience.

## Validation and remaining limits

Added **25 unit tests and 5 UI tests** using deterministic local fixtures, including disk-backed reopening, typed/provider deduplication, Watchlist/collection eligibility, OR genres, inclusive years/runtime, missing and expired fields, no mutation, current-pick preservation, source revision changes, cancellation/replacement and deterministic index sampling. UI fixtures require both DEBUG `--ui-testing-search` isolation and explicit `--ui-testing-watch-discovery`; production is never seeded.

Executed in Linux:

- Xcode project OpenStep parsing, reference resolution and complete source membership for all three targets: **PASS**.
- Swift grammar parsing for **148** source/test files: **PASS**; this is not compilation or type checking.
- Asset JSON parsing and design-token/adaptive contrast validation: **PASS**.
- Project/build configuration equality with main and whitespace checks: **PASS**.

**All 25 new unit and 5 UI XCTest methods are UNRUN.** No Xcode, Swift compiler, iOS SDK or simulator is installed. Native compilation, offline runtime behavior, SwiftData disk reopening, screenshots, VoiceOver, Switch Control, small-screen layout, Dynamic Type, and light/dark appearance remain unverified. No performance improvement has been measured. Snapshot capture still scales with source size and related local diary/review snapshots on source revisions; decoding, sorting and filtering run off the main actor. No database/schema/migration, networking, retention, personal-write or CI behavior changes.

### Local validation

Use README's shared MovieTracker scheme command with your installed simulator UUID. Targeted tests:

```sh
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -only-testing:MovieTrackerTests/WatchDiscoveryTests \
  -only-testing:MovieTrackerUITests/WatchDiscoveryUITests \
  CODE_SIGNING_ALLOWED=NO
```

Also run the existing Library organization, collection, navigation and offline suites. Manually save a movie and TV show to Watchlist, disconnect the network, and verify source/media/OR-genre/year/runtime combinations, empty states and Pick Again. Select a collection containing a watched title; verify its independent order/status survives selection. Open Details, return, switch tabs and reopen discovery; verify filters and pick remain. Confirm an expired TMDB title is identity-only, unknown fields fail required filters, and artwork loss after restart is explained by the licensing gate. Verify large text and compact screens, light/dark appearance, VoiceOver labels and keyboard Done dismissal. Capture screenshots of filters and a result after actual simulator validation. No screenshots were fabricated in cloud.
