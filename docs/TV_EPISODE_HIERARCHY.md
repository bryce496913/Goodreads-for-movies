# TV season and episode hierarchy (025)

## Components and interaction

Series detail retains its existing route, metadata and tracking service. The tracking section now has one concise shared ProgressDescription followed by native TVSeasonGroup disclosures. Headers use **Season N** or **Specials**, subtle dividers, normal spacing and no decorative cards. All groups begin collapsed; users may expand multiple seasons. Stable stored season UUIDs retain expansion and the season's model across ordinary saved-state/catalog updates.

Expanded groups conditionally create the existing TVSeasonEpisodesView in embedded mode. It uses LazyVStack rather than a nested List or NavigationStack. Collapsed groups do not render episode rows or start season requests. The group attempts loading on its first expansion; repeated expansion reuses its retained model and existing store. Failed loads require explicit Retry, and canceled attempts may be attempted again. Explicit Refresh and the model's existing freshness/backoff/authorization policy remain authoritative. Metadata expiry still reaches retained group models. Catalog refresh does not intentionally reset expansion.

TVSeasonEpisodesView supplies the same controls/content in embedded and standalone modes. **Open Season N** / **Open Specials** retains the typed standalone destination; Home's existing next-episode route still opens it directly. The existing confirmations and centralized LibraryStore mutations are shared rather than duplicated.

TVEpisodeRow presents a native watched toggle beside episode number/title and air date. Unknown episode numbers use a neutral Saved episode label; the opaque provider reference remains in the accessible label and stable test identity. Episode provider IDs remain ForEach identity. There is no parent button around the toggle. Future unwatched episodes remain disabled, and existing manually watched flags can still be cleared. Runtime/synopsis are available in a native secondary disclosure, with no empty synopsis container when neither is available.

Bulk **Mark Aired Episodes Watched** and **Mark Season Unwatched** live in the season's **Season actions** menu, followed by the original confirmation. Explicit retry/refresh and post-success saved feedback remain. Metadata provenance, actual future/unknown exclusion counts, retained/unlisted season status and custom season names are in **Metadata details** rather than repeated before episode rows. Failure feedback remains visible after a failed request; no error is silently treated as a loaded empty season.

## Progress and unavailable metadata

ProgressDescription is shared by series, season and saved-series progress:

- Valid coverage and positive eligible denominator: “3 of 7 known aired episodes · 43% of known,” with a native bar and explicit percentage accessible value.
- Incomplete coverage or no eligible denominator: actual watched count only, no invented percentage or division by zero.
- Up-to-date: text plus a check symbol. The series-level note identifies known aired regular episodes and explicitly excludes a permanent series-completion claim.
- Unloaded/unknown season with no saved episodes: one concise **Episode details unavailable** header state.
- A successfully loaded listing with an explicitly known zero expected count and no saved episodes: **No episodes listed**. An unknown total never becomes a verified zero.

Specials use the same disclosure layout but remain separate in the existing regular-season calculations. No counting, coverage, future/unknown-air-date, permanent completion, batch mutation or offline semantics changed.

## Data and performance boundaries

No domain entity, SwiftData schema, LibraryStore implementation, metadata service, progress model or calculation changed. Every individual/bulk write still uses its original store call, explicit save/rollback and error path. Saved episode metadata and progress are not deleted or recreated by collapse. The same cached episode/summary queries and numeric season ordering remain. Only the explicitly selected season loads; existing cache guards apply. A user can still deliberately expand many seasons, so total rendered content can grow with that selection.

DEBUG-only SearchUITestService adds explicit many-seasons, season-unavailable and season-once fixtures. These are activated only by the existing UI-test launch configuration and never seed production data. Default test data behavior remains unchanged.

## Checks and tests

Passed on Linux: project OpenStep parse, referenced files and source membership for all three targets; Swift grammar parsing for 135 files; asset JSON; all 44 intended text contrast pairs across nine adaptive assets; whitespace and protected business/persistence/model file checks. Grammar parsing is **not compilation or Swift type checking**.

All **373 XCTest methods are UNRUN**. Xcode, Apple SDKs and simulators are unavailable. No Xcode build/device checks or GitHub Xcode CI added.

Six new regression methods cover:

1. Native inline expansion, mutation, collapse/reopen, stable episode identity and no second network request (the fixture would fail it).
2. Separate expandable Specials and its watched control.
3. A reverse-ordered 25-season catalog with collapsed episode content and season 24 access.
4. Unavailable season metadata, no fake episode rows and an explicit enabled retry.
5. Missing versus verified empty state, Specials label, reliable/unknown/zero-denominator progress copy.
6. Numeric catalog ordering and stable stored UUIDs after repeat catalog updates, without progress writes.

Existing tests now navigate through disclosures to standalone seasons, access bulk actions through the menu and assert the concise progress label. Existing future/unknown handling, batch confirmation, offline persistent relaunch, movie exclusion, long titles, accessibility layouts, progress updates and data-integrity tests remain. Numeric season ordering remains a store responsibility, tested rather than reimplemented in the UI.

## Screenshots and local validation

No runtime before/after screenshots are available in this Linux environment. The inline-expansion regression attaches a representative expanded-season screenshot when run locally; all fixtures are deterministic and require no network. Capture collapsed/expanded regular seasons, Specials, unavailable metadata, bulk confirmation and a long season list in both appearances before visual sign-off.

Run TVProgressUITests, TVProgressTests, DesignSystemTests, MediaDetailUITests and DashboardUITests locally, then the full existing regression targets. Inspect compact/large iPhones, light/dark/high contrast, largest Dynamic Type, VoiceOver/Switch Control and Reduce Motion. Confirm expansion announcements, independent toggle/menu gestures, preserved expansion after mutations/refresh, no duplicate downloads on reopening, long-title wrapping and final-row reachability. Check Home → Season, series → expanded episodes → standalone season → Back, offline edits and persistent relaunch.

Rendering, disclosure accessibility element mapping, scroll reachability, cancellation during very rapid expansion, actual request counts and runtime state/persistence behavior remain unverified until local tests run. If a first expansion is canceled before completion, another attempt can be necessary; ordinary completed expansion/collapse does not deliberately refresh. No simulator or persistence result is claimed from static checks.
