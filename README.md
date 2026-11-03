# MovieTracker

A native, local-first iPhone foundation for tracking movies and television together. MovieTracker is a temporary working name. The app supplies navigation, accessible empty states, domain models, local persistence infrastructure, and an opt-in metadata service. Search now finds movie and TV metadata with authorized local TMDB configuration; titles can be saved locally with independent favorites and viewing statuses.

## V0.5 beta status

**NOT READY — BLOCKERS REMAIN.** Version 0.5.0/build 12 is prepared for local validation, not uploaded or certified. See the [release checklist and TestFlight steps](docs/V0.5_RELEASE_CHECKLIST.md), [regression matrix/evidence](docs/V0.5_TEST_PLAN.md), [known issues](docs/KNOWN_ISSUES.md), and [release notes](docs/V0.5_RELEASE_NOTES.md). TMDB cache content now uses a 150-day lifecycle with personal data preserved separately; see [metadata policy and remaining licensing/operational gates](docs/METADATA_POLICY.md). Runtime behavior, dormant-device retention and provider authorization still require verification.

## Requirements and running

- macOS with the latest stable Xcode and its iOS SDK (Swift 6 language mode).
- Minimum deployment target: **iOS 17.0**, iPhone first.
- SwiftUI, Swift Concurrency, SwiftData, XCTest; **no third-party packages**.

1. Open `MovieTracker.xcodeproj` in Xcode.
2. Select the shared **MovieTracker** scheme and an installed iPhone simulator running iOS 17 or newer.
3. Run with **Product → Run** (`⌘R`). App launch requires no account, API key, backend, or network connection. Real Search requires authorized local TMDB configuration and network access; see [provider setup](docs/metadata-provider.md).
4. Run **Product → Test** (`⌘U`) for domain, persistence, and navigation tests.

For a physical iPhone, select your signing team in Signing & Capabilities. Automatic signing is enabled; no personal team is committed. You may also pass `DEVELOPMENT_TEAM=<YOUR_TEAM_ID>` to `xcodebuild` for a device build. **`com.example.MovieTracker` is a placeholder bundle identifier**: replace it with an owned identifier before distribution/App Store submission (and update test identifiers as appropriate). Shared version/build defaults are in `Config/Beta.xcconfig`; ignored `Config/Local.xcconfig` can supply APP_BUNDLE_IDENTIFIER and DEVELOPMENT_TEAM. The display name is MovieTracker Beta. The supplied `AppIcon.appiconset` is selected for both Debug and Release. Icon compilation and archive validation still require local Xcode verification. Portrait is the initial supported orientation; system colors and native dynamic text styles support light/dark mode, increased contrast, and Dynamic Type.

Command-line validation on macOS:

```sh
xcodebuild -list -project MovieTracker.xcodeproj
xcrun simctl list devices available
# Replace the destination with an installed iPhone simulator's UUID.
xcodebuild test \
  -project MovieTracker.xcodeproj \
  -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -derivedDataPath /tmp/MovieTrackerDerivedData \
  CODE_SIGNING_ALLOWED=NO
```

Use the same arguments with `build` in place of `test` for a build-only check. See [the validation report](Documentation/FoundationValidation.md) for commands that capture exit status, build logs, test results, and the required manual matrix. Those commands are instructions, not recorded passing runs.

## Implemented

