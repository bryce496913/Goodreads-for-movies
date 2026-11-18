# Pass 038 — streamlined movie watch logging

## Before and after

Before this pass, viewing status, diary events, overall personal rating and written reviews were independent writes from Movie Details: Viewing Status → Watched did not create a diary event; Record Viewing created an event without changing status/rating; rating and review editors saved separately. A title may have multiple reviews, at most one review explicitly associated with each viewing event. Rewatches are separate events, not extra Library identities.

Movie Details now has one primary **Log a Watch** action (**Log Again** once the movie is Watched or has viewing history). It opens one native sheet containing a cache-only poster/title/year, watched date, overall half-star rating and optional new review. The former movie Record Viewing button is replaced by this entry; TV Record Viewing and existing historical-event editing are unchanged. General review writing/editing and independent status/rating controls remain available. Movie status selection uses secondary styling alongside the primary logging action.

## User behavior

- Today is the default local civil date. Choose an earlier date or turn **Watched date known** off for a genuinely undated event. The existing `DiaryDates` conversion stores the chosen local year/month/day as a UTC-normalized date; `recordedAt` remains the actual Save instant. Future dates are rejected. Old dated watches retain chronological watched-date ordering rather than appearing as recently watched just because they were recorded today.
- The existing `PersonalRatingControl`/`PersonalRating` handle 0.5–5.0 in half-star steps and Unrated. In this sheet the control edits only a draft and does not show its ordinary persisted Saved confirmation. The label explains that the value is the overall title rating. Untouched ratings are preserved from the current store, including a concurrent change made after the sheet opened; selecting/clearing explicitly replaces it on Save.
- **Add a review for this viewing** is off initially. Turning it on and entering text explicitly creates a new review linked to this new event. Existing text is never prefilled, copied or overwritten on a repeat watch. General/other-event reviews and legacy text remain unchanged. Empty/whitespace-only requested reviews fail validation; up to 1 MiB UTF-8 text matches portable-backup limits. Leaving the option off creates no review.
- Save creates one event, marks the movie Watched, applies an explicitly edited rating and optionally creates that event's review. Existing favorites, collections, reviews, diary and episode data remain. A new sheet creates a new repeat event; one Library identity remains.
- Cancel performs no writes. Edited drafts require Discard Changes or Keep Editing; interactive dismissal is disabled while edits/save are pending. Save and Cancel stay in native navigation chrome, with keyboard Done and Dynamic Type layouts. Errors retain the draft/IDs for retry. Dismissal and the accessibility success announcement occur only after the store call succeeds.

## Atomic transaction and idempotence

`LibraryStore.logMovieWatch` uses exactly one existing `writeTransaction` boundary. It never calls the public committing `saveViewingEvent`, `saveReview`, `setPersonalRating` or `setStatus` from inside that boundary. The Pass 036 mutation ownership guard is unchanged, and the existing nested-writer disk regression now exercises this coordinator too.

The coordinator validates identity/movie kind/date/review, rejects a loaded integrity/read error, checks the stable event ID, uses the existing noncommitting Library-entry helper, stages status and explicitly requested rating fields, creates the existing `StoredViewingEvent`, and optionally creates the existing `StoredPersonalReview` with its viewing UUID. Review-ID conflicts abort the staged event/rating/status too. The existing integrity audit/save/rollback/index/publication handles the complete graph. There is no asynchronous network or suspension inside the transaction, second ModelContext, new persistent entity, schema/migration change or backup-format change. Rating writes maintain the same store-owned legacy compatibility mirror as the existing rating writer; UI code never touches persisted columns.

Each sheet owns fixed event/review UUIDs. The draft model rejects reentry while saving and subsequent submissions after success. A repeated store request with the same event UUID/media identity is a no-op; it does not overwrite later ratings/reviews or create another viewing. A collision with another title is rejected. A failed save rolls back, keeps the IDs/draft and permits retry. The operation publishes one committed revision; existing Library, Detail, Diary, Home and Profile dependencies refresh through the normal store arrays/indexes/revision pipeline.

