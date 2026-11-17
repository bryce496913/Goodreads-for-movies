# Expanded movie and TV discovery — Pass 040

## Behavior and architecture

An empty/whitespace-only Search field shows Browse. A native Movies / TV Shows selector gives both media types the same categories: Trending, Popular, Top Rated and Genres. Only the selected feed loads; this is not a multi-feed dashboard. Typing uses the existing debounced title Search model, filters, cancellation and pagination. Clearing returns to the current valid Browse selection/results without another feed request. The title-search algorithm is unchanged.

`MetadataBrowseRequest` extends `MediaMetadataService`; `TMDBMetadataService.browse` uses the existing authenticated transport, response mapping, retry/cooldown policy and image configuration. No second client, backend, response database or schema change is introduced. Other providers can explicitly report `unsupportedDiscovery` through the default protocol implementation.

`ProviderBrowseModel` is main-actor UI state containing Sendable domain results. It has no model context or LibraryStore writer. `ProviderBrowseView` reuses SearchResultRow, sized artwork, Paper/Ink/Ember controls and MediaDestination. Existing Detail actions remain the only route from browsing to personal changes, including statuses, independent favorites/ratings, reviews and collections.

## Official provider review

Reviewed the [official TMDB OpenAPI](https://developer.themoviedb.org/openapi/tmdb-api.json), [language documentation](https://developer.themoviedb.org/docs/languages), [trending reference](https://developer.themoviedb.org/reference/trending-movies) and [API terms](https://www.themoviedb.org/api-terms-of-use) on 2026-11-17. The OpenAPI endpoint/parameter inventory was fetched again successfully during final checks. These are documentation checks, not authenticated API smoke tests or a licensing certification.

All routes below are GETs under `https://api.themoviedb.org/3` with application-level Bearer authorization through the existing development configuration.

| Category | Movie route | TV route | Paging / parameters used |
| --- | --- | --- | --- |
| Weekly trending | `trending/movie/week` | `trending/tv/week` | `language`; single-page preview |
| Popular | `movie/popular` | `tv/popular` | `language`, `page`; optional movie `region` |
| Top Rated | `movie/top_rated` | `tv/top_rated` | `language`, `page`; optional movie `region` |
| Genre list | `genre/movie/list` | `genre/tv/list` | `language` |
| Genre discovery | `discover/movie` | `discover/tv` | `language`, `page`, `with_genres`, `sort_by=popularity.desc`, `include_adult=false`; optional movie `region` |
| Similar | `movie/{id}/similar` | `tv/{id}/similar` | `language`, `page`; UI uses page 1 only |

The official spec does not list a `page` argument for Trending. The client refuses Trending page 2 and exposes no Load More for it. Popularity and ratings are provider rankings within a media type, not a shared cross-media or personalized ranking. No vote score is invented/displayed. UI requests currently use `en-US` with no regional restriction; typed callers can supply validated language and region. Region is sent only to documented movie endpoints, never substituted with TV `watch_region`.

Genres are loaded/cached separately for movie and TV, mapped to canonical `tmdb:<positive ID>` values. Switching media clears the selected genre; a selection must occur in that media type's actual genre list before discovery loads. Choosing Genres without an ID fetches no titles. Choosing any other category returns to browsing without the genre filter. Empty lists and failed genre requests remain distinct.

Similar Titles uses the actual TMDB Similar endpoint, not AI or a personalized recommendation claim. It removes the current exact MediaID, deduplicates by full typed identity and presents at most 20 results in a horizontal section. Tapping uses the existing detail route. It is a bounded first-page preview without recursive prefetching; further requests happen only when the user navigates to another title. Empty and unsupported responses have explicit presentation.

## Requests, retention and failures

- One selected feed chain at a time; genre lookup, feed and optional image configuration are sequential. Pagination has a synchronous double-tap guard; only one page task runs per model. Image configuration may finish alongside an explicitly requested additional page. No parallel category prefetch, automatic paging or discovery refresh loop.
- SwiftUI owns `.task(id:)` cancellation. Immutable selection keys, generations, cancellation checks and credential epochs guard results after every await, including noncooperative test services. Pagination cannot append to a replacement category/media selection. Disappearing cancels owned pagination; canceled/failed pages do not advance the cursor.
- Popular, Top Rated and genre pages are manual, capped at 500 provider pages and 200 retained titles per current Browse pool. Similar is capped at 20. Duplicates are excluded before appending. Refresh Titles / Retry Browsing explicitly replaces the pool. There is no claim that 200 titles are a complete catalog.
- Existing typed offline, timeout, authentication, forbidden, rate-limit and malformed-response errors and bounded retry/cooldown behavior remain authoritative. Errors do not become empty results, and UI does not continually retry. Missing credentials point to Profile Settings. Optional image-configuration failure leaves accessible poster placeholders.
- Actual title receipt dates come from TMDB mapping; genre receipts are recorded only after a fresh successful fetch. Reads, navigation and personal edits never renew them. Genre memory is bounded to two media lists. Current pools and image configuration expire under the existing 150-day policy, and credential replacement clears them. Metadata maintenance/session invalidation is wired into Search and Detail; expiry itself triggers no network request. Refresh is explicit.
- Results are session memory, not a permanent offline discovery archive. No persisted title/genre cache or personal-data mutation is added. A relaunch offline can still use the established personal Library, while new Browse feeds require the network.
- Attribution appears on Browse and existing Details. Existing provider authorization/commercial-use gates remain; endpoint documentation does not grant new rights. Pass 030's disk-artwork gate remains **BLOCKED**. Artwork continues through ProviderArtworkLoader's bounded, coalesced, memory-only handling and existing lease/credential checks. No disk images, URLCache fallback, full-resolution artwork or credentials are added.

## Regression evidence and owner validation

Cloud checks performed:

- OpenStep project parses; every reference resolves and all three targets have complete Swift source membership.
- Grammar syntax parsing passes for **163** Swift files. This does not type-check Swift or compile SwiftUI.
- Build configurations and PBXProject settings compare identically to pre-change HEAD; only source/group membership was added.
- Nine semantic color assets/four appearances and 44 intended text contrast pairs pass the existing validator.
- `git diff --check` passes. Existing schema/persistence sources remain unchanged.
- `scripts/validate-v06.sh simulator-unavailable` returns its expected **69 / UNVERIFIED** result: macOS, Xcode and an installed simulator are required.

Added **17 unit tests and 4 UI tests** (repository totals: 439 unit/benchmark and 92 UI methods). HTTP fixtures cover all 12 endpoint routes, language/region/auth headers, canonical genres, typed identity, missing fields/art, invalid page/type and typed failure handling. Model fixtures cover category/media switching, genre choice, duplicate paging/double taps, search/Browse return, error versus empty, expiry/credential invalidation, explicit pagination recovery, cancellation, noncooperative stale responses and personal-store non-mutation. UI fixtures cover categories, genres, media switching, Search/clear, Details, Similar, offline and empty states. Existing Search/App Shell expectations now return to Browse rather than the former idle placeholder.

**All new and existing native XCTest methods remain unrun for this revision.** There is no Xcode, Swift compiler, iOS SDK or simulator here. No live authorized TMDB search/feed/detail check ran; no credential was used. No device/simulator screenshot was generated. UI tests attach Browse screenshots when run locally. Earlier owner-reported Xcode/device passes apply to earlier code only.

On the owner's Mac, run the shared MovieTracker scheme's full Test action (or the README's `xcodebuild test` command with an installed destination). Run ProviderBrowseTests, TMDBBrowseTests and ProviderBrowseUITests plus existing SearchModel, Search, Detail, Library and networking regressions. Use deterministic `--ui-testing --ui-testing-search` fixtures for UI checks; `--detail-fixture=browse-offline` and `browse-empty` select failures/empty feeds. No Xcode GitHub CI is added.

Manual checks with authorized local configuration:

1. Visit Search with no text; inspect each category for Movies and TV, then choose distinct genres. Load extra Popular/Top Rated/genre pages, double-tap Load More and switch media during loading.
2. Type/clear a query, navigate into/out of Details, and switch tabs; verify the appropriate query/filter/pool survives and movie/TV identities remain correct.
3. Inspect Similar on a movie and series, select another title and navigate back. Verify no current-title duplicate or unwanted Library entry/diary event appears.
4. Test missing/invalid credentials, airplane mode, unavailable artwork and retry after recovery. Verify no spinner persists indefinitely and personal actions/data remain intact.
5. Check compact/large iPhones, light/dark, largest Dynamic Type, VoiceOver and Reduce Motion. Capture real Browse, genre, movie/TV and Similar screenshots; layout and runtime acceptance remain unverified until this is done.

Known limitations: session-only discovery results, fixed English UI request locale, explicit 200-title Browse/20-title Similar bounds, single-page Trending, no new persistent artwork permission, and unverified native/runtime/live API behavior.
