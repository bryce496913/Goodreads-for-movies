# Library organization — pass 010

## Filtering and local search

The saved Library has independent media (All/Movies/TV Shows), status (All statuses/Watchlist/Watching/Watched), Favorites-only, local title query and sort controls. Media/status/favorite/query conditions combine with **AND**. Favorites are not a viewing status: All statuses includes favorites with any status or no status. A Watching + Movies intersection normally has no matches; controls never silently change another active filter or hide legacy records from the All view.

The search field explicitly says **Search saved titles**, separate from discovery Search. Matching folds case and diacritics with a fixed en_US_POSIX locale and normalizes whitespace on both titles and queries. Clearing text removes only the query, retaining other preferences. Reset Filters clears query/media/status/favorites while retaining the selected sort. Preferences are local view state retained during tab/detail navigation, not database mutations or persisted app preferences. A new launch defaults to All media/All statuses/all favorites and Recently Added.

## Sorting rules

| Option | Primary order | Missing values |
| --- | --- | --- |
| Recently Added (default) | addedAt descending, not updatedAt | Existing stored added dates are used; no date is invented |
| Title A–Z | Folded title ascending | Existing metadata-unavailable labels remain honest display fallbacks |
| Release Year | Known year descending (newest first) | Unknown/nonpositive years after known years; no year is filled in |
| Personal Rating | Valid integer half-star units descending | Unrated follows valid values; invalid legacy ratings follow unrated |

After the primary key, all sorts use folded title, media type, opaque provider-qualified media value, then record UUID ascending. Equal ratings, years, added dates and identical titles therefore retain deterministic ordering even if source fetch order changes. Records use their persistent UUID for SwiftUI identity, not list position. Legacy logical duplicates are not merged/deleted by a view.

Rating projection uses the existing validated boundary: exact valid legacy Double ratings sort correctly without a backfill, legacy zero is unrated, and invalid stored values display unavailable instead of being rounded/clamped or written. Known half-star units remain precise integers. Sorting/filtering never calls a mutation method.

## Layout, favorites and navigation

Rows show cached poster/placeholder, title, media type, known year, current status, personal rating/Unrated and favorite indicator. Titles wrap without a fixed text height. Accessibility text sizes use a vertical artwork/text layout and a menu in place of the segmented media control. Native menu/status/sort/toggle controls remain independently accessible. Layout, VoiceOver and Switch Control quality still require local simulator/device checks.

Favorites can be added/removed in existing Details actions and from a row swipe/context menu. The new existing-row store operation changes **only** isFavorite and updatedAt; it does not re-encode or replace saved metadata, status, ratings, reviews, diary or episode data. It uses the shared explicit-save/rollback writer and shows a failure alert. Removing a favorite from a Favorites-only view updates the list after the save. Status edits in Details similarly update the active intersection when returning.

History, Personal Reviews and TV Episode Progress are in **More in Library** in the navigation bar, remaining reachable with thousands of rows. Their established media destination handling is retained. Empty/no-match views provide an explicit Find Movies and TV action; it selects the discovery Search tab and resets that tab's navigation path to its search root, without coupling the Library query to remote search. Ordinary tab switches preserve existing navigation state.

## Empty states

A truly empty source always shows Your library is empty. For a nonempty source with no visible matches, precedence is: nonempty local query → no saved titles match; Favorites-only → no favorites/no favorites matching filters; specific status → empty Watchlist/no Watching series/no Watched titles; otherwise no matching saved media. Text explains adjusting/resetting combined filters and selecting All statuses for independent favorites. Source/read failures show an error/retry rather than being described as a successful empty fetch.

## Performance and offline behavior

LibraryStore already owns the complete local entries collection. This pass projects lightweight immutable row values on committed store revisions, rather than issuing a second SwiftData fetch from each View body. Folded title keys and validated rating keys are computed once per projection. The active source sort is cached; query/media/status/favorite edits filter that sorted array in **O(n)** without re-sorting. A sort change or new source revision rebuilds it in **O(n log n)**. Memory is O(n), and List constructs row views lazily. Normal redraws only read the visible array.

