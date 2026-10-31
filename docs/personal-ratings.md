# Personal ratings — pass 007

## Rating boundary and UI

`PersonalRating` is a validated value containing integer half-star units **1...10**, representing **0.5...5.0 stars**. Its initializer and Codable decoder reject all other integers. Nil means unrated; zero is not a valid PersonalRating or new saved rating. Presentation divides by two only for display and the compatibility mirror, so canonical comparisons/sorting use precise integers. All ten increments have value/encoding tests.

`PersonalRatingControl` is reusable and explicitly labeled **Your personal rating**. It shows decorative full/half/empty SF Symbols alongside the numeric rating or Unrated. A native menu offers every exact increment and a native Stepper moves one half-star per action; stepping below 0.5 or choosing Unrated clears the rating. No touch location within a star is used. Menu/stepper values and a separate Clear Personal Rating button support VoiceOver/Switch Control and Dynamic Type. Stars are hidden from accessibility to avoid five redundant image announcements. Native control selection and full assistive-technology/layout quality still need local testing.

Detail and Library read the same stored value; `PersonalRatingSummary` can be reused for future Profile presentation. The UI distinguishes personal ratings from provider/community scores; no community score is added. Saves are synchronous explicit transactions: success says Saved, failure presents an alert while LibraryStore rolls back to the previous value. There is no fake saving delay or asynchronous success claimed before saving.

## Persistence and independence

Ratings remain on the existing StoredLibraryEntry, the simplest one-logical-record-per-exact-media-identity model. `LibraryStore.setPersonalRating` uses the same typed/provider-qualified identity lookup and save/rollback path as statuses/favorites. Assigning a rating to a previously unsaved title creates an entry with **no viewing status** (`none` internally), not Watched. Editing reuses the row UUID/added date. Repeating the same rating/snapshot is idempotent. Clearing removes only rating columns, retaining status, favorites, metadata, reserved reviews, dates and the entry. Changing status/favorite never changes rating. Explicit confirmed Remove from Library remains the separate operation that removes the full entry and personal data.

`UserLibraryEntry.rating` now accepts only PersonalRating, so feature code cannot pass arbitrary floating-point values. Persistence is a raw-data boundary: `StoredLibraryEntry.validatedRating()` rejects corrupt canonical units rather than describing them as Unrated. Controls show an unavailable-value message and allow explicit replacement/clearing; reading never silently repairs or discards the raw value.

## Additive schema/legacy compatibility

The existing optional `rating: Double?` column is retained. A new optional nil-default `ratingHalfStarUnits: Int?` column is canonical for new writes. No existing column/entity/constraint is removed, renamed, or made required, and there is no destructive migration, database recreation, or automatic wipe/backfill.

For an unbackfilled legacy row:

- nil or a legacy zero is interpreted as unrated.
- A finite exact 0.5-star increment in 0.5...5.0 is read as the corresponding integer units without rounding or mutating storage.
- Incompatible values (for example 3.3, negative, nonfinite or above five) remain in the old column and produce a validation error until the user explicitly replaces/clears them.
- New rating edits write canonical integer units and a compatible Double mirror; clear writes nil to both. Canonical units take precedence if both columns exist. Status/favorite edits leave both columns untouched.

The new field permits a future numeric rating sort without structural schema changes. PR #010 must account for valid unbackfilled legacy values (fallback sorting or an explicit safe backfill) rather than silently treating every nil canonical column as unrated.

Lightweight migration is intended for the added optional field, but an actual pre-007 persistent store has **not** been migrated on this Linux host. Reopen tests create the current schema and do not prove old-schema migration. Validate upgrades using recoverable copies of both pre-006 and pre-007 stores on macOS before release. Existing duplicate-identity handling and single-writer requirements from [Library persistence](library-persistence.md) still apply; no duplicate cleanup is performed.

## Tests, screenshots and validation limits

Added 15 methods:

- 3 value tests: every increment/encoding, invalid integers/encoded values, exact legacy conversion and zero/unrated semantics.
- 9 persistence tests: movie/TV ratings with no status, edit/repeated save identity, clear preservation, status independence, unrated no-op, failed-save rollback, legacy and invalid-data preservation, persistent container reopening, and validated domain conversion.
- 3 deterministic UI tests: set/edit/clear and Library consistency, native Stepper plus status independence, and process relaunch using the DEBUG-only dedicated UUID test store introduced in #006.

Static grammar/project reference/source membership/asset/whitespace checks pass for all **55 Swift files**. **All 94 tests, builds, real UI, accessibility selection behavior, persistence at runtime and old-schema migration remain unverified here.** This host has no Swift compiler, Xcode, Apple SDK or iOS simulator. Source parsing is not type checking or execution. No GitHub Xcode CI was added.

No genuine simulator screenshot can be produced here. The UI test retains “Personal rating — fixture 4.5 stars” as an xcresult attachment when run locally; that screenshot generation is itself unverified. Export the attachment from the current run in Xcode's Report navigator and attach it to the PR. Keep the fixture marker visible and do not substitute a generated mockup as test evidence.

From the checkout root in Bash, replace the simulator UUID:

```bash
set -euo pipefail
xcodebuild -version
xcrun simctl list devices available
RATING_CHECK_DIR="$(mktemp -d /tmp/MovieTracker-ratings.XXXXXX)"
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -derivedDataPath "$RATING_CHECK_DIR/DerivedData" \
  -resultBundlePath "$RATING_CHECK_DIR/Ratings.xcresult" \
  -only-testing:MovieTrackerTests/PersonalRatingTests \
  -only-testing:MovieTrackerTests/RatingPersistenceTests \
  -only-testing:MovieTrackerUITests/RatingUITests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$RATING_CHECK_DIR/test.log"
```

Confirm 15 selected methods actually execute, then run all 94 without the only-testing arguments. Commands above are instructions, not recorded passing commands. Manually check compact/large iPhones, light/dark, large/largest Dynamic Type, VoiceOver and Switch Control, menu/stepper increments, Unrated versus 0.5, clear, Library/Detail consistency, save failures, relaunch and existing-store migration. Provider network/credential access is not required by these fixture tests.

No written reviews, viewing diaries, community ratings or episode progress is implemented.
