# Pass 031 — Continue Watching and direct episode actions

## Pre-change audit and ambiguity decisions

The dashboard aggregates Sendable snapshots locally; Home does not request TV metadata. EpisodeID combines the exact provider-qualified TV MediaID and provider episode ID. Existing watched flags, UTC-day aired eligibility, specials exclusion and unknown coverage remain authoritative. Season/series percentages count known aired episodes, not permanent series completion. Metadata retention is still 150 days; pass 030's artwork gate remains BLOCKED and posters remain memory-only.

The existing next preview sorts retrieved regular episodes but relies on a broad coverage flag; it does not independently validate positive/unambiguous episode positions or contiguous season coverage. A locally known candidate is not proof of a globally next episode. Pass 031 will represent that distinction explicitly and withhold the Home action without sufficient reliable coverage.

“Last watched” is actually the latest **mark-watched action timestamp**, not a diary watch date or maximum episode number. It will be labeled Last marked watched. Out-of-order viewing remains valid.

The existing LibraryStore.setEpisodeWatched deliberately promotes an absent/Watchlist status to Watching. Home's new action must preserve status independence. It will use an explicit opt-out on the same writer; the existing episode/season screen behavior remains the default. No rating/favorite/review/diary operation is implied. Existing all-known-aired rows disappear; an explicitly Watching series may retain an up-to-date card without a fabricated next episode. Watching status may justify a zero-progress card; unrelated zero-progress series will not be seeded into Home.

## Implemented selection and card behavior

NextEpisodeSelector returns one of **reliable**, **knownUnwatched**, or **unavailable**. Only reliable supplies Home's existing optional next field. Partial candidates are represented explicitly in the algorithm but are not displayed as “next” or offered as Home actions.

The selector validates a TV identity and finite clock, ignores specials, validates exact series/provider episode identity, positive season/episode positions and nonempty existing titles, and requires valid original episode receipts for TMDB data. Eligible candidates must be unwatched, have a finite known air date on/before the UTC day and sort by regular season number, episode number, then provider episode identity. It never synthesizes an episode/title/date.

Global reliability additionally requires the existing full listing/coverage proof, contiguous known regular seasons, unambiguous contiguous episode positions within retrieved season groups, matching season membership and unique provider IDs. Unknown remaining air dates, gaps, duplicate positions, expired/unknown TMDB catalog, season or episode receipts, conflicting expected season counts or partial coverage withhold a global-next claim. A gap may be a provider convention; this pass conservatively withholds the Home action rather than inventing an intervening episode. Series dashboard coverage also withholds percentages for gaps/expired season receipts. Existing known-aired percentage arithmetic is unchanged; complete known-aired coverage never implies permanent completion.

Continue Watching keeps its compact cache-only poster, native series and season navigation, concise known-aired progress or watched-count fallback and last-marked episode. The next episode title and **Mark S… E… watched** action are separate from navigation, with no nested action inside a link. The two native links use plain button styling to avoid automatic List-row action coupling; the save button keeps its own explicit style/target. An explicitly Watching title may show zero progress or stay up to date with all known aired episodes; unrelated zero-progress titles are not added. Profile's series-with-progress count still uses actual watched flags, not Watching status. Existing five-card ordering/cap remains.

## Mutation and concurrency boundary

LibraryStore.markNextEpisodeWatched receives an exact EpisodeID. It:

1. Rejects non-TV identities and treats an already watched exact episode as an idempotent no-op.
2. Reads the target series' cached season/episode data and current watched set, checking current receipt/coverage/ordering eligibility with the same selector.
3. Rejects a stale requested ID if a different episode is now next or eligibility is unavailable.
4. Calls the original transactional setEpisodeWatched with updateViewingStatus false, using current local episode/show metadata.

The new defaulted writer parameter preserves the original Watching promotion for existing episode/season callers. Home's path does not call prepareWatching, so it does not create an implicit Library entry or change existing status/updatedAt, rating, favorite, private review or viewing diary. Exact provider identities, cached per-series queries and original save/rollback/publication remain authoritative. No schema/migration or competing writer is added.

HomeEpisodeAction exposes saving/error state, guards reentry, and reports failures with an explicit Retry Save action. No success message precedes persistence: confirmed stored flags disable the old action and the existing root revision-triggered cancellable dashboard task recomputes local snapshots. No asynchronous network work is involved in a save. The non-suspending main-actor transaction serializes watched/unwatched writes; duplicate queued taps for the same ID make no second write. No delay/task hop is added to force a spinner for a fast save, and quick tab switches cannot cancel a partially completed transaction. The local aggregate's existing cancellation/generation protections remain.

A stale card can briefly remain while aggregation finishes; button state reads current stored flags and the mutation revalidates all eligibility, so it cannot write the stale recommendation. Metadata refresh still only updates metadata on progress rows, never watched flags/timestamps. Failed saves roll back and retain previous visible personal state; retry rechecks current data rather than blindly replaying a snapshot.

## Offline and data safety

The action needs saved, trustworthy eligibility metadata but no metadata service, token, image download or internet connection. Missing/expired metadata preserves flags and navigation while withholding the action. Explicit season toggles remain separately available under existing rules. No automatic fetch of every series was added. Force-quit persistence is covered by a temporary disk-store reopen test, not by a claimed device run. Artwork remains session-memory-only under the blocked pass 030 rights gate; offline relaunch may show a compliant placeholder.

## Tests and actual results

Eleven new methods cover:

- Regular-season/episode ordering, out-of-order watched flags, specials and future exclusion.
- Known candidates versus reliable next, unknown air dates, missing seasons and ambiguous/gapped positions.
- Missing/expired TMDB receipts and invalid episode metadata.
- Zero/up-to-date Watching cards with unchanged statistics definitions.
- Direct action idempotence and preserved status/favorite/rating/review/diary/update timestamps.
- Save-failure rollback, explicit retry and one write for a repeated tap.
- Independent provider-qualified series and rejection of a same-valued movie identity/stale next.
- Offline temporary disk-store reopening with retained progress and no diary creation.
- Revalidation after unwatch/metadata refresh with preserved flags.
- UI action with a failing metadata service, local profile data preservation and detail navigation.
- UI incomplete coverage with no invented next/action.

Executed on Linux: project OpenStep/reference/membership checks for all three targets; Swift grammar parsing for 135 source/test files; asset JSON and all 44 semantic contrast pairs; whitespace, documentation links and unchanged schema/network/artwork/retention checks. Grammar parsing is not compilation or type checking.

All **395 XCTest methods are UNRUN**: no Swift compiler, Xcode, Apple SDKs or simulator is available. No Xcode build/device checks or GitHub Xcode CI was added. No offline device/force-quit or disk-test success is claimed. The new UI test attaches an up-to-date/offline-fixture Home screenshot when run locally; no runtime screenshots are available here.

Run DashboardTests, TVProgressTests, DashboardUITests and the existing offline, integrity, persistence, detail and TV UI suites locally, then the full shared scheme. Inspect compact/large iPhones, light/dark/high contrast, largest text, VoiceOver, direct-action/navigation gesture separation, tab switching, last-row reachability, save faults/retry, expired metadata, out-of-order watches and multiple series. Confirm profile counts and exact flags after relaunch/reconnection. Selection is intentionally conservative for unusual provider numbering; cached metadata quality limits action availability. Save latency and runtime rendering/cancellation remain unverified. Pass 032 is not started.