- Home, Search, Library, and Profile tabs, each owning its own native stack/path, with shared screen layouts, inline empty states and protected editors; see [app-shell audit and regression limits](docs/APP_SHELL.md).
- Personal Home dashboard and anonymous local Profile with saved Continue Watching, dated viewing history, Watchlist shortcuts, timestamped activity, and clearly defined statistics. See [dashboard semantics, migration, fixtures and validation](docs/home-profile-dashboard.md).
- Welcoming empty states with a route to Search, accurate zero counts, unavailable unrated average, and provider credential Settings plus About & Credits.
- Adaptive Paper/Ink surfaces and Ember emphasis, system typography/spacing tokens, and shared artwork, type labels, states and actions; see [design system, audit and accessibility evidence](docs/DESIGN_SYSTEM.md).
- Movie, TV show, typed media identity, viewing status, and user library domain values.
- A SwiftData container and stored library entry with explicit domain conversion, ready for future tracking features.
- An injectable, async TMDB metadata service for movie/TV/combined search, details, genres, and sized artwork URLs; connected to the Search tab. See [provider evaluation and local setup](docs/metadata-provider.md). Current official requirements, conservative expiry and outstanding licensing decisions are recorded in [metadata policy](docs/METADATA_POLICY.md); authorized live retrieval remains unverified.
- Functional Search with a 300 ms debounce, All/Movies/TV Shows filters, loading/empty/retry states, sized poster thumbnails, explicit duplicate-safe pagination, and typed movie/TV detail pages. See [Search behavior and validation](docs/search-discovery.md).
- Movie/TV detail pages with shared artwork, genre, synopsis, cast and metadata sections, TV season summaries, partial-failure recovery and session snapshots for previously loaded details. See [detail architecture and validation](docs/media-details.md).
- Persistent Library rows and detail actions for Watchlist, TV Watching, Watched, independent favorites, clear status and removal. Unexpired provider metadata supports offline display; expired/unknown-age content becomes an identifier placeholder while personal records remain; see [library persistence](docs/library-persistence.md).
- Personal movie/TV ratings from 0.5–5.0 stars using precise integer half-star units, independent of viewing status, with native accessible editing and Library summaries. See [personal ratings and migration](docs/personal-ratings.md).
- Private written reviews and a local viewing diary with optional watched dates, repeat watches, offline archives, explicit associations and independent deletion. See [review lifecycle, diary semantics and migration](docs/reviews-viewing-history.md).
- TV season/episode tracking with direct watched toggles, saved offline lists, confirmed season actions, and conservative aired-episode progress. See [TV progress rules and validation](docs/tv-episode-progress.md).
- Organized Library with local media/status/favorite filters, case/diacritic-insensitive title search, stable sorts, quick favorite actions and distinct empty states. See [Library rules, screenshots and performance](docs/library-organization.md).
- Manual personal-only JSON export and confirmed non-destructive restore from Settings; see [format, conflict rules, privacy and validation](docs/DATA_BACKUP_AND_RESTORE.md).
- A recoverable persistence-error screen that retries opening the store without deleting user data or silently switching to a disposable store.

## Architecture and decisions

```text
MovieTracker/
  App/                 App entry, container lifecycle, root tab navigation
  Core/
    Models/            Foundation-only domain values
    Persistence/       SwiftData storage and container creation
    Statistics/        Immutable local dashboard projections and deterministic aggregation
    Networking/        Metadata interfaces, TMDB DTO mapping and URLSession transport
    DesignSystem/      Shared visual primitives
  Features/
    Home/ Search/ Library/ Profile/
  Resources/Assets.xcassets/
MovieTrackerTests/     Domain and in-memory SwiftData tests
MovieTrackerUITests/   Tab and Settings navigation smoke test
MovieTracker.xcodeproj/  Native project and shared scheme
```

Feature views stay together. SearchModel owns observable search state on the main actor, with the instance retained at the tab root. Search depends on the metadata protocol; provider DTOs remain outside feature UI. Utilities and preview fixtures will be added only when needed.

`MediaID` combines a kind (`movie`/`tvShow`) with an opaque string, preventing movie and TV IDs from colliding. Provider identifiers are mapped to opaque namespace-qualified values at the metadata adapter boundary. Genre identifiers and poster references are opaque strings; no provider-specific URLs or SDK types enter the domain.

Library entries have at most one viewing status (`watchlist`, `watching`, `watched`), with an independent favorites flag so a watched title can also be a favorite. Personal ratings use validated half-star units independently of viewing status. Written reviews and repeat viewings have separate entities; the old review column remains readable for safe legacy import. LibraryStore preserves `addedAt` and updates `updatedAt` for meaningful edits.

SwiftData now uses a frozen VersionedSchema and an explicit additive migration plan, with pre-open safety backups and schema recognition. V2 adds metadata refresh state; recognized raw backups become verified personal-only recovery archives after successful application startup. Historical adoption remains unverified until the disk fixtures and real store copies execute; see [migration support and failure recovery](docs/DATA_MIGRATIONS.md).

SwiftData stores explicit raw kind/status strings and throws on unknown values instead of silently changing their meaning. UUIDs identify library entries. LibraryStore looks up the exact typed/provider-qualified media identity before inserting or updating; existing duplicate rows are reported rather than destructively merged. The container uses the default local app store, explicitly disables CloudKit, and inserts **no seed/demo records**. In-memory containers are isolated for tests. SwiftData/context work runs on the main actor. Persistence has no repository layer, authentication, or cloud sync. Metadata networking starts only after a nonempty Search query, never automatically on app startup.

## Validation and current limits

The implementation was authored in a **Linux cloud environment with no Swift compiler, Xcode, Apple SDKs, or iOS simulator**. No iOS build or XCTest run has been completed there. Static project/scheme and source syntax checks are recorded in [the validation report](Documentation/FoundationValidation.md); they do not establish compilation or runtime readiness.

