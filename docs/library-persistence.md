# Persistent library — pass 006

LibraryStore is the single main-actor writer. Identity is the exact pair `(mediaKind, mediaValue)`: the opaque value includes the provider namespace (`tmdb:123`), so namespace and media type both participate. Lookup compares fields directly, avoiding delimiter ambiguities. Repeated saves update one row; unchanged operations do not advance timestamps. Existing duplicate rows cause a visible mutation error, not silent merging/deletion or a third row. The current app is single-process/single-writer; all future writers must use this store. There is no new database uniqueness constraint that could break existing duplicate data during migration.

Watchlist/Watching/Watched remain mutually exclusive. Movie Watching is rejected at the store boundary. Nil status uses the explicit stored sentinel `none`; removing Watchlist clears status but preserves the entry and favorites/reserved personal fields. Favorites are independent and may create an entry with no active status. Removal is separate, confirmed, and scoped to the exact identity. Dates added are stable; meaningful edits update dates updated.

A dedicated ModelContext disables autosave. Explicit save failures roll back only that writer's pending transaction and surface a sanitized error. Successful mutations refresh the observable entries collection used by both Details and Library. Fetch failures are visible with Retry Library. Title/type/year/status/favorite rows require no provider call; thumbnails use saved references/resolved URLs or placeholders. Library uses the same MediaDestination and detail model as Search, seeding it with the saved domain snapshot so a failed remote refresh cannot erase personal data or the saved text.

## SwiftData changes and migration

The existing StoredLibraryEntry entity, UUID unique attribute, string status field, rating/review columns and dates are retained. Only optional nil-default metadata fields are added: savedTitle, savedYear, savedPosterReference, savedPosterURL, snapshotData. The snapshot is sorted-key JSON of Codable domain values, not raw API DTOs or credentials. Legacy rows with no snapshot remain visible with an honest metadata-unavailable label; saving from a detail page can fill the snapshot while preserving personal fields. Corrupt/unrecognized snapshot data does not delete a row. Replacing future nonoptional Codable fields requires compatibility handling.

These additive optional columns are intended for SwiftData lightweight migration. No destructive migration, store recreation, reset, uniqueness backfill, or automatic duplicate cleanup is implemented. Existing-store upgrade must be tested on macOS against a copy of an actual pre-006 store before release; it has NOT been executed here. In-memory/persistent reopening tests use the new schema and do not prove old-schema migration. Keep a recoverable copy of user data when validating migration. Provider permissions for stored metadata remain a release requirement documented in metadata-provider.md; this task does not establish a content license or image offline guarantee.

## Tests and validation

Added 9 store tests and 3 UI tests (79 total methods including the existing suite): movie/TV Watchlist separation, watching-to-watched and favorite preservation, repeated operations/provider namespaces, nil status, precise removal, save rollback, legacy duplicates, persistent container reopening/snapshots, reserved data preservation, immediate UI changes, removal, and process relaunch with offline saved details.

UI tests use the existing DEBUG-only explicit fixture flag. An additional validated UUID flag `--ui-testing-library-store=<UUID>` selects a dedicated Application Support/LibraryUITests/<UUID> store only when --ui-testing-search is also present. It never selects or deletes the normal user store; Release ignores it. Ordinary UI tests remain in-memory. Relaunch tests use fresh UUID stores and do not seed demonstration data automatically. Navigation smoke tests now use isolated fixtures, avoiding assumptions about a user's real saved library.

Static parsing/reference/membership checks passed for all 50 Swift files; whitespace checks passed. Xcode, Swift compiler and simulators remain unavailable: all 79 tests, live UI, save-failure presentation, runtime persistence and migration remain unverified. No GitHub Xcode CI was added.

Run locally with the shared MovieTracker scheme and an installed simulator:

```sh
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -only-testing:MovieTrackerTests/LibraryStoreTests \
  -only-testing:MovieTrackerUITests/LibraryUITests CODE_SIGNING_ALLOWED=NO
```

Confirm all 12 selected methods run, then run the full suite. Manually verify save, favorite/status changes, clearing, confirmed removal, immediate Library/Detail consistency, offline rows and saved details, missing artwork, process relaunch, and existing-store migration on compact/large iPhones and accessibility text sizes. Do not treat source parsing or an unexecuted test as runtime evidence. No ratings/reviews/episode-progress editing is included in this pass.
