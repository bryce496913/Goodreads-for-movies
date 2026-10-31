# MovieTracker

A native, local-first iPhone foundation for tracking movies and television together. MovieTracker is a temporary working name. The app supplies navigation, accessible empty states, domain models, local persistence infrastructure, and an opt-in metadata service. Search now finds movie and TV metadata with authorized local TMDB configuration; library saving is not yet implemented.

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
- Functional Search with a 300 ms debounce, All/Movies/TV Shows filters, loading/empty/retry states, sized poster thumbnails, explicit duplicate-safe pagination, and typed minimal detail destinations. See [Search behavior and validation](docs/search-discovery.md).
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

`MediaID` combines a kind (`movie`/`tvShow`) with an opaque string, preventing movie and TV IDs from colliding. External provider identifiers must be mapped into the domain at a future integration boundary. Genre identifiers and poster references are opaque strings; no provider-specific URLs or SDK types enter the domain.

Library entries have one viewing status (`watchlist`, `watching`, `watched`), with an independent favorites flag so a watched title can also be a favorite. Rating/review values are optional foundations, with editing and rating-scale decisions deferred. Timestamps are explicit; future editing logic must update `updatedAt`.

SwiftData stores explicit raw kind/status strings and throws on unknown values instead of silently changing their meaning. UUIDs identify library entries. Domain media identity is separate; duplicate-title policies will be implemented with future library editing. The container uses the default local app store, explicitly disables CloudKit, and inserts **no seed/demo records**. In-memory containers are isolated for tests. SwiftData/context work runs on the main actor. Persistence has no repository layer, authentication, or cloud sync. Metadata networking starts only after a nonempty Search query, never automatically on app startup.

## Validation and current limits

The implementation was authored in a **Linux cloud environment with no Swift compiler, Xcode, Apple SDKs, or iOS simulator**. No iOS build or XCTest run has been completed there. Static project/scheme and source syntax checks are recorded in [the validation report](Documentation/FoundationValidation.md); they do not establish compilation or runtime readiness.

Included tests (46 methods total, all require local macOS/Xcode execution):

- Thirteen SearchModel tests for normalization, deterministic debounce coordination, cancellation/stale-result protection, filters, pagination/deduplication, retry states, missing configuration, and year/navigation identity.
- Five Search UI tests for mixed results, selection/state, clearing, filters/pagination, empty results, and error/retry; debug fixtures require an explicit launch argument and include screenshot attachments.

- Fifteen additional metadata-service tests (unrun here) use injected transports and a fake credential, covering parsing, mapping, errors, pagination, cancellation, and artwork. Run locally with no TMDB credential; see [metadata validation instructions](docs/metadata-provider.md#validation-record-and-local-checks).
- Four domain tests: metadata, unknown season count, movie/TV identity and Codable round trip, library statuses/defaults and independent favorites.
- Six persistence tests: empty in-memory initialization, saved/fetched domain round trip for both media kinds, invalid stored enum values, container isolation, isolated on-disk save/reopen, and failure for an unusable store path without changing existing data.
- Three UI tests: all four tabs/search field and Settings push/back with independent navigation state; background/foreground and cold relaunch; Settings reachability at the largest accessibility text category. Assertions use accessibility identifiers for combined cards and scroll to controls rather than assuming a screen height.

Builds and Xcode tests are run locally by the project owner. Do not add GitHub Actions workflows for Xcode builds or tests.

Before accepting this foundation, run the suite in Xcode and manually check:

- Light **and** dark appearance on a small iPhone, including the Settings screen.
- Accessibility text sizes, VoiceOver reading order/control labels, and increased contrast; content should remain readable while scrolling.
- Cold launch with networking disabled, empty library on first launch, and successful local-store initialization after relaunch.
- All tabs and Settings navigation, with no sample content presented as saved data.

Entering a Search query triggers metadata requests with approved local TMDB configuration; poster loading uses AsyncImage. Other tabs and app startup remain independent of the network. Offline behavior and visual/accessibility quality still need simulator/device confirmation. Final app icon, distribution signing, production branding, and App Store preparation are intentionally deferred.

## Planned features

Future passes can add movie/TV discovery, personal watchlists and tracking, ratings/reviews, seasons and episode progress, viewing history/statistics, and later social discovery/recommendations. None of these are implemented in this foundation. The metadata adapter and Search UI are implemented; the typed Details destination currently shows only the selected title, type, and year. There is no account system, cloud sync, notifications, monetization, or AI functionality.

Recommended next step: run the complete suite and capture Search screenshots locally, verify current provider terms/attribution and authorized live access, then review before the separately scoped full Details pass. Tracking remains unimplemented.
