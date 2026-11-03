# Home, Profile and visual consistency (023)

## Modernization summary

Home now presents Continue Watching, Recent Personal Activity, Recently Watched and Watchlist in that order. Existing next-episode and series links are retained. Continue Watching uses the existing progress component in a compact mode, with explicit watched/eligible counts, a native bar only when a percentage is known, and an accessible percentage value. The next-episode link has a familiar play symbol and a 44-point minimum height. Unknown progress/next episode metadata remains explicit. No progress or recommendation is invented.

A completely empty Home presents the existing welcoming state and Search action, rather than four additional repetitive empty sections. Once personal data exists, section-specific empty explanations and history/Library shortcuts remain. The native four-tab routes are unchanged.

Shared dashboard title rows use consistent 56 × 84 cache-only posters, one wrapping media/year line and the existing half-star rating treatment. At accessibility text sizes, artwork and text stack vertically. Recent-watch rows retain actual watched dates; undated Profile diary rows explicitly show a recorded date with an unknown-watch-date label. Recent Activity continues to identify its record timestamp separately from any watched date. Event identities/order and snapshot calculations are unchanged.

Profile uses one plain adaptive metric row: short labels/counts align horizontally when they fit; long strings and accessibility sizes stack. Combined VoiceOver labels retain the full metric definition and value. Average rating keeps its explicit unavailable state. All eight counts, existing definitions and recent diary/navigation remain; no decorative metric grid or new statistic was added.

Settings credential save, personal export and restore use existing action styling with SF Symbols. Data-management links remain directly visible. About/Credits uses spacing/radius tokens for the existing TMDB logo backing. The white logo backing is intentionally retained for brand artwork contrast. All provider notices, privacy text, cache policy and external links remain unchanged; credentials and personal-data operations are untouched.

## Shared components and boundaries

- DashboardTitleRow and DashboardDiaryRow reuse existing PosterFrame/LibraryCachedPoster and PersonalRatingDisplay; no network image request was introduced.
- DashboardMetricRow provides one adaptive, read-only metric treatment.
- ProgressDescription gains a default-off compact presentation option used only by Home. Full season/series summaries retain their existing information; series denominators explicitly identify regular episodes. The compact mode omits redundant total-watched and exclusion footnotes; known-aired denominator and uncertainty text remain, with full exclusions available in series/season detail.
- AppActionStyle and existing native list/form/navigation/editor helpers remain authoritative.

No domain models, SwiftData schemas, migrations, LibraryStore writes, metadata/cache services, dashboard aggregation/input/snapshot/model, search/progress models or Library projections changed. No new persistence, feature, automatic request, animation or haptic system was added. Save feedback remains tied to existing successful operations. Native controls retain system motion behavior; Reduce Motion still requires device verification.

## Visual consistency review

This is a source-level audit, not a runtime certification. Existing native List/Form scrolling and semantic adaptive surfaces remain across all screen families.

| Screen family inspected | Presentation decision / remaining check |
| --- | --- |
| Root shell / four tabs | Keep native TabView, independent stacks and existing titles; verify state/back navigation locally. |
| Home / dashboard | Reorder genuine data, compact progress, adaptive artwork rows, focused empty state; verify dense and sparse libraries. |
| Profile | Adaptive plain metric rows and explicit definitions; verify long labels/largest text. |
| Search / results | Retain native search, filters, row posters, retry/pagination and clear empty/error states from 021. |
| Movie / TV details | Retain artwork/title hierarchy, shared section styles, visible personal actions and missing-artwork fallbacks. |
| Library / local filters | Keep 022 rows, independent status/favorite/rating, stable local search/sorting and differentiated empty states. |
| Rating editor | Keep native menu/stepper and precise half-star model; stars remain decorative. |
| Reviews / review editor | Keep selectable long reviews, Form writing area, keyboard Done and protected Save/Cancel. |
| Diary / viewing editor | Keep explicit watched/recorded labels, independent repeat events and protected date edits. |
| TV saved progress / seasons / episodes | Reuse progress, direct watched toggles and native synopsis disclosure; no completion semantics change. |
| Settings | Shared non-destructive action style; native destructive credential confirmation, secure entry and keyboard dismissal retained. |
| Export / restore preview | Style existing actions only; file pickers, privacy, conflict preview and confirmation remain intact. |
| About / Credits | Preserve TMDB logo/white backing, all attribution and legal/privacy notices. |
| Startup/persistence errors | Retain recoverable error/retry behavior; no destructive reset or empty-store fallback introduced. |

