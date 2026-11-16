# Pass 034 — V0.6 UI integration and accessibility

## Audit and changes

| Surface | Finding | Refinement |
| --- | --- | --- |
| Home Continue Watching | Progress was inside the series link; navigation and mutation needed clearer hierarchy. Each row repeated long coverage wording. | Series title is a separate 44-point minimum navigation target; progress remains independently readable with series-specific spoken counts. Continue uses the shared secondary action style; Mark Watched remains primary. A single section footer explains known-aired progress. Saving/disabled/error states remain explicit. |
| Library / four-tab shell | Existing native stacks and local state already serve V0.6. | Preserved Home, Search, Library, Profile, existing Library entry points, navigation destinations, filter models and tab-owned paths. No custom navigation or added tab. |
| Collections | Swipe removal used generic Delete; reordering depended on drag handles. | Explicit **Remove from Collection** with confirmation and **Keep in Collection**. Whole-list deletion separately says **Delete Collection** / **Keep Collection**. Both explain preservation of title data. Native drag handles remain; title menus and custom accessibility actions provide Move Up / Move Down with boundary disabling. Reorder mode suppresses title navigation to prevent accidental opening. |
| Collection editor / membership | Single-line names and no dedicated keyboard dismissal; confirmed changes had little feedback. | Vertically growing name field, native keyboard Done, visible toolbar Save/Cancel, existing unsaved-change protection plus Keep Editing. Native toggles retain persisted-state bindings and clarify immediate saves. Successful create/rename/membership/reorder/removal operations announce only after the existing store call succeeds. Membership and order feedback is also visible. |
| Collection rows | Horizontal posters compete with large text and trailing controls. | Existing cache-only fixed poster frame and native type/metadata hierarchy; stack artwork above text at accessibility sizes. Title-action menus have 44-point minimum targets and title-specific labels. |
| What Should I Watch? | Primary action/count followed a long filter form; result poster/title were separate List rows. | Source followed by candidate count and Pick for Me, then filters. Result groups artwork/title/metadata with an accessibility-size vertical layout. Shared primary/secondary/tertiary controls, semantic error/loading views, readable missing-metadata copy, keyboard Done identifier, and Start Over. Counts include zero when the source is nonempty. Random picks announce the selected title/type. Source/filter/pick retention and eligibility logic are unchanged. |
| Media Detail | Existing shared status/favorite/list actions, scroll padding and typed destinations already support the flow. | Audited and retained; no V0.5 redesign or competing detail route. |
| Settings artwork | Clear already uses the shared managed clear path, but cancellation and completion could be clearer. | Explicit Keep Artwork, personal-data preservation hint, visible checkmark/text and a completion announcement after the shared clear call. |

All changes use Paper/Ink/Ember semantic colors, existing typography/spacing, `AppActionStyle`, `EmptyStateCard`, `AppLoadingState`, `AppErrorMessage`, `LibraryCachedPoster`, `appListScreen`, `appFormScreen`, and `appEditorSheet`. No new design tokens or parallel control/navigation/cache abstraction. Artwork remains memory-only under the **BLOCKED** Pass 030 licensing gate. Existing fixed poster frames prevent artwork-driven geometry changes; cache policy/loader code is untouched.

## Interaction and accessibility boundaries

- Collection removal deletes membership only via `LibraryStore.removeCollectionMembers`; collection deletion retains its existing `deleteCollection` behavior. No Library removal action was added to these screens.
- Reorder alternatives call the same `reorderCollection` transaction with original membership IDs, preserving stale-order checks and manual identity/order. Native handles and accessible alternatives are equivalent operations, not independent ordering logic.
- Every persistence announcement/visible success follows a successful synchronous store call. Failed operations retain the existing alert/retry path, and previous operation feedback is cleared before new attempts. Native cancellation never reports success.
- Home still uses `HomeEpisodeAction` → `markNextEpisodeWatched`; only the presentation handler announces a confirmed watched flag. Navigation does not call the mutation path. No spinner delay or new asynchronous write is introduced.
- UIKit accessibility announcements provide feedback without animation, forced focus, haptics or a spinning selection game. Existing native controls handle selected/disabled traits. Progress exposes both counts and percent; controls include exact series/episode or title context.
- Shared native List/Form scroll margins and safe areas remain authoritative; no device offsets or custom bottom dock. Editor toolbar actions remain outside scrollable name content. Discovery's main action precedes optional filters; final controls remain in the scrollable List. At accessibility sizes, collection/result poster layouts stack vertically.
- The existing membership picker can open its existing collection editor. That necessary editor sheet remains; no additional modal layer was introduced.

