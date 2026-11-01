# Movie and television details — pass 005

## Architecture and behavior

The existing `MediaDestination` remains the single typed route. Search injects its existing metadata service and a shared session snapshot store into `MediaDetailModel`; future Library/Home callers can construct the same model and screen without a competing detail route. Search results and navigation state are not replaced or reset by detail loading.

`MediaDetailModel` owns main-actor observable loading, error, cancellation, and optional-resource state. SwiftUI's task owns its lifetime/cancellation. A generation UUID and cancellation checks prevent obsolete responses from publishing or entering the snapshot store. Primary movie/TV requests are routed by the full typed ID and validated against that ID before publication. After primary metadata succeeds, cast and image configuration load concurrently. Their failures do not discard useful primary metadata; retry is explicit, never an automatic loop.

Shared components:

- `DetailArtworkHeader` / `DetailArtwork`: bounded card poster (`w342`) and detail backdrop (`w780`) URLs, image progress/fallback states, title/type/year, and VoiceOver artwork descriptions. No original-resolution image fallback or custom image cache.
- `DetailSection`, `DetailFacts`, `DetailGenres`, `DetailSynopsis`, and `DetailCast`: reusable headings, vertically wrapping labeled values, genre labels, complete synopsis text, and a cast preview of at most ten unique people.
- `MovieDetailContent`: release information, runtime, genres, overview and artwork.
- `TVDetailContent`: first-air date, optional episode runtime/status, genres, overview, and noninteractive season/episode totals. No episode rows, progress controls, or tracking are added.
- `MediaDetailView`: composes content and handles loading/error/retry presentation. It does not implement networking.

Movie/TV domain values now retain genre names; TV values also support optional episode counts and series status. `MediaGenre` is located with domain models. Raw TMDB credits stay in `TMDBCredits`; people without a usable identifier/name are skipped, duplicate people are removed, unknown character names remain unavailable, and credits preserve provider ordering. Movie and TV credits use `/movie/{id}/credits` and `/tv/{id}/credits`; these are previews of the returned cast, not a guarantee of comprehensive historical series credits. No actor-profile feature is introduced.

Missing dates, runtimes, counts, statuses, genre lists, cast, and descriptions get explicit unavailable/empty wording. Nonpositive counts/runtimes do not display as misleading zero values. No provider or invented rating/score is displayed. Artwork failure is separate from text failure. Loading and primary-error changes post accessibility announcements (iOS 17+).

All content is in one vertical ScrollView. Text has native Dynamic Type styles and no fixed height/line cap. At accessibility sizes the poster/title layout becomes vertical. Only artwork has an aspect-ratio constraint. Genre labels and fact/cast sections wrap vertically; they do not depend on screen-specific offsets. VoiceOver gets section headings, combined fact/cast labels, and explicit loading/unavailable artwork descriptions. Real-device layout and VoiceOver quality remain pending runtime verification.

## Previously loaded/offline information

`MediaDetailCache` stores at most 20 domain snapshots in memory for the current tab-root lifetime, evicting the oldest inserted identity. Movie/TV IDs remain separate. A primary success is retained even if optional work is canceled. Reopening a cached identity shows the snapshot immediately while attempting a refresh; a failed refresh preserves it with “Showing previously loaded details” and a meaningful error/retry action. With no snapshot, the known Search title/type is shown alongside the loading/error state, without fabricating additional metadata.

This is **not a persistent offline catalog**: snapshots disappear on process termination/eviction, and images are available offline only if the system can still supply previously loaded content. There is no disk metadata cache, no custom image caching/downloading layer, and no SwiftData schema/store reset or migration. The source provider's current retention/caching rules still need verification for this session policy before distribution; do not assume permission for long-lived storage or redistribution.

## Tests and actual validation status

Added:

