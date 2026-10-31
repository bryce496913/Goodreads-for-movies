# Private reviews and viewing diary — pass 008

## Data model and identity

The existing StoredLibraryEntry, rating columns, status/favorite fields, dates, snapshot fields and UUID identity are unchanged. Two entities are added to both production and test schemas:

- **StoredPersonalReview**: unique UUID; exact media kind/provider-qualified identifier; private text; created/edited timestamps; optional viewing-event UUID; saved title/domain metadata snapshot; and a legacy-import marker.
- **StoredViewingEvent**: unique UUID; exact media identity; optional watched civil date; recorded/updated timestamps; and an independent title/domain snapshot.

A title may have any number of reviews and viewings but one logical Library entry under the existing single-writer identity rule. New unsaved titles receive a no-status Library entry when the first review/event is saved; neither rating nor status is inferred. A title review may be standalone or explicitly associated with one viewing. Each event can have at most one associated review through store validation. Recording another watch never copies/creates/associates a review automatically.

The only persisted association is the review's optional viewingEventID. History derives its review indicator by that UUID; there is no redundant inverse field, SwiftData relationship, or cascade delete rule. LibraryStore validates the selected event belongs to the same exact media identity and rejects reused review/event IDs belonging to another title. Deleting a review leaves its event untouched. Deleting an event detaches its reviews without deleting or rewriting their text; other watches and the title's rating/status/favorite remain unchanged.

All writes use the same main-actor LibraryStore, dedicated context, explicit save and rollback as the Library/rating features. Creating a review/event and ensuring its Library row happen in one transaction. A failed save cannot leave an empty partial row; failed edits/deletes restore text and associations. Reload publishes a consistent set of Library/reviews/events only after all fetches succeed. Future writers must continue using this store rather than introduce competing contexts.

## Review lifecycle and offline UI

Details show full wrapping private review text, created/edited dates, explicit edit/delete, and Write Review / Record Viewing. Personal Reviews in Library provides direct local reading/editing even if the Library row has been removed. No metadata request is made by the archive or review editor. Each review/event owns a metadata snapshot, with a saved-title fallback if that snapshot is missing or unrecognized; private text is not dependent on successful JSON decoding or remote refresh.

ReviewEditor keeps text/association in local State until Save. Whitespace-only content is disabled in the UI and rejected by the store; valid content, paragraph spacing and long text are preserved. Save upserts the draft UUID, retaining creation date and updating edited date only for changed text/association. The native multiline editor uses Dynamic Type and scrolls long text. Cancel never writes. Dirty forms block interactive swipe dismissal and offer a Discard Changes confirmation on Cancel. Persistence errors leave the draft open with a clear alert. Delete is separately confirmed and never implies deleting an associated viewing.

Multiple standalone reviews are permitted, each with its own UUID. They are intentional user-created records; rewatches do not duplicate them. Review editing reuses the selected UUID. The only overall rating remains on the Library entry, independent of all reviews/events. There is no public publishing, social submission, review upload or cloud sync.

## Diary dates and repeat watches

Viewing History is accessible from Library and sorts by `watchedDate ?? recordedAt` descending, then recordedAt and UUID for deterministic ties. A known old viewing logged today sorts by its old watched date, not today's logging timestamp. An undated event is explicitly labeled **Date recorded**, never “watched today.” The history introduction explains these semantics and that displayed ratings are the user's **current overall title ratings**, not per-watch scores.

Watched dates are optional Gregorian civil dates normalized to UTC midnight. The editor converts between that storage representation and a local DatePicker so changing timezones does not shift the chosen calendar day. RecordedAt is an actual timestamp, displayed in local time and never changed when editing the watched date. UpdatedAt records event edits. A new editor session gets a fresh event UUID; repeated Save of that same draft updates one event. Three watches mean three events and one Library identity.

Users can edit/delete a single event from History. Dated and undated events are both valid. Optional review associations can be selected/cleared in ReviewEditor. TV events are explicitly series-level: logging them or setting a generic Watched status creates no episode history, no episode completion and no progress records. No automatic status/rating changes occur.

