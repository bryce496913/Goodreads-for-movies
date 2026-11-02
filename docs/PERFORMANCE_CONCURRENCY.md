# Large-library performance and concurrency — pass 016

## Evidence and scope

The audit used main at merge `10ddbec` (PR 015) as the baseline. These are source-level findings, **not measured frame-time or latency bottlenecks**. This Linux worker has no Swift compiler, Apple frameworks or XCTest runtime. No native benchmarks, XCTest, Xcode compilation, simulator, signing or device-build checks were performed. No numeric speedup, responsiveness guarantee or arbitrary timing threshold is claimed.

| Path | Baseline source finding | Change / remaining cost |
| --- | --- | --- |
| Library rows | Main-actor normalization/projection, sort on each source revision, synchronous scan on each filter/search edit | Scalar/`Data` Sendable capture; off-actor normalization, fallback JSON, validation, sort and filter. Sorted values reused for filter-only edits. Dedicated library revision avoids reprojection for unrelated diary/progress changes. Capture still O(titles) when library rows change. |
| Persistence writes | Full-store integrity fetch, save, six more fetches on reload, a second full integrity audit and unrelated array sorts | Reconcile pending inserts/deletes with loaded rows, one pre-save audit, explicit save, publish only affected collections. No success-path full reload. Rollback/retry/import retain full reload. Audit, reconciliation and affected-entity index rebuild remain linear on main actor. |
| Detail/diary rows | Linear title, review, event and review-link scans per rendered row | Typed-identity dictionaries and event-link set; chronological event arrays retain existing deterministic ties. List rendering remains lazy. Full history remains loaded in memory. |
| Episode UI | Each watched lookup scans all progress; every season rebuilds watched-ID set, scans unrelated progress and decodes/merges episodes repeatedly | Exact episode and series/season indexes; one watched set per committed revision; cached merged season episodes and summaries. Only requested season/series is recomputed after invalidation; summaries expire at UTC day boundaries. |
| Episode mutations | Single toggle fetches all series progress before matching ID | Exact series/provider-episode predicate with limit two to retain duplicate detection. Catalog/season operations still validate series-wide records as needed. |
| Metadata refresh | Scans whole title/review/diary tables to update one identity | Predicates for exact media kind/provider ID, bounded exact metadata-state lookup. Metadata-expiry purging still scans and decodes full-store snapshots: retention guarantees are preserved. |
| Dashboard / ratings | Already captured Sendable values and aggregated off actor, but replacement did not cancel older detached work | Replacement explicitly cancels older worker; added cancellation checks during diary/review/season aggregation and large sorts. Generation check prevents stale publication. Shared Home/Profile revision/day guard remains. Full aggregation/capture still O(store size), with sort costs. |
| Provider mapping / UI | Networking actors map bounded provider pages; UI result/detail models use generation/cancellation checks | Existing architecture retained. No unmeasured provider mapping rewrite. No computation/sort moved into SwiftUI body. |

## Isolation and data ownership

`LibraryStore` remains the **single main-actor writer** with its dedicated, autosave-disabled `ModelContext`. Saves are synchronous and contain no suspension points: concurrent callers serialize on the main actor. Failed saves roll back and reload committed values/indexes; no optimistic detached write or competing writer exists. Existing uniqueness/association audit rules remain enforced before saving. No schema changes, persisted aggregate columns, data reset, destructive migration or persistence framework were introduced.

Successful transactions reconcile `insertedModelsArray`/`deletedModelsArray` against loaded entities using persistent model identity; updates already belong to this context. They audit the resulting full set, save explicitly, then publish affected arrays and rebuild only the affected entity indexes in their existing deterministic order. This relies on the established single-writer boundary: an external context/import must finish and call `reload()` before subsequent store operations. External simultaneous writers are unsupported. Explicit reload still performs all fetches and the integrity audit; existing duplicate/corrupt records are reported, never silently merged.

Indexes contain context-owned models and **never leave the main actor**. Duplicate groups remain arrays rather than being collapsed to a single record. Read semantics retain the first existing row, while mutation queries and the full pre-save audit reject newly introduced duplicates. Pure `LibraryItemInput`, `LibraryItem`, `LibraryOptions` and `DashboardInput` values are Sendable. They contain scalar/Foundation value copies, not ModelContext or SwiftData models. Detached workers only compute read-only projections. Their owners publish results on the main actor after cancellation and generation checks.

Library source/filter/sort changes cancel both pending publication and the detached computation. Cancellation is checked during capture conversion, comparisons and filtering. Superseded generations cannot publish. The previous consistent projection is retained while the UI shows an updating indicator; selection/filter semantics and stable row UUIDs are unchanged. `waitForUpdates()` allows deterministic tests without time-based sleeps; `cancelUpdates()` permits an explicit canceled refresh to retry the same source revision.