## Regression tests and evidence

Added **six UI XCTest methods** in existing suites:

1. Home series/season navigation preserves watched counts and tab path.
2. Named collection moves, saved order across navigation, disabled boundary, edit-mode navigation suppression, and membership/list deletion cancellation.
3. Long collection names at largest accessibility text in dark mode, keyboard dismissal, Save/Cancel, Keep Editing and empty state.
4. Discovery largest-text/dark result actions, hit target, final filter controls above the tab bar and state across tab switching.
5. Discovery light-mode year keyboard, Pick Again, TV identity and Details/back navigation.
6. Settings artwork cancel/confirm at largest text in dark mode and final backup row reachability.

Updated existing regressions for explicit membership removal confirmation, multiline editor lookup, standalone Home progress labels, discovery keyboard identifier, and artwork completion element lookup. Existing create/rename/delete, Add to List, random/filter/empty-state, direct mark and independent-data tests remain in place. Repository inventory is now **374 unit + 80 UI XCTest methods**.

Executed in Linux:

- OpenStep project parse, reference resolution, complete membership in all three targets: **PASS**.
- Swift grammar parsing across **148** source/test files: **PASS**, **not compilation or type checking**.
- Asset JSON and design-token validation: **PASS**. All 44 intended text pairs meet 4.5:1; variant minima: light 4.65, dark 4.64, increased-contrast light 5.88, increased-contrast dark 4.95.
- Protected data/network/discovery model/projection/cache/shell/build settings inspected as unchanged; no new source files or target settings needed.
- Whitespace checks: **PASS**.

**All native unit/UI XCTest methods are UNRUN.** Xcode, Swift compiler, iOS SDK and simulators are unavailable. No simulator/device screenshot or before/after image is available; new UI tests attach screenshots only when actually executed. No runtime claim is made for layout, VoiceOver, announcements, navigation, safe areas, persistence or test passing.

## Local verification and deferred issues

Run the shared MovieTracker scheme with an installed compact iPhone and larger iPhone on iOS 17+, using README's `xcodebuild test` command. At minimum include CollectionsUITests, WatchDiscoveryUITests, DashboardUITests, BetaPreparationTests, AppShellTests, MediaDetailTests and the existing collection/library/episode integrity unit suites. No GitHub Xcode CI is added.

Manually check light/dark and increased contrast, default/large/largest accessibility text, VoiceOver and Switch Control, Reduce Motion, keyboard display/dismissal, list scrolling and final controls above the tab bar. Confirm:

- Multiple Continue Watching rows name the correct series; tapping Details/Continue never marks an episode. Direct mark updates only its intended flag; failed saves announce no success.
- Collection creation/rename cancellation preserves drafts or discards only after confirmation; long names remain editable with keyboard visible.
- Move Up/Down and native handles produce the same dense order, boundaries are clear, VoiceOver custom actions are exposed, and order survives reopening. Remove from Collection, Delete Collection and their cancel actions have distinct effects.
- Add to List feedback reflects actual persisted membership. Failure alerts do not leave a false success state.
- Discovery source/media/OR-genres/year/runtime remain unchanged through Details/back and tab switching; zero/unknown/expired states remain understandable. Repeated uniform picks may choose the same title.
- Artwork clear cancels safely or clears through the existing shared loader, without losing personal data. Missing artwork does not resize poster frames.

Native announcement delivery/order can be affected by sheet dismissal and system focus; this needs actual VoiceOver validation. Multiline name field accessibility representation, native EditButton environment behavior and custom accessibility actions also require Apple runtime validation. Numeric year-entry parsing retains the existing native formatter and needs device testing. Compact safe-area and localization coverage, maximum-size toolbar layout and screenshots remain deferred until local execution. No data model, persistence service, migration, metadata/provider behavior, discovery algorithm, artwork licensing, or V0.5 feature behavior was rewritten. Pass 035 has not been started.
