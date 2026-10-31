# MovieTracker

A native, local-first iPhone foundation for tracking movies and television together. MovieTracker is a temporary working name. This first pass supplies navigation, accessible empty states, domain models, and local persistence infrastructure; it does not yet save titles through the UI.

## Requirements and running

- macOS with the latest stable Xcode and its iOS SDK (Swift 6 language mode).
- Minimum deployment target: **iOS 17.0**, iPhone first.
- SwiftUI, Swift Concurrency, SwiftData, XCTest; **no third-party packages**.

1. Open `MovieTracker.xcodeproj` in Xcode.
2. Select the shared **MovieTracker** scheme and an installed iPhone simulator running iOS 17 or newer.
3. Run with **Product → Run** (`⌘R`). No account, API key, backend, or network connection is required.
4. Run **Product → Test** (`⌘U`) for domain, persistence, and navigation tests.

For a physical iPhone, select your signing team in Signing & Capabilities. **`com.example.MovieTracker` is a placeholder bundle identifier**: replace it with an owned identifier before distribution/App Store submission (and update test identifiers as appropriate). The project intentionally has no final icon or branding. Portrait is the initial supported orientation; system colors and native dynamic text styles support light/dark mode, increased contrast, and Dynamic Type.

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

## Implemented

- Home, Search, Library, and Profile tabs, each owning its own `NavigationStack`.
- Welcome, upcoming activity/recommendation empty states, a local search-field placeholder, and library category placeholders with no fake saved content.
- Profile/statistics empty states and a navigable reserved Settings screen.
- Reusable semantic surfaces, spacing, section headings, and empty-state cards.
- Movie, TV show, typed media identity, viewing status, and user library domain values.
- A SwiftData container and stored library entry with explicit domain conversion, ready for future tracking features.
- A recoverable persistence-error screen that retries opening the store without deleting user data or silently switching to a disposable store.

## Architecture and decisions

```text
MovieTracker/
  App/                 App entry, container lifecycle, root tab navigation
  Core/
    Models/            Foundation-only domain values
    Persistence/       SwiftData storage and container creation
    DesignSystem/      Shared visual primitives
  Features/
    Home/ Search/ Library/ Profile/
  Resources/Assets.xcassets/
MovieTrackerTests/     Domain and in-memory SwiftData tests
MovieTrackerUITests/   Tab and Settings navigation smoke test
MovieTracker.xcodeproj/  Native project and shared scheme
```

Feature views stay together. View models will be introduced when a feature has state/business logic that warrants them; the placeholder screens do not need empty view models. Networking, utilities, preview fixtures, and services will be added only when required, rather than creating unused scaffolding now.

`MediaID` combines a kind (`movie`/`tvShow`) with an opaque string, preventing movie and TV IDs from colliding. External provider identifiers must be mapped into the domain at a future integration boundary. Genre identifiers and poster references are opaque strings; no provider-specific URLs or SDK types enter the domain.

Library entries have one viewing status (`watchlist`, `watching`, `watched`), with an independent favorites flag so a watched title can also be a favorite. Rating/review values are optional foundations, with editing and rating-scale decisions deferred. Timestamps are explicit; future editing logic must update `updatedAt`.

SwiftData stores explicit raw kind/status strings and throws on unknown values instead of silently changing their meaning. UUIDs identify library entries. Domain media identity is separate; duplicate-title policies will be implemented with future library editing. The container uses the default local app store, explicitly disables CloudKit, and inserts **no seed/demo records**. In-memory containers are isolated for tests. SwiftData/context work runs on the main actor. No repositories, protocols, authentication, networking, or cloud services are introduced.

## Validation and current limits

The implementation was authored in a **Linux cloud environment with no Swift compiler, Xcode, Apple SDKs, or iOS simulator**. No iOS build or XCTest run has been completed there. Static project/scheme and source syntax checks are described in the pull request; they do not establish compilation or runtime readiness.

Included tests (require macOS/Xcode):

- Four domain tests: metadata, unknown season count, movie/TV identity and Codable round trip, library statuses/defaults and independent favorites.
- Four persistence tests: empty in-memory initialization, saved/fetched domain round trip for both media kinds, invalid stored enum values, and container isolation.
- One UI test: all four tabs and search field load, Settings push/back navigation, and independent tab navigation state.

The GitHub Actions workflow builds and runs the shared scheme on an available iPhone simulator on macOS. Check its actual results after the PR opens; a configured workflow is not a passing build.

Before accepting this foundation, run the suite in Xcode and manually check:

- Light **and** dark appearance on a small iPhone, including the Settings screen.
- Accessibility text sizes, VoiceOver reading order/control labels, and increased contrast; content should remain readable while scrolling.
- Cold launch with networking disabled, empty library on first launch, and successful local-store initialization after relaunch.
- All tabs and Settings navigation, with no sample content presented as saved data.

No remote requests or external services are implemented. Offline behavior and visual/accessibility quality still need simulator/device confirmation. Final app icon, distribution signing, production branding, and App Store preparation are intentionally deferred.

## Planned features

Future passes can add movie/TV discovery, personal watchlists and tracking, ratings/reviews, seasons and episode progress, viewing history/statistics, and later social discovery/recommendations. None of these are implemented in this foundation. There is no API integration, account system, cloud sync, notifications, monetization, or AI functionality.

Recommended next step: review and validate this foundation on macOS/iPhone before choosing the next feature. Do not add provider integration or tracking until a separate scoped request is approved.