- 12 model/component tests: movie and TV routing/data, missing fields, offline/configuration/retry behavior, reopening a session snapshot offline, optional cast/artwork failures, successful image URL publication, identity rejection, bounded typed cache, canceled late-response rejection/loading state, and Search service/cache reuse.
- 3 provider tests: genre names and TV status/count mapping, movie/TV credits routes with incomplete/duplicate people, and unavailable zero counts/blank status.
- 6 detail UI tests: movie/back, TV/season summary, missing artwork/synopsis/cast, explicit network retry, offline cached reopen, and long title/synopsis in dark appearance at the largest accessibility text category.

Existing Search debug fixtures were extended rather than adding a competing fixture architecture. All UI detail fixtures require `--ui-testing-search`; `--detail-fixture=<mode>` selects complete/missing/retry/offline-after-load/long data inside that gated DEBUG-only service. Screens remain marked **UI test data**, no fixture image downloads occur, and the existing in-memory UI-test store is retained. Release builds exclude that fixture service. Normal launches never substitute fictional results.

**Executed here:** static Swift grammar parsing for all 45 source/test files, OpenStep project reference/file/source-membership checks for all three targets, shared scheme/asset checks, and whitespace checks. New sources are registered in the intended app/unit/UI targets. These checks do not type-check Swift, expand SwiftData/Observation macros, or run tests.

**Not executed here:** Xcode build, all 67 XCTest/UI methods, real movie/TV/credits retrieval, simulator/device rendering, image loading, accessibility/VoiceOver behavior, and screenshots. This Linux host has no Swift compiler, Xcode, Apple SDK, or iOS simulator. No runtime acceptance criterion is claimed to pass. No GitHub Xcode CI was added.

## Screenshots and local validation

There are **no genuine simulator screenshots from this host**. UI tests retain attachments named “Details — movie fixture” and “Details — television fixture”, plus missing-metadata and large-text/dark screenshots. Run locally and export these from the current `.xcresult` in Xcode's Report navigator; attach them to the PR before approving visual acceptance. Fixture screenshots keep their visible UI test data marker. Do not substitute generated mockups as test evidence.

From the checkout in Bash, use an installed iPhone simulator UUID:

```bash
set -euo pipefail
xcodebuild -version
xcrun simctl list devices available
DETAIL_CHECK_DIR="$(mktemp -d /tmp/MovieTracker-details.XXXXXX)"
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -derivedDataPath "$DETAIL_CHECK_DIR/DerivedData" \
  -resultBundlePath "$DETAIL_CHECK_DIR/Details.xcresult" \
  -only-testing:MovieTrackerTests/MediaDetailTests \
  -only-testing:MovieTrackerTests/MetadataServiceTests \
  -only-testing:MovieTrackerUITests/MediaDetailUITests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$DETAIL_CHECK_DIR/test.log"
```

Confirm the selected **36 methods** execute (12 detail, 18 metadata, 6 UI), then run all **67** without the only-testing arguments. No successful execution of these commands has been recorded here. Preserve exit status via pipefail, use fresh result paths, and keep generated artifacts out of Git.

Manually review both a compact and a larger supported iPhone in light/dark appearance and large/largest accessibility text: long titles and full synopsis scrolling, cast/genre wrapping, accessible loading/errors/artwork descriptions, slow/missing/failing artwork, empty cast/roles, correct movie/TV routing, back-navigation/search preservation, and cached offline reopen. Test a fresh missing-configuration/offline error without a snapshot as well. Portrait remains the supported orientation.

Real-provider verification requires the authorized local Run configuration documented in [metadata-provider.md](metadata-provider.md). The prior documentation/network and credential limitations remain unresolved; new credits requests have not been verified live. Provider terms, image/caching permissions, approved attribution/logo requirements, and production credential architecture remain release prerequisites. The existing TMDB text attribution is retained; no unverified logo or secret is committed.

Personal ratings, reviews, watchlist actions, and episode tracking remain outside this pass.

Pass 009 extends the existing TV route with season/episode progress; the noninteractive-summary-only description above records pass 005. Current behavior is documented in [tv-episode-progress.md](tv-episode-progress.md).
