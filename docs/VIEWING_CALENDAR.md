# Pass 039 — viewing calendar and diary

## Entry, navigation and presentation

Library → More in Library → Viewing History now offers native **List / Calendar** selection. List remains the default and keeps the existing newest-first order (watched date, or recorded timestamp only for undated entries). An Undated-only toggle and a Calendar → Show Undated in List action keep unknown dates reachable and editable. No fifth tab or new navigation architecture.

Calendar opens on the current month/day. Previous/Next move one month, selecting its first day; Today returns to the current month/day. Selecting a day scrolls the native List to its events. Dated repeats and different titles remain separate rows using their existing event UUIDs. The selected month/day and presentation mode survive Details/back, sheet editing and tab switching while this History view remains alive. They are transient: reopening a new History instance or restarting the app begins at the current month; no preference/entity is persisted.

Calendar and List share one event row implementation and the existing typed `MediaDestination`, `ViewingEventEditor` and confirmed `deleteViewingEvent` writer. Rows show cache-only poster/placeholder, title/type/year, watched date (or explicitly Date recorded), current overall rating and event-specific/title review indicator. Dated rows also show a separate recorded timestamp to help distinguish repeat logs. Viewing dates, recorded times and edited times are never interchanged; editing does not regroup by updatedAt. Metadata is passed through the existing expiry policy before display/editing, with identity-only fallback when unavailable.

## Date policy

The existing model defines watchedDate as a **Gregorian civil date encoded at UTC midnight**, not a real viewing-time instant. `DiaryDates.storageDate` already converts the user's chosen local year/month/day into that storage convention. This pass does not change it or any saved timestamp.

Grouping extracts that saved UTC civil day, reconstructs the same Gregorian year/month/day in the user's selected time zone, and then uses the user's current Calendar to obtain the display-day key. It does **not** treat UTC midnight as an instant to shift west/east, so January 1 does not become December 31 merely because the phone's time zone changed. Locale, calendar identifier, explicit firstWeekday and time zone drive month construction, headings, weekday order and day labels. Leap/month/year boundaries and DST use Calendar arithmetic, not fixed 86,400-second grid steps.

The persisted model does not retain an original time zone, calendar identifier or time of viewing. It cannot recover those facts for arbitrary legacy instants stored outside the documented civil-date convention. No destructive migration is attempted. A civil date that does not exist in the selected zone (for example, 2011-12-30 in Pacific/Apia) fails a round-trip check instead of silently moving to another day. It is counted as unavailable for Calendar, remains in the full List with its saved-date label and explanation, and can be edited through the normal editor. Nonfinite/corrupt date values are not assigned invented calendar dates. Month slots preserve weekday alignment even when a local civil day was historically skipped.

Undated events have watchedDate == nil. They never enter calendar groups using recordedAt, even if recorded today. Their recorded timestamp stays visible and determines their existing List ordering. No presentation operation writes a date.

## Read-only architecture and performance

`ViewingCalendarProjection` builds a Sendable date/UUID index and a bounded month value. It receives no ModelContext, provider client or SwiftData models. Groups use local calendar-day Date keys and arrays of stable event UUIDs. Within a day, records sort newest recordedAt first, then UUID ascending for deterministic ties. Records are never merged by media identity or date.

`ViewingCalendarModel` owns transient month/day state and main-actor live-record lookup. On source revisions it copies only UUID/watchedDate/recordedAt; a cancellable detached task groups/sorts those immutable stamps. All live records remain on the context actor. Cancellation/generation checks prevent superseded work publishing. Ready state is keyed to the actual prepared calendar/locale/revision so canceled time-zone changes cannot reuse old day keys.

Ordinary navigation/unchanged source keys reuse the prepared index. Metadata/rating-only revisions reuse grouping when copied stamps and the prepared configuration are unchanged, while refreshing record references. Source capture still scales linearly with history size; it is not a paged store. Day selection reads one cached group and maps its IDs, without regrouping or sorting all history. Month days/labels are cached until month/configuration changes. The existing indexed persistence and store ownership remain untouched; no second fetch system or redundant persistent calendar records.

