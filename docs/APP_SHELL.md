# Navigation and app shell — pass 020

## Source audit before implementation

- The native four-tab structure is sound and should stay. Search explicitly owns its NavigationPath, while Home/Library/Profile rely on implicit stack state. Make ownership equally explicit without a router or custom navigation UI; ordinary tab switches should preserve each stack.
- Home's navigation title says “Welcome” while the tab says Home. Profile repeats its native Profile title with a second large “Your local profile” heading. Secondary Lists/Forms often inherit large titles, unlike inline Details/Season pages.
- The four root Lists use the design canvas, but Settings, review/diary/progress Lists and editor Forms retain different background/title/spacing defaults. Native safe-area and back gestures already work structurally; no manual insets/ignoresSafeArea workaround is warranted.
- Search/Home/Library put fully padded rounded empty-state cards inside native grouped rows. Reviews, history, Profile diary and TV progress use unrelated empty layouts. Reuse an inline shared message inside List rows to avoid nested containers while keeping actions outside it.
- Library's More menu pushes through an optional item outside the root path. Use value-based native destinations so explicit shortcuts and path ownership remain coherent. Intentional “Find…” / “Open Library” shortcuts should open their tab root; tapping a tab ordinarily must not clear its path or query/filter state.
- Review and viewing editors already protect unsaved drafts and use one modal NavigationStack each. Preserve those checks. Review TextEditor lacks the existing Settings-style keyboard Done control; add focus dismissal and interactive scroll dismissal without changing validation or saves.
- Backup preview's Cancel action is below potentially many conflicts. Move that same action to its native cancellation toolbar so it remains available while scrolling; keep confirmation, busy disabling, revision checks and restore operations unchanged.

These are source findings, not observed device failures. Native tab/chrome layout, animations, keyboard, accessibility and screenshots cannot be certified on this Linux worker. No media/persistence/provider/search/user-operation logic will change.

## Navigation decisions

Home, Search, Library and Profile remain exactly four native TabView items, with standard outline SF Symbols (`house`, `magnifyingglass`, `books.vertical`, `person.crop.circle`). Selected-state tint uses pass 019's Ember asset. Native tab background uses its adaptive surface; hit testing, labels, safe-area insets, gestures and platform transitions stay with Apple. No floating dock, custom bar, custom gesture, animation controller, appearance proxy or fifth tab was introduced.

AppRootView owns four independent in-memory NavigationPaths. Search's existing model/cache and Library's organization model remain retained at the root. Value-based routes are reflected in those paths; existing view-based NavigationLinks remain SwiftUI-managed. Ordinary tab taps change only the selected tab. Library's More menu now appends its existing subpage enum to the Library path and resolves it with native `navigationDestination(for:)`, keeping back navigation and explicit root shortcuts coherent. No custom navigation framework or domain-model route replacement was added.

“Open Library” intentionally clears that tab's path and resets its existing filters; “Find…” intentionally clears Search's path. Neither action deletes records or changes Search's retained query. Ordinary tab switching does not perform either reset. Path state is in-process only: this pass does not add restoration of navigation after termination.

Home's title is intentionally **Home** rather than Welcome, matching the tab. Existing launch/title assertions were updated to that identity; other navigation titles/action identifiers remain. Stable `screen.*` identifiers supplement existing identifiers for regression checks. Each root uses a native large title; pushed pages and modal editors use inline native titles. Profile's second large heading is removed, retaining its privacy/local-device description. Remaining reusable PageHeader text (About) is compact title2, not a second large navigation title. Selected movie/TV titles remain meaningful content headings in Details.

## Layout and changed-screen summary

`AppShell.swift` contains presentation-only helpers, not state/routing machinery:

- `appPageTitle`: native root-large versus pushed/editor-inline titles with the adaptive navigation background.
- `appListScreen`: native inset-grouped List, pass 019 canvas, 16-point horizontal scroll-content margins, 24-point section spacing and interactive keyboard dismissal.
- `appFormScreen`: corresponding native Form canvas/margins/section spacing/keyboard dismissal and inline title.
- `appTabChrome`: adaptive native tab-bar background, keeping the bar visible and system-sized.
- `appEditorSheet`: native large sheet and visible drag indicator. Existing dirty/busy interactive-dismissal protections remain at their current owners.

Margins describe the surrounding scroll content; native grouped-row text insets/separators remain platform-driven. Detail ScrollView keeps its single 16-point content padding. No extra top spacer, negative inset, geometry/device offset, safe-area override, overlay toolbar or fixed-height text container was added.

| Screen | Change |
| --- | --- |
| Four tab roots | Explicit path ownership, consistent native titles/canvas/margins/section spacing; existing tab labels and functionality retained. Home title now matches its tab. |
| Home / Search / Library | Shared empty messages now render inline within native grouped rows, without a second padded rounded card. Existing Search/Library filters, empty-state actions and error/loading distinctions remain. Home's history/Library shortcuts remain reachable even for an empty account-free library. |
| Profile | One native page title and supporting privacy description; accurate zero metrics remain. Empty recent diary uses the same inline message. No synthetic activity or rating is added. |
| Reviews / Viewing history | Common inline empty appearance with existing instructions to write/log from Details, shared List background/title/spacing and stable identifiers. Review text, event chronology and edit/delete behavior are unchanged. |
| Saved TV / Season / detail-season empty views | Same presentation vocabulary; empty descriptions explain where to load season information and that saved watched flags are retained. Progress arithmetic, toggles, batch actions and requests are unchanged. |
| Details | Keeps one inline navigation title, existing selected-title content/artwork and existing actions; metadata-error presentation uses the shared inline message. |
| Settings / About | Common pushed title/margins/background. Settings retains the secure-field Done control, now identified for tests. About retains the supplied unmodified TMDB logo/notices on their existing white logo backing. |
| Review / viewing editors | Native Form layout and inline modal titles, consistent large sheet presentation. Review adds a keyboard Done action and dismisses focus before the existing cancel/discard decision. Viewing cancel gains a stable identifier. |
| Backup / restore preview | Common Form/List layout. The **same** Cancel action moves from below long conflict lists into the native cancellation toolbar, with its existing busy-disabled state. Confirmation, model callbacks, picker lifecycle, revision checks and data operations are unchanged. |