In-memory filtering is deliberate: it supports exact diacritic/case rules, legacy rating fallback and missing metadata using the already loaded single-writer collection, avoiding uncertain predicate translations or competing contexts. At larger-than-memory collection scales, serverless paginated SwiftData queries/indexing could replace this projection behind the same UI; that is not built speculatively here. Store commits still reload its existing collections; this pass does not claim measured frame rates or optimize every unrelated persistence transaction. The 5,000-item correctness dataset is not a runtime benchmark.

No query, filter or sort makes HTTP requests or writes saved data. Library posters perform **cache-only reads of the existing OS URLCache**; they do not initiate image downloads on row appearance/filter changes. If the system no longer holds an image, the row shows a film placeholder, even online. No custom disk/image cache or image download is added. Discovery/Details keep their existing separate image-loading behavior. Selecting a detail or the explicit Find action is separate user navigation, not a filtering request. Library search works without provider credentials or internet.

## Schema and integrity

No persistent entity, schema registration or existing stored field is changed; no migration/backfill/reset is introduced. LibraryStore adds an in-memory revision signal and the narrow favorite mutation. Private notes, ratings, timestamps, snapshots and record identities are unaffected by read-only organization. Existing save failures roll back; real-user stores are never seeded or wiped.

## Tests, screenshots and actual results

Added **14 unit/store tests** and **5 UI tests**, for **159 total methods**. Unit tests use a deterministic 5,000-item dataset, stable UUIDs, repeated titles/equal dates/years/ratings, nil values, no-status favorites, movie/TV separation, AND filters, case/diacritic search, clear/reset/empty messages, legacy projection without writes, filtered status/favorite updates, failed-save rollback and isolated persistent reopening.

UI tests use **250 synthetic records** only when both existing --ui-testing-search and new --ui-testing-library-organization flags are explicitly provided in DEBUG. Normal UI tests remain empty/in-memory unless requested. The seed uses the same writer transaction, runs only for an empty isolated test store and does not reset the dataset on relaunch, preserving favorite edits. Release excludes the fixture. A visible UI test data marker identifies screenshots. UI tests cover combined filters/search, clear/sort menus, edited status under an active filter, no-match → Search navigation, and favorite removal/relaunch. Existing diary/archive and row-navigation tests were adapted for the toolbar menu and added controls.

Passed here: static Swift grammar parsing of all **81 Swift files**, project references/file/source membership, shared scheme/asset and whitespace checks. These do not type-check Swift, expand macros, compile the app, run tests or measure performance. **All 159 tests, runtime UI/ordering/accessibility, persistence behavior and performance remain unverified** on this Linux host without Swift compiler, Xcode, Apple SDK or simulator. No GitHub Xcode CI was added.

No genuine Library screenshots can be supplied from this environment. UI tests retain attachments named Library — combined filters fixture, Library — rating sort fixture, and Library — no local matches fixture when executed. Screenshot generation is also unverified. Export them from the current xcresult in Xcode's Report navigator and attach to the PR; keep fixture markers visible. Do not substitute generated mockups as runtime evidence.

Run locally from the checkout root in Bash, with an installed simulator UUID:

```bash
set -euo pipefail
xcodebuild -version
xcrun simctl list devices available
LIBRARY_CHECK_DIR="$(mktemp -d /tmp/MovieTracker-library-organization.XXXXXX)"
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -derivedDataPath "$LIBRARY_CHECK_DIR/DerivedData" \
  -resultBundlePath "$LIBRARY_CHECK_DIR/Library.xcresult" \
  -only-testing:MovieTrackerTests/LibraryOrganizationTests \
  -only-testing:MovieTrackerUITests/LibraryOrganizationUITests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$LIBRARY_CHECK_DIR/test.log"
```

Confirm **19 selected methods** execute, then run all **159** without only-testing filters. Commands above are instructions, not passing runs. Manually check compact/large iPhones, light/dark and large/largest Dynamic Type, long titles, VoiceOver, all combined filters/empty states, no-status/Watched favorites, all sorts/ties/missing values, clear/reset, quick favorite failure, status changes/back navigation, utility menu and Find route, relaunch and airplane-mode local search. Use Instruments/local measurements for actual large-library responsiveness before claiming performance acceptance.

No social lists, public collections or cloud synchronization are implemented.