Included tests (363 methods total, all require local macOS/Xcode execution):

- 4 domain and 22 mocked metadata tests.
- 6 persistence container/conversion tests.
- 9 library store and 3 library UI tests.
- 18 SearchModel and 5 Search UI tests.
- 12 detail model/component and 7 detail UI tests.
- 3 rating value, 9 rating persistence and 3 rating UI tests.
- 3 general navigation and 10 app-shell UI tests.
- 17 review/diary store and 5 review/diary UI tests.
- 18 TV progress store/calculation/model tests and 5 TV progress UI tests.
- 14 Library organization/store tests (including 5,000-item data) and 5 organization UI tests.
- 24 dashboard/statistics/persistence tests (including 150 titles and 1,000 watched episodes) and 6 dashboard UI tests.
- 3 stabilization/offline/historical-schema tests, 2 isolated Keychain tests, and 2 beta configuration/accessibility UI tests.
- 14 disk migration/backup tests and 8 disk integrity tests; all await Apple SwiftData execution. See [data migrations](docs/DATA_MIGRATIONS.md).
- 16 metadata lifecycle tests, 3 personal-archive tests, and 1 additional attribution/policy UI test.
- 10 design token/contrast/component-layout and tab-contract methods, all unrun; the [Python asset-contrast check](scripts/validate-design-tokens.py) passes without Apple tooling.
- 34 backup/restore and validation methods, all unrun; see [backup and restore](docs/DATA_BACKUP_AND_RESTORE.md).
- 19 offline metadata/artwork integration methods, all unrun; see [offline capability matrix, cache design and limits](docs/OFFLINE_RELIABILITY.md).
- 28 performance/concurrency methods (13 regressions and 15 benchmarks), all unrun; see [findings, isolation and reproducible harness](docs/PERFORMANCE_CONCURRENCY.md).
- 15 HTTP/authentication/retry hardening tests; see [TMDB networking, credential exposure and live-check status](docs/TMDB_NETWORKING.md).

See [library persistence](docs/library-persistence.md), [details](docs/media-details.md), and [personal ratings](docs/personal-ratings.md) for local commands, migration limits, fixture isolation and screenshot instructions.

Builds and Xcode tests are run locally by the project owner. Do not add GitHub Actions workflows for Xcode builds or tests.

Before accepting this foundation, run the suite in Xcode and manually check:

- Light **and** dark appearance on a small iPhone, including the Settings screen.
- Accessibility text sizes, VoiceOver reading order/control labels, and increased contrast; content should remain readable while scrolling.
- Cold launch with networking disabled, empty library on first launch, and successful local-store initialization after relaunch.
- All tabs and Settings navigation, with no sample content presented as saved data.

Entering a Search query triggers metadata requests with approved local TMDB configuration; poster loading uses ephemeral, cache-disabled requests with bounded memory caching. Other tabs and app startup remain independent of the network. Offline behavior and visual/accessibility quality still need simulator/device confirmation. Distribution signing, production branding, and App Store preparation remain deferred.

## Planned features

Home and Profile now aggregate real local viewing data; later passes may consider separately scoped discovery features. Library organization/sorting is implemented locally. Search, detail pages, local watchlist/status/favorites and personal ratings are implemented. The metadata adapter, Search UI and movie/TV detail pages are implemented, including real-provider credits support; live access remains unverified here. Private reviews and a viewing diary are implemented locally. Episode progress is separate from series-level status and diary events. There is no account system, social publishing, cloud sync, notifications, monetization, or AI functionality.

Recommended next step: run the complete suite and capture Search screenshots locally, verify current provider terms/attribution and authorized live access, then validate library/rating/review/diary migration and relaunch before choosing the next separately scoped feature. Live-provider, simulator and migration validation remain pending. Installed builds can configure their own authorized token in Profile → Settings using the device Keychain; no token is bundled. Release ignores the optional Debug Run-scheme credential. `scripts/validate-v05.sh <SIMULATOR_UUID>` performs local Debug/Release builds and the full test suite; it has not run successfully on this Linux worker.

Search and detail presentation rules and local regression steps: [Search and media experience](docs/SEARCH_MEDIA_EXPERIENCE.md).

Library and tracking presentation rules, regression coverage and remaining usability checks: [Personal tracking UI](docs/PERSONAL_TRACKING_UI.md).

Home/Profile modernization, full screen-family consistency audit, screenshot coverage and validation limits: [UI consistency report](docs/HOME_PROFILE_UI_CONSISTENCY.md).