The shared EmptyStateCard supports `card` (existing standalone use) and `inline` (inside Lists). Inline removes its extra padding/fill/border but retains heading/message semantics, wrapping and accent icon. Screen composition does not gain nested stacks of cards. No empty state generates sample recommendations, reviews, counts or pretend progress; tests use only the existing DEBUG fixture launch mode.

## Keyboard, controls and unsaved edits

Review and viewing editors still own one NavigationStack inside their native sheet, not a second stack pushed into the tab's stack. Existing Save/Cancel toolbar placement, text/date validation, confirmation dialogs, error alerts and `interactiveDismissDisabled(hasChanges)` remain. Review's Done action changes focus only; canceling a discard dialog keeps the text/date draft. No swipe-to-save, implicit autosave, silent draft discard or data-mutation shortcut was added.

Form/List scrolling can dismiss the keyboard interactively. Toolbar Save/Cancel stay native rather than being oversized styled buttons inside a constrained navigation bar. Destructive buttons/dialog actions retain their destructive roles; ordinary discovery/retry styling from pass 019 remains. Segmented/menu filters, Toggles, native Back and search fields keep platform interaction and accessibility behavior. Large-text menu filter fallbacks remain in place. Native file exporters/importers remain native; no additional modal picker or navigation container was placed around them.

## Accessibility and inspection limits

Source review confirms native labels/touch handling, dynamic system fonts, leading alignment/wrapping, descriptive empty states, retained accessible names/identifiers and no custom animation or safe-area workaround. The Python palette check still passes all 44 intended text pairs across light/dark/increased contrast. Standard native controls, separators and selected states remain platform-driven. This is not a claim that the entire rendered interface, focus order or tab labels have been validated.

Runtime review is still required for VoiceOver, highest Dynamic Type, Reduce Motion, high contrast, light/dark, long translated strings/RTL, keyboard coverage, modal/tab safe areas and compact screens. Current copy is English; no translations or localization infrastructure were invented in this pass. No measured animation smoothness, keyboard timing or device appearance claim is made.

## Regression tests and actual evidence

Added **10 AppShellUITests**, using the existing DEBUG mock metadata service and isolated in-memory user store:

1. Four native tab labels, selected state, root identifiers, tab targets and one navigation bar.
2. Independent Search detail and Profile Settings stacks across tab switches, native Back and retained Search query/results.
3. Library history/review/TV subpages across tab switches and Back, with retained local query/favorite filter.
4. Explicit Home → Open Library root/filters reset, distinct from ordinary tab selection.
5. Home/Search/Library/Profile empty descriptions and discovery actions.
6. Review keyboard Done, reachable toolbar controls, disabled blank Save, cancel-discard-dialog preservation and final explicit discard without saving a review.
7. Pristine and dirty viewing-sheet Cancel/Discard without creating a diary event.
8. Settings → Backup/About → Back hierarchy and core action reachability, without invoking nondeterministic native file providers.
9. Largest accessibility text menu filters, Toggle, Settings secure field and keyboard Done; no credential is saved.
10. Requested dark-appearance root identity/selection and screenshot capture.

One additional unit contract in DesignSystemTests checks four unique tab labels and valid SF Symbol names. Existing UI launch helpers now expect Home. Existing functional UI tests remain intact; no assertions were removed to disguise runtime failures. New tests take screenshots when run locally. Software-keyboard tests require the simulator's software keyboard enabled; native control visual frames are not used as a proxy for every expanded system hit region.

**All XCTest remains UNRUN** on this Linux worker without Swift/Apple frameworks. Current inventory: **356 methods — 306 unit-target (including existing benchmarks), 50 UI**. Passed here: project/reference/target membership checks, Swift grammar parsing for 135 files (not type checking/macros), resource JSON/privacy metadata, documentation links/whitespace, AppIcon/AccentColor configuration checks and the unchanged palette contrast check. No Xcode/device build, simulator, signing, TestFlight or GitHub Xcode CI ran/was added.

**Screenshots are unavailable here.** No mock screen render is presented as native evidence. Run AppShellUITests plus NavigationTests and existing Search, Library, detail, diary, rating, TV, backup-model and accessibility regressions locally. Export the Home/root, empty Profile, largest-text Settings and requested-dark screenshots produced by the suite, and verify actual appearance rather than treating launch arguments as proof of theme selection.

## Deferred review

Verify navigation/back gestures and state retention on an actual supported iPhone; inspect light/dark/increased contrast and large text with hardware/software keyboard settings, and confirm the native toolbar/tab chrome on supported OS versions. Check long translations/RTL once real localized resources exist. Broader Home editorial layout, Library filter density, detail action hierarchy and large-import performance remain separate follow-ups. Media models, persistence/services, search/projection algorithms, ratings/review/diary/episode calculations and backup/restore operations are unchanged by this pass.