## Accessibility and offline behavior

Shared Paper/Ink/Ember colors, typography, spacing, action/empty/loading styles and fixed poster frames are reused. Weekday order respects the user's firstWeekday; complete VoiceOver day labels include weekday/date, count and selected state. Days with events display both a film symbol and a numeric count, not color alone. Selected-day announcements occur only after counts are ready; day controls disable while grouping is pending. Month navigation has explicit Previous/Next labels.

Day and month controls keep 44-point minimum targets. A compact screen can horizontally scroll the seven-column grid rather than shrink hit targets; at accessibility text sizes, a vertical day list replaces the grid, and the mode picker uses a native menu. Selecting a day scrolls to its event section without a custom animation. Native outer List margins/safe areas and the existing editor's keyboard behavior remain. No new haptic/animation system; Reduce Motion is not overridden.

All calendar grouping/display reads local personal events. Opening a saved row requires no metadata request to render; opening Details retains its existing refresh/cached/error behavior. Artwork still uses the shared bounded memory cache only; disk artwork remains BLOCKED. Missing artwork after relaunch is expected. Metadata retention, personal ownership, backup v2/v1, schema/migration stages and all persistence writers are unchanged.

## Tests and actual validation

Added **14 unit methods** for month lengths/leap/locale week starts/non-Gregorian calendars, independent same-day events and deterministic ties, undated/invalid values, extreme time-zone/year boundaries, DST, skipped civil dates, month/day state, actual date edits/deletion with rating/review preservation, cached source revisions, cancellation/configuration replacement, disk reopening and 5,000 IDs. Added a 5,000-event XCTest clock/memory benchmark, without timing thresholds or claimed measurements.

Added **4 UI methods** for month navigation/List switching, separate day events, Details/back/tab state, one-event deletion, undated reachability, largest text/dark layout, movie/TV routing and offline disk-backed process relaunch. Explicit DEBUG `--ui-testing-viewing-calendar` fixtures run only inside existing isolated UI-test stores and create real local test events; production is never seeded.

Executed on Linux:

- OpenStep project/references/complete source membership for three targets, Swift grammar for **157** files and asset JSON: **PASS**. Grammar is not compilation/type checking or macro execution.
- Adaptive design tokens/44 intended text contrast pairs: **PASS**.
- Original build configurations/PBXProject settings and frozen/current schema/entity declarations preserved: **PASS**.
- Whitespace and relative documentation links: **PASS**.

**New/changed native XCTest, compilation, simulator/device UI, actual offline force-quit/relaunch and benchmark measurements are UNRUN.** The owner's earlier device test success is historical evidence for their earlier revision, not this new Calendar. No screenshots or performance improvement are fabricated; UI tests attach images only when actually executed. No GitHub Xcode CI was added.

## Owner verification

```sh
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -only-testing:MovieTrackerTests/ViewingCalendarTests \
  -only-testing:MovieTrackerUITests/ViewingCalendarUITests \
  CODE_SIGNING_ALLOWED=NO
# Then run the full existing scheme:
scripts/validate-v06.sh <installed-test-simulator-UUID>
```

Run LargeLibraryBenchmarks in comparable Release conditions to measure grouping; no native baseline/updated timing is available here. Manually check Gregorian and another preferred calendar, Sunday/Monday week start, DST, west/east zones and year/leap boundaries. Verify current-month initial state, count/selected announcements, horizontal reachability on compact screens, vertical large-text flow, VoiceOver/Switch Control, light/dark/high contrast, native editor keyboard/save/cancel, separate repeat events, date edit relocation, one-event deletion and preserved reviews/ratings. Open movie/TV Details and return, switch tabs and switch List/Calendar; transient selection should remain until the History instance is replaced. Relaunch offline and verify saved events/groups rebuild while initial month resets to current; unknown dates remain unknown. Keep valuable databases intact. No merge or Pass 040.
