# MovieTracker

A native, local-first iPhone foundation for tracking movies and television together. MovieTracker is a temporary working name. The app supplies navigation, accessible empty states, domain models, local persistence infrastructure, and an opt-in metadata service. Search now finds movie and TV metadata with authorized local TMDB configuration; titles can be saved locally with independent favorites and viewing statuses.

## Requirements and running

- macOS with the latest stable Xcode and its iOS SDK (Swift 6 language mode).
- Minimum deployment target: **iOS 17.0**, iPhone first.
- SwiftUI, Swift Concurrency, SwiftData, XCTest; **no third-party packages**.

1. Open `MovieTracker.xcodeproj` in Xcode.
2. Select the shared **MovieTracker** scheme and an installed iPhone simulator running iOS 17 or newer.
3. Run with **Product → Run** (`⌘R`). App launch requires no account, API key, backend, or network connection. Real Search requires authorized local TMDB configuration and network access; see [provider setup](docs/metadata-provider.md).
4. Run **Product → Test** (`⌘U`) for domain, persistence, and navigation tests.

For a physical iPhone, select your signing team in Signing & Capabilities. Automatic signing is enabled; no personal team is committed. You may also pass `DEVELOPMENT_TEAM=<YOUR_TEAM_ID>` to `xcodebuild` for a device build. **`com.example.MovieTracker` is a placeholder bundle identifier**: replace it with an owned identifier before distribution/App Store submission (and update test identifiers as appropriate). The project intentionally has no final icon or branding. Portrait is the initial supported orientation; system colors and native dynamic text styles support light/dark mode, increased contrast, and Dynamic Type.

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

- Home, Search, Library, and Profile tabs, each owning its own `NavigationStack`.
- Welcome, upcoming activity/recommendation empty states, library category placeholders with no fake saved content.
- Profile/statistics empty states and a navigable reserved Settings screen.
- Reusable semantic surfaces, spacing, section headings, and empty-state cards.
- Movie, TV show, typed media identity, viewing status, and user library domain values.
- A SwiftData container and stored library entry with explicit domain conversion, ready for future tracking features.
- An injectable, async TMDB metadata service for movie/TV/combined search, details, genres, and sized artwork URLs; connected to the Search tab. See [provider evaluation and local setup](docs/metadata-provider.md). Current terms and live retrieval remain unverified because provider documentation access is blocked and no credential is configured.
- Functional Search with a 300 ms debounce, All/Movies/TV Shows filters, loading/empty/retry states, sized poster thumbnails, explicit duplicate-safe pagination, and typed movie/TV detail pages. See [Search behavior and validation](docs/search-discovery.md).
- Movie/TV detail pages with shared artwork, genre, synopsis, cast and metadata sections, TV season summaries, partial-failure recovery and session snapshots for previously loaded details. See [detail architecture and validation](docs/media-details.md).
- Persistent Library rows and detail actions for Watchlist, TV Watching, Watched, independent favorites, clear status and removal. Saved metadata supports offline title/detail display; see [library persistence](docs/library-persistence.md).
- Personal movie/TV ratings from 0.5–5.0 stars using precise integer half-star units, independent of viewing status, with native accessible editing and Library summaries. See [personal ratings and migration](docs/personal-ratings.md).
- Private written reviews and a local viewing diary with optional watched dates, repeat watches, offline archives, explicit associations and independent deletion. See [review lifecycle, diary semantics and migration](docs/reviews-viewing-history.md).
- TV season/episode tracking with direct watched toggles, saved offline lists, confirmed season actions, and conservative aired-episode progress. See [TV progress rules and validation](docs/tv-episode-progress.md).
- A recoverable persistence-error screen that retries opening the store without deleting user data or silently switching to a disposable store.

## Architecture and decisions

```text
MovieTracker/
  App/                 App entry, container lifecycle, root tab navigation
  Core/
    Models/            Foundation-only domain values
    Persistence/       SwiftData storage and container creation
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

SwiftData stores explicit raw kind/status strings and throws on unknown values instead of silently changing their meaning. UUIDs identify library entries. LibraryStore looks up the exact typed/provider-qualified media identity before inserting or updating; existing duplicate rows are reported rather than destructively merged. The container uses the default local app store, explicitly disables CloudKit, and inserts **no seed/demo records**. In-memory containers are isolated for tests. SwiftData/context work runs on the main actor. Persistence has no repository layer, authentication, or cloud sync. Metadata networking starts only after a nonempty Search query, never automatically on app startup.

## Validation and current limits

The implementation was authored in a **Linux cloud environment with no Swift compiler, Xcode, Apple SDKs, or iOS simulator**. No iOS build or XCTest run has been completed there. Static project/scheme and source syntax checks are recorded in [the validation report](Documentation/FoundationValidation.md); they do not establish compilation or runtime readiness.

Included tests (140 methods total, all require local macOS/Xcode execution):

- 4 domain and 21 mocked metadata tests.
- 6 persistence container/conversion tests.
- 9 library store and 3 library UI tests.
- 13 SearchModel and 5 Search UI tests.
- 12 detail model/component and 6 detail UI tests.
- 3 rating value, 9 rating persistence and 3 rating UI tests.
- 3 general navigation UI tests.
- 17 review/diary store and 4 review/diary UI tests.
- 18 TV progress store/calculation/model tests and 4 TV progress UI tests.

See [library persistence](docs/library-persistence.md), [details](docs/media-details.md), and [personal ratings](docs/personal-ratings.md) for local commands, migration limits, fixture isolation and screenshot instructions.

Builds and Xcode tests are run locally by the project owner. Do not add GitHub Actions workflows for Xcode builds or tests.

Before accepting this foundation, run the suite in Xcode and manually check:

- Light **and** dark appearance on a small iPhone, including the Settings screen.
- Accessibility text sizes, VoiceOver reading order/control labels, and increased contrast; content should remain readable while scrolling.
- Cold launch with networking disabled, empty library on first launch, and successful local-store initialization after relaunch.
- All tabs and Settings navigation, with no sample content presented as saved data.

Entering a Search query triggers metadata requests with approved local TMDB configuration; poster loading uses AsyncImage. Other tabs and app startup remain independent of the network. Offline behavior and visual/accessibility quality still need simulator/device confirmation. Final app icon, distribution signing, production branding, and App Store preparation are intentionally deferred.

## Planned features

Future passes may add viewing statistics, sorting/filtering, and later social discovery/recommendations. Search, detail pages, local watchlist/status/favorites and personal ratings are implemented. The metadata adapter, Search UI and movie/TV detail pages are implemented, including real-provider credits support; live access remains unverified here. Private reviews and a viewing diary are implemented locally. Episode progress is separate from series-level status and diary events. There is no account system, social publishing, cloud sync, notifications, monetization, or AI functionality.

Recommended next step: run the complete suite and capture Search screenshots locally, verify current provider terms/attribution and authorized live access, then validate library/rating/review/diary migration and relaunch before choosing the next separately scoped feature. Live-provider, simulator and migration validation remain pending.