No custom animations, shadows, fixed-font sizes or new hard-coded colors were introduced. Light/dark/high-contrast colors come from the existing semantic assets. No feature was removed to simplify the visuals. Runtime contrast over imagery, touch targets, clipping, keyboard reachability, long reviews and VoiceOver traversal remain local checks.

## Automated evidence

Passed on Linux:

- Xcode project OpenStep parsing, all referenced files and complete source membership in all three targets.
- Swift grammar parsing for 135 source/test files — not compilation or type checking.
- Asset JSON parsing and nine adaptive color assets, with all 44 intended text contrast pairs >= 4.5:1.
- Whitespace checks, unchanged attribution strings and protected business/model/persistence files.

All **363 XCTest methods are UNRUN**: Xcode, Apple SDKs and simulators are unavailable. No Xcode compilation/device checks or GitHub Xcode CI was added.

New methods cover adaptive dashboard metric/title layout at compact width, normal/largest text and light/dark; Home watched-date presentation for independent repeats (fixture watch dates in 2020 versus record dates in 2025); and largest-text dark Home/Profile/Settings/backup action reachability. Existing empty Home tests now check removal of repetitive empty sections. Existing deterministic profile counts, episode-mutation updates, navigation, settings/credential/attribution, backup, ratings, reviews and Library filter regressions remain.

## Screenshot and manual validation matrix

No runtime before/after screenshots are available from Linux. These tests capture attachments when run locally; their existence does not imply they have executed:

| Requested state | Existing / updated local screenshot source |
| --- | --- |
| Home empty / populated | DashboardUITests, including new largest-text dark and dated-repeat views |
| Search results | SearchTests |
| Movie / TV detail | MediaDetailUITests, including missing artwork and large-text dark |
| Library populated / empty | LibraryOrganizationUITests for populated; manually capture AppShellUITests’ empty Library fixture |
| Season details | Manually capture TVProgressUITests' deterministic season fixture |
| Rating selection | RatingUITests |
| Review editing | Manually capture DiaryUITests' deterministic review editor |
| Profile | DashboardUITests, including new largest-text dark state |
| Settings | BetaPreparationUITests before credential entry; DashboardUITests dark state |

Run the full shared MovieTracker unit/UI targets locally; begin with DashboardUITests, DesignSystemTests, AppShellUITests and BetaPreparationUITests. Review compact and large iPhones, light/dark/increased contrast, normal/largest text, VoiceOver/Switch Control, Reduce Motion and keyboard-safe editing. Repeat Search → Details → Back, Home next episode → Season → Back, Library filter changes, review Save/Cancel, rating edit/clear and Settings → Export & Restore → Back. Confirm watched flags/counts and saved data survive relaunch using the existing isolated persistent fixtures. Capture remaining screenshots in both appearances before visual sign-off.

## Deferred work and later branding / V1.0 recommendations

Runtime layout, motion, actual accessibility traversal, native file-provider sheets and persistence-failure presentation remain unverified. This pass does not establish V0.5 release readiness. Keep current release blockers documented in the release checklist.

For a later approved branding pass, settle the final app name and typography/artwork identity while retaining semantic contrast and required TMDB attribution. Before V1.0, validate localization expansion, long real-world titles/reviews, VoiceOver/Switch Control and native document workflows on devices, and collect actual large-library profiling evidence before changing layouts or adding navigation complexity. These are recommendations, not features implemented here.
