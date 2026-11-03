# Home dashboard refinement (024)

## Presentation

The Home tab keeps its identity and native stack. Its navigation title now reads **Your screen**, with the compact subtitle **Pick up where you left off.** This is provisional display copy, not an app rename. UI tests retain Home tab selection and expect the new root navigation title.

Continue Watching uses a compact cache-only poster beside a wrapping title and progress. The title/progress area opens the series; a separate Continue action opens the existing season destination only when the aggregator supplies a known next episode. There are no nested navigation links. The action's spoken description includes the series, season, episode and episode title. At accessibility text sizes artwork and text stack vertically.

Reliable progress shows watched/eligible known aired regular episodes and a small native bar with its percentage accessible value. Incomplete progress shows only the existing total-watched count; no invented total, percentage or next episode appears. Last marked episode information appears when its episode number is known. Technical metadata diagnostics remain in detail screens; Home omits the old incomplete-percentage and unknown-next warnings. No series-completion, episode counting or next-episode algorithm changed.

Recent Activity becomes a compact title plus action/date row. Rating updates read “Rated 2.5 stars,” for example, from the existing label; cleared ratings remain explicit. Full original activity wording and the recorded timestamp remain in the accessibility label. Optional watched dates stay separately labeled. Only viewing events already in the Recently Watched preview are omitted from Activity; independent repeats and undated events are retained. This is a small read-only projection of previews bounded to eight activity and five diary records, not a full-store scan or changed analytics service.

Recently Watched uses “Your recent watches will appear here” when no dated previews exist. Viewing History remains available even when there are undated records. Populated previews keep their actual watch dates. Empty Watchlist shows “Start your watchlist,” supporting copy and a Search shortcut. Existing artwork previews and Open Library remain.

Section order is welcoming subtitle, Continue Watching, Recent Personal Activity, Recently Watched, Watchlist. A completely empty Home retains the focused empty state and Search action. Existing local aggregation, native navigation, adaptive color/type tokens and memory-only artwork policy are unchanged. No new TMDB request, persistence operation, animation or haptic was added.

## Bottom tab bar investigation

Source inspection found a native List within NavigationStack/TabView, with no Home/root ignoresSafeArea, overlay tab bar or fixed screen-height container. No supplied screenshot file or running simulator was available to establish the reported overlap's actual runtime cause. This pass does **not** claim that cause has been reproduced or a device-level fix verified.

Home now explicitly applies the existing 16-point content-margin token to the native List's bottom scroll content. It preserves automatic tab-bar safe-area insets and provides normal end-of-list spacing. No tab-bar height estimate, device-specific offset, custom bar or safe-area override was introduced. Regression assertions require the final action's full frame to sit above the native tab bar after scrolling, including populated largest-text dark, empty and empty-Watchlist states. They must run locally before overlap is considered resolved.

## Regression coverage and results

New tests:

- Home copy retains half-star values, explicit cleared ratings and correct singular/plural watched counts.
- Activity projection omits only duplicate viewing-event previews, preserving undated events, ratings, source snapshot and ordering.
- Mocked incomplete episode coverage shows a watched count, no percentage, no invented next episode and a working series link.
- Mocked undated history/empty Watchlist retains both events and the History/Search/Library routes, with final-action tab-bar clearance.

Existing dashboard tests now assert compact rating activity and removal of duplicate viewing activity, new navigation title expectations and safe-area clearance in empty/populated accessibility states. Existing dated-repeat, profile statistics, episode mutation, navigation, ratings, review and Library regressions remain. The test fixture adds incomplete/empty-Watchlist/undated variants only inside the UI test target.

Linux checks passed: OpenStep project parsing, references and complete membership in all three targets; Swift grammar parsing for 135 files; asset JSON; nine adaptive color assets and all 44 intended text contrast pairs >= 4.5:1; relative documentation links; whitespace checks; unchanged persistence/domain/network/statistics/model/projection files. Grammar parsing does not compile or type-check Swift.

All **367 XCTest methods are UNRUN**. Xcode, Apple SDKs and simulators are unavailable. No build/device checks or GitHub Xcode CI was added. No runtime before/after screenshots are available; updated DashboardUITests attach empty, populated, incomplete, empty-Watchlist, dated-repeat and largest-text dark states when run locally.

## Local review and remaining layout concerns

Run DashboardUITests, DesignSystemTests, AppShellUITests and NavigationTests locally, followed by the existing full regression targets. Inspect compact and larger iPhones, light/dark/high contrast, largest Dynamic Type, VoiceOver and Reduce Motion. Confirm:

1. Home tab retains its selected state and opens Your screen; all pushed pages return correctly.
2. Continue Watching opens series/known next episode; incomplete coverage never displays a percentage or fabricated next episode.
3. Activity rows use recorded timestamps; dated watches use watched dates; repeat watches remain independent.
4. Undated-only history remains accessible despite a concise empty dated-preview state.
5. Search and Library shortcuts work, and the last row scrolls entirely above the tab bar in every state.
6. Long titles, action labels, posters and progress remain readable without clipping or oversized cards.

Capture before/after screenshots in both appearances. Rendering, actual tab-bar overlap, VoiceOver traversal and touch-target reachability remain unverified until these runs pass. If overlap persists, capture device/OS, appearance, text size and view-debugger safe-area frames before changing native insets further. No speculative device-specific workaround is included.