## Legacy content and migration safety

Schema changes add two new entity tables; the existing Library entity/fields/constraints are retained. No destructive migration, store reset/recreation or bulk conversion runs. Lightweight migration is intended for entity additions, but **an actual pre-008 store upgrade has not been executed here**. Validate against recoverable old-store copies on macOS before release. Current-schema reopen tests are not proof of legacy-schema migration.

Old text in StoredLibraryEntry.review remains readable as an **Earlier saved review — original date unavailable**. Explicit Edit/Save imports it into the new review table and clears the old column only in the successful transaction. If a user explicitly removes that Library row, nonempty legacy text is first preserved in the review archive in the same transaction. Imported records are labeled **Imported (original date unavailable)** until a later known edit; their new record-creation time is not presented as the original writing date. No reviews are copied during rewatches, status/rating changes, or app startup. Explicit deletion can clear a legacy review without requiring metadata.

Removing a Library row keeps new reviews and viewing events with their own offline snapshots. Personal Reviews and Viewing History remain accessible from an otherwise empty Library. Removal of the Library row still removes that row's rating/status/favorite as the confirmation explains; deleting an individual review/event does not. Ratings and statuses are not migrated or rewritten by review/event edits.

## Tests and observed results

Added **17 unit/store tests** covering create/edit/identity/timestamps, blank validation, dated/undated semantics, three repeat watches/one title, chronological ordering, independent deletion, event edits, wrong-media links/ID reuse, association uniqueness, save rollback, offline archive after Library removal/missing metadata, legacy import/delete/removal preservation, container reinitialization and timezone round trips. Added **4 deterministic UI tests** for create/edit/cancel, confirmed review deletion, multiple series events/deleting one, and private review access/editing after process relaunch with remote metadata forced offline.

Existing UI selectors were also corrected to use `matching(identifier:).firstMatch` on queries rather than `firstMatch` on an already selected element. Explicit button styles keep multiple controls in List rows from sharing automatic row-wide actions.

Passed here: Swift grammar parsing of all **66 Swift files**, Xcode project object/file references and complete app/unit/UI source membership, shared scheme/asset checks, retained Library schema fields, and whitespace checks. These are static checks, not Swift type checking, macro expansion or test execution.

**All 115 tests, the iOS build, UI interaction/layout/accessibility, runtime save/rollback/relaunch and old-schema migration are unverified.** This Linux environment has no Swift compiler, Xcode, Apple SDK or simulator. No GitHub Xcode CI was added; local Xcode validation remains the project owner's workflow.

Run locally from the checkout in Bash with an installed iPhone simulator UUID:

```bash
set -euo pipefail
xcodebuild -version
xcrun simctl list devices available
DIARY_CHECK_DIR="$(mktemp -d /tmp/MovieTracker-diary.XXXXXX)"
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -derivedDataPath "$DIARY_CHECK_DIR/DerivedData" \
  -resultBundlePath "$DIARY_CHECK_DIR/Diary.xcresult" \
  -only-testing:MovieTrackerTests/DiaryStoreTests \
  -only-testing:MovieTrackerUITests/DiaryUITests \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$DIARY_CHECK_DIR/test.log"
```

Confirm **21 selected methods** execute, then run all **115** without only-testing arguments. These commands have not run here. The UI suite uses explicit DEBUG fixtures/in-memory stores, with a fresh UUID dedicated persistent test store for process relaunch; it never clears the real user store and requires no credentials or network. No genuine simulator screenshots or runtime results are available from this host.

Manually verify long reviews at large/largest Dynamic Type, VoiceOver editor/control labels, Save/Cancel/discard, association choices, confirmation/error feedback, movie/TV routing and back navigation, old watches logged today, undated events, timezone changes, repeat watches, per-event edits/deletes, archive access after Library removal, offline relaunch and migration with real old-store copies. No episode-level tracking or public/social reviews are implemented.
