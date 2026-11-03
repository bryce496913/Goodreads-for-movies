# Personal Library and tracking UI (022)

## UI changes and audit

- **Library:** retained efficient native list rendering and 56 × 84 cache-only posters. Combined media type/year into one wrapping line. Viewing status uses a neutral SF Symbol and explicit text; favorites retain a separate heart label. Personal ratings now share the diary's decorative half-star display and explicit rating text. Unrated and invalid values retain distinct labels. Large accessibility text retains vertical poster/content stacking.
- **Filters and local search:** inspected existing native search drawer, segmented media picker (accessibility menu), status and sort menus, Favorites toggle, reset action and differentiated empty states. Retained their placement and behavior so controls remain visible and discoverable, without adding hidden filter drawers or another layout mode. Local projection, stable sorting, source revisions and row identity are unchanged.
- **Ratings:** preserved the 0.5–5.0 precise model, nil/unrated, native menu, stepper and independent clear action. Added a 44-point minimum picker height, explicit clear icon and consistent read-only rating presentation across Library and diary. Details keeps its existing stars/value/menu/stepper. Existing Saved feedback still follows successful persistence only.
- **Reviews:** separated title/privacy, writing area and viewing association into native Form sections. Writing space has a minimum height, not a maximum; the form scrolls. Native top-bar Save/Cancel, keyboard Done, whitespace validation, error alerts, unsaved-change confirmation and blocked interactive dismissal remain. Saved reviews retain selectable, wrapping text; edit actions use the shared action style.
- **Diary:** added existing cache-only poster thumbnails with placeholder fallback. Rows retain title, media type, watched/recorded date distinction, current overall rating and event/title review indicators. Accessibility sizes stack poster and content. Repeat watches keep independent event identity, edit/delete actions and the existing store ordering; no new sorting or grouping changes date semantics. No thumbnail request is made, even when artwork is unavailable or the Library record was removed.
- **TV tracking:** refined the existing shared ProgressDescription used for series, seasons and saved progress. Total watched is emphasized, denominator text is secondary, known percentages keep a native bar and accessible percent value. Zero eligible/incomplete totals retain explicit text instead of invented percentages. Up-to-date uses a filled check symbol plus text and explicitly does not imply permanent series completion. Future/unknown exclusions remain visible.
- **Episodes:** direct watched toggles now precede expandable synopses and have a 44-point minimum height. Native disclosure keeps long season lists compact while preserving full synopsis access. Aired-watched and unwatched batch actions keep their confirmation and now use the existing shared style. “Progress saved” appears only after a synchronous LibraryStore operation returns without error, and is cleared on failure. It indicates the last successful operation, not an unsaved draft. No custom animation or haptic system was added; native controls retain system behavior.

## Data and architecture boundaries

No SwiftData model, persistence operation, relationship, migration, metadata lifecycle, image cache, domain calculation, library projection or progress model changed. All writes still use their original LibraryStore calls and rollback/error handling. Reviews and viewing dates keep original drafts and save semantics. Stars are decorative; text and native controls carry values for VoiceOver/Switch Control. PersonalRatingDisplay is the shared read-only rating treatment; the existing RatingStars and ProgressDescription are reused rather than replaced with competing components.

## Checks and evidence

Linux static checks pass: project parsing and all references/source memberships (three targets), Swift grammar parsing for 135 files, asset JSON parsing, nine adaptive semantic color assets, all 44 intended text contrast pairs >= 4.5:1, and diff whitespace checks. Protected domain/persistence/model/projection/cache files are unchanged. These are not compilation or type-check results.

All **360 XCTest methods are UNRUN** here. No Xcode, Apple SDKs or simulators are available. No Xcode build/device audit or GitHub Xcode CI was added. No runtime before/after screenshots are available. The deterministic mocked UI suites can produce rating, Library and diary screenshots locally.

Added regression methods:

- DesignSystemTests: compact-width layout for no-known-total, zero, partial, up-to-date and incomplete progress plus a half-star rating, in light/dark and normal/largest accessibility text.
- DiaryUITests: whitespace-only save disabled, keyboard Done dismissal and explicit discard of changes.
- TVProgressUITests: expandable episode synopsis, direct toggle, persisted watched state reflected in UI and post-operation save feedback.

Strengthened existing checks for combined Library movie/status/favorite/rating presentation, rating Saved feedback and independently recorded undated diary rows. Existing filtering, sorting, dated/undated ordering, repeat-watch deletion, rating precision, favorites/status independence, rapid progress mutations and disk-backed relaunch suites remain unchanged and require local execution.

## Local validation and deferred checks

Run the shared MovieTracker scheme's MovieTrackerTests and MovieTrackerUITests targets locally. Focus on DesignSystemTests, LibraryOrganizationUITests, RatingUITests, DiaryUITests and TVProgressUITests. Use the existing deterministic `--ui-testing-search` fixtures and isolated test stores. No live metadata is needed.

Inspect compact and large iPhones, dark/light/increased contrast, largest accessibility text, VoiceOver, Switch Control and Reduce Motion. Verify filter reachability with the keyboard open, title/rating wrapping, review Save/Cancel above the keyboard, discard and failure alerts, direct episode toggles, long expanded synopses, batch confirmation, offline placeholders, relaunch persistence and date ordering. Capture screenshots before accepting rendering.

Deferred: native runtime layout/accessibility verification, save-failure presentation under a real persistence fault, and performance measurements. No new “next episode” algorithm or definitive completed-series badge was invented; existing conservative progress semantics remain authoritative. Artwork remains session-cache-only under the current retention policy and may display placeholders after relaunch.