## Offline, retention and backup

The sheet and writer have no provider/transport dependency and do not fetch metadata before logging. The header and staged entities use available local data or the established typed identity placeholder; expired TMDB payloads are sanitized before staging and no retrieval lease is renewed. The 150-day policy and blocked persistent-artwork rights gate are unchanged. `LibraryCachedPoster` reads only the shared bounded memory cache, with a fixed-size placeholder when missing; no disk cache or guaranteed restart artwork.

Portable personal-only v2/v1 backups already include the Library status/rating, event UUID/dates and review text/association. Those formats need no new field. Restoring never reintroduces provider payloads. Frozen historical and current schema/entity declarations remain unchanged.

## Tests and actual evidence

Added **15 unit methods** for dated/undated logs, every valid half-star/explicit clear, associated review, repeat preservation, one actual save/idempotence, failed-save rollback/retry, review conflict after staging, invalid dates/reviews/TV identities, cross-title event collision, draft cancel/double-submit, failed draft retry, unchanged/concurrently edited rating, timezone conversion, diary ordering, expired metadata, disk reopening and backup restore. Extended the existing nested-writer disk test with the logging coordinator.

Added **4 UI methods** for combined rating/review plus repeat, pristine/edited cancellation, largest-text/keyboard-safe undated review and saved-title logging after offline relaunch. Updated the existing shell cancellation regression to use the movie logging replacement; the TV diary regression remains unchanged. The suite inventory is **407 unit/benchmark + 84 UI = 491 methods**.

Executed in Linux:

- Project OpenStep parsing/references/complete source membership in all three targets, Swift grammar parsing for **152** files, asset JSON: **PASS**. Grammar is not compilation/type checking.
- Adaptive design-token validation: **PASS**, all 44 intended text pairs ≥4.5:1.
- Original build configurations/PBXProject settings preserved; frozen schema/entity declarations unchanged: **PASS**.
- Whitespace and changed documentation link checks: **PASS**.

**All new/changed native tests and this branch's compilation are UNRUN.** No Swift compiler, Xcode, iOS SDK, simulator or physical phone is available to the cloud agent. The owner's earlier all-tests-passed report (Xcode 26.5, iPhone 14 Pro, iOS 27.0.1) applies to their earlier tested code; it is not evidence for this new logging flow. No screenshot or runtime/performance success is claimed. UI tests attach screenshots when executed. No GitHub Xcode CI was added.

## Local validation

Run the shared scheme on a dedicated installed test simulator, then your existing iPhone setup:

```sh
scripts/validate-v06.sh <installed-test-simulator-UUID>
# Or target the new tests first, then run the full shared scheme:
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -only-testing:MovieTrackerTests/MovieWatchLogTests \
  -only-testing:MovieTrackerTests/DataIntegrityTests \
  -only-testing:MovieTrackerUITests/MovieWatchLogUITests \
  CODE_SIGNING_ALLOWED=NO
```

Verify default-today, past/undated watches, optional/changed/cleared/preserved ratings, new linked review versus general review, cancel/discard, double taps and injected failed saves. Confirm one movie/three events after three separate logs, existing review/favorite/collections remain, and Library/Home/Profile/Diary/Detail refresh. Test missing/expired metadata with networking unavailable, offline force-quit/relaunch, backup restore, compact/largest-text/light/dark/VoiceOver/Switch Control, keyboard Save/Cancel/Done and scrolling. Native date/timezone, transaction/rollback, migration and actual UI behavior still require Apple-framework evidence. Do not reset valuable user stores. No merge, TestFlight upload or Pass 039 was performed.


## V0.7 integration follow-up — Pass 043

The [V0.7 test plan](V0.7_TEST_PLAN.md) maps this feature to existing and new cross-feature regressions and records current execution limits. Production behavior, migration definitions, metadata receipts and personal backup formats are unchanged in the stabilization pass. Supported cloud static checks pass; native functional, disk/relaunch, accessibility and performance results remain unverified for this revision. Persistent artwork remains separately blocked.
