# Functional Search — pass 004

## Behavior and architecture

Search uses PR #003's `MediaMetadataService`. The Search tab owns no provider DTOs and invents no production results. `SearchLaunchConfiguration` constructs a live adapter from the private local Xcode Run environment described in [provider setup](metadata-provider.md). Without configuration, entering a query produces a clear configuration error; app launch and other tabs still work offline.

`SearchModel` is a main-actor Observation model retained by `AppRootView` in State. Navigating to Details or switching tabs does not recreate it or intentionally cancel its valid request. Query, filter, results, and page state survive while that root lives, but are not persisted across process termination.

Query normalization trims leading/trailing whitespace and collapses internal whitespace. Normalized-equivalent edits do not refetch. Empty input cancels pending work and clears results/errors immediately. A 300 ms `Task.sleep` debounce runs before requests; there are no timers. The debounce closure is injected for deterministic tests.

Every meaningful query/filter change cancels both the active first-page and page tasks and generates a new UUID. Before publishing results or errors, each task checks cancellation and its captured generation. Thus a transport that ignores cancellation or an old page that completes after a new search cannot overwrite/append to newer results. A cancellation of the still-current request leaves a retryable canceled state instead of a permanent spinner. No continuous retries run for auth, rate limits, offline conditions, or provider failures.

All, Movies, and TV Shows invoke the corresponding protocol endpoint. Rows retain the full typed `MediaID`, so movie and TV IDs/titles can coincide without collapsing entries. Deduplication is by that identity, within and across pages. Date-only values use Gregorian UTC for the displayed year (January 1 does not become the previous year in a western timezone). Titles wrap with dynamic system text styles and have explicit media labels and accessible combined labels.

Pagination is explicit **Load More**. No `onAppear` or rendering-triggered auto-fetch is used. A synchronous in-flight guard prevents double taps from requesting the same page. Success advances nextPage even when the page contains only duplicates or filtered-out people. Failure keeps current results and the failed next-page number, with a separate Retry More Results control. Only explicit retry runs that page again. A page with no visible movie/TV matches and further pages shows both an explanation and Load More.

Artwork resolution uses provider configuration and `w185` thumbnails, with AsyncImage and a bounded 56 × 84 point artwork area; row text has no fixed height. Missing, unsupported, or failed images show a neutral film placeholder. Configuration failure does not erase searchable titles, and exposes a separate Retry Artwork action. No custom image cache is introduced. The configuration task is independent of result ordering; it cannot publish an old query's titles.

`MediaDestination` is the single typed route for movie/TV Details. Its title/type/year snapshot remains stable during search edits. `MediaDetailView` now loads full movie/TV content via this same route; see [pass 005](media-details.md). The route snapshot remains the initial loading/error fallback. No ratings, reviews, or watchlist functionality is added.

Search includes a TMDB text attribution link and the established notice for real results. Provider documentation still returned HTTP 403 through this environment on 2026-10-31; current licensing, approved logo and placement requirements must be confirmed before distribution. No unverified logo asset is invented. Authorized live retrieval is not claimed here.

## Deterministic tests and fixture isolation

Thirteen SearchModel tests cover normalization/empty input, a manually released debounce gate, obsolete first-page and page completions, clear-query cancellation, endpoint filters/mixed identity, pagination/deduplication, initial/page errors and explicit retry, equivalent queries, current-request cancellation, configuration absence, and UTC years/typed routes. The tests use continuations and await task completion rather than timing sleeps. They do not need credentials or a network connection.

Five Search UI tests cover searching/selecting mixed results and tab state, clearing, all filters and Load More, empty results, and offline/error/retry presentation. Debug-only `SearchUITestService` is activated **only** by `--ui-testing-search`. The same flag selects an in-memory SwiftData container so these tests do not touch the default app store. Screens visibly say **UI test data**. Fictional fixtures contain no poster references and perform no network requests. Release builds exclude the fixture service and ignore the flag. Normal debug runs do not use fixture fallback for missing credentials.

The fixture query `sample` produces movie and TV versions of “Sample Story” with different years; page two intentionally repeats a movie to test deduplication. `empty` returns no titles, `error` fails offline, and `retry` fails once then succeeds on explicit retry. These strings have no special behavior outside the explicitly flagged debug fixture session.

## Executed checks and remaining validation

This host is Linux, with no Swift compiler, Xcode, Apple SDK or simulator. Static OpenStep project parsing/file-reference/target-membership checks, shared scheme/asset checks, Swift grammar parsing, and whitespace checks pass. All new sources belong to the correct app/unit/UI targets. Syntax parsing is not type checking or macro expansion. **All 46 tests, builds, actual UI navigation, artwork rendering, real-provider calls, and simulator acceptance remain unverified here.** No GitHub Xcode CI was added.

### Screenshots

**No genuine simulator screenshots are available from this environment.** The PR does not substitute mockups for screenshots. Search UI tests attach screenshots named:

- Search — mixed fixture results
- Search — selected movie
- Search — empty fixture response
- Search — offline fixture error

Run locally and export those attachments from the current `.xcresult` in Xcode's Report navigator. The screenshots intentionally show the UI test data marker. Separately capture authorized real-data results only after provider/configuration checks. Attach compact/large iPhone, light/dark, and largest accessibility text screenshots to the PR before considering visual acceptance verified.

### Run locally

From the checkout root in Bash, replace the simulator UUID:

```bash
set -euo pipefail
xcodebuild -version
xcrun simctl list devices available
SEARCH_CHECK_DIR="$(mktemp -d /tmp/MovieTracker-search.XXXXXX)"
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -derivedDataPath "$SEARCH_CHECK_DIR/DerivedData" \
  -resultBundlePath "$SEARCH_CHECK_DIR/Search.xcresult" \
  -only-testing:MovieTrackerTests/SearchModelTests \
  -only-testing:MovieTrackerUITests/SearchTests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$SEARCH_CHECK_DIR/test.log"
```

Confirm **18 search tests actually run**, then run all **46** tests without the only-testing arguments. These commands have not been executed here. Keep logs/result bundles outside Git. Screenshots come from those actual runs, not previously saved results.

Manual review on compact and larger iPhones should check light/dark mode, large and largest accessibility text, long titles, missing dates/images, both media types sharing a title, scrolling to Load More/retries, keyboard interactions, tab/detail/back preservation, and empty/offline/auth/rate-limit states. In a private authorized Run scheme, confirm real search, filters, pagination, and sized posters. No account is needed. Provider/network/credential requirements and local Xcode validation remain prerequisites for real-data acceptance.

Pass 005 extends this architecture to full details and increases the suite to 67 methods; the counts and static results above record the original pass 004. Current detail validation and screenshots are tracked in [media-details.md](media-details.md).