Episode summary caches are ephemeral, invalidated after each progress/season commit or reload and keyed by UTC civil day for aired eligibility. No redundant total is persisted. A toggle invalidates computed summaries, and the next read recomputes only the requested season/series from indexed records. The one-pass counter preserves duplicate-ID, special/future/unknown-air-date rules. A generic series watch/status still never invents episode progress. Rapid toggles preserve the original record identity, ratings and other personal content.

## Deterministic fixtures and correctness coverage

`MovieTrackerTests/LargeLibraryFixtures.swift` exists only in the unit target. It builds 100/1,000/5,000 title values and isolated in-memory SwiftData stores, 10,000 episode-progress records across 100 series, and 5,000 repeat-watch diary records. IDs, civil dates, ties, missing years, favorite flags and half-star ratings are deterministic. Fixture insertion is batched before measuring; production launch never seeds these values. No network is used.

Thirteen new functional regression methods cover fixture cardinality/statistics, sort/filter/search consistency, rapid query/filter/sort replacement, source replacement, explicit cancellation/recovery, late dashboard completion, canceled dashboard retry, indexed chronology/review detachment, rapid toggles, concurrent idempotent calls, failed-save rollback, library-only revision invalidation, and day-boundary eligibility. Existing Library organization tests now await actual projection completion rather than assuming synchronous publication. Existing persistence/disk migration and feature regressions remain required.

## Reproducible local benchmark harness

`LargeLibraryBenchmarks` supplies **15 XCTest performance methods** using `XCTClockMetric` and `XCTMemoryMetric` with no baseline threshold. Fixtures are constructed outside the measurement block. Tests measure:

- Filtering, rating sorting and normalized local search separately at 100, 1,000 and 5,000 titles.
- Dashboard aggregation with 5,000 titles, 5,000 diary events and 10,000 progress records.
- A committed episode toggle against the large store, including audit/index costs. Fixture provider IDs use `fixture:`; this does not measure TMDB-specific expiry decoding/purging.
- History retrieval: 100 identical title lookups over 5,000 events, both indexed and the retained baseline full-scan expression.
- Episode reads: 100 IDs distributed across 10,000 records, both indexed and the retained baseline `first` scan expression.

Use the shared MovieTracker scheme in local Xcode, Release configuration, one fixed installed destination, and select the `LargeLibraryBenchmarks` class in the Test navigator. Run functional `PerformanceConcurrencyTests` and `LibraryOrganizationTests` separately before comparing performance. Do not treat grammar parsing or this harness's presence as passing tests. No Xcode commands were executed in this pass.

For comparable measurements, keep hardware/OS, Xcode/SDK, destination, Release optimization, XCTest metric settings/iterations, thermal state and fixture counts constant. Retain the `.xcresult` and report median/spread, not just one iteration. The paired scan/index methods supply reproducible baseline expressions on the same fixture/runtime. They exclude index construction intentionally; the committed-toggle benchmark includes its rebuild cost. The library CPU kernels preserve semantics; moving them off actor is a scheduling change and is not evidence of a faster kernel. Use Time Profiler/Hangs locally to assess main-actor occupancy separately from elapsed CPU time.

To compare *end-to-end historical* behavior, run the same fixture/workload definitions against parent `10ddbec` in a separate local checkout, adapting the harness to its synchronous Library model (there is no `LibraryProjection` type in that parent). Keep that adaptation read-only and record it alongside results; do not compare different operations or count fixture setup as only one side's cost. No historical native end-to-end baseline was run or backfilled here.

| Metric | Baseline | Updated |
| --- | --- | --- |
| Library filter/sort/search at all three sizes | NOT RUN | NOT RUN |
| Dashboard aggregation | NOT RUN | NOT RUN |
| Committed episode update | NOT RUN | NOT RUN |
| Diary lookups (paired reference/index harness) | NOT RUN | NOT RUN |
| Episode lookups (paired reference/index harness) | NOT RUN | NOT RUN |

## Validation and remaining risks

Passed here: project parse/reference resolution and complete source membership in all three targets, grammar parsing for 117 Swift files, asset/resource metadata checks and whitespace checks. Grammar parsing does not type-check Swift 6 actor isolation, SwiftData macros or XCTest APIs. Repository inventory is 285 methods: 245 unit-target methods (including 15 benchmarks), 40 UI methods. **All native tests and benchmarks remain UNRUN.**

Launch/reload, scalar snapshot capture, full integrity validation, metadata purging, index rebuilding and changed-collection ordering still execute on the main actor. A 10,000-row write can still incur meaningful work. Keeping these safety operations serial avoids a suspension/reentrancy window that could validate one revision and save another. Measurement should determine whether a future immutable integrity snapshot or model-actor design is justified; this pass does not assert those costs are solved. Caches/indexes add linear memory overhead; large diary screens still hold the full chronological history. No pagination or persistent aggregate was introduced without evidence. Native regression execution and profiling are required before claiming runtime acceptance.
