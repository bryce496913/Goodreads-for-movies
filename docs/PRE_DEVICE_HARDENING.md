# Pass 036 — pre-device hardening

**READY PENDING XCODE VALIDATION.** No native compilation, SwiftData migration, XCTest, simulator or device success is claimed. Use disposable/copied data for the first Apple run. No new feature, store reset, safety-archive deletion, app identity change, artwork disk cache, TestFlight upload or next development pass.

## Confirmed source findings and repairs

1. **Nested commits could escape an outer rollback.** `writeTransaction` exposes a staging closure; invoking a public committing writer inside it could call `savePendingChanges` and flush the outer pending changes before a later outer error. Reviewed feature paths currently use noncommitting helpers rather than intentionally nesting writers, but the API composition itself lacked a safeguard. A main-actor ownership flag now rejects nested entry into `writeTransaction`, Library mutation or removal **before** the nested writer changes or saves anything. The outer transaction retains its save/rollback boundary; the flag is released on success, failure and early return. `ensureLibraryEntry` remains a staging helper and can reuse one pending identity without an inner commit. No second context/writer is introduced.
2. **Collection-only identities were omitted from shared offline routing.** After removing a Library row, or restoring a membership-only backup, `offlineMedia` checked Library/reviews/diary/seasons but ignored collection memberships. Collection rows had a fallback, hiding the shared lookup gap; legacy/unknown-namespace Details could lack its local snapshot/actions. The indexed membership set now qualifies a saved identity for a placeholder. This performs no fetch, provider request, metadata lease renewal or personal-row recreation.
3. **Removal confirmation omitted collection scope.** The dialog now says that collection memberships remain and may show an ID without retained metadata. It already explicitly says the Library entry/rating/status/favorite are removed and written reviews/history/progress remain. No silent cascade or new removal semantics is introduced.

## Removal and collection semantics

A membership references the exact typed/provider-qualified `MediaID`, not a Library row UUID. It is an independent saved reference, not a dangling SwiftData relationship. A statusless row is valid. Main Library removal deletes that row's status, favorite and rating only after the existing explicit confirmation; it preserves memberships/order, separate reviews/diary/episode flags and archives legacy review text. Collections still navigate using available retained data or a placeholder; personal-only restore must not recreate the deleted row or its removed rating/status.

Removing from **Collection A** removes only A's membership and compacts A's positions. Collection B and personal data stay intact. **Delete Collection** removes only that collection and its memberships. None of these operations infer Watched/Watching, alter ratings, delete reviews/diary/episode progress or silently duplicate a title. Unknown/expired metadata remains unavailable; a valid identity is not a fabricated title.

## Focused regression coverage

Added four unit methods in existing files:

- Disk-backed nested writer composition: transaction/mutation/removal/restore variants stage an outer insert, attempt an inner writer, assert no save/changed personal fields, retry after rollback and reopen disk to verify only the intended retry persisted.
- Two calls to the staging helper within one transaction reuse a pending identity and produce one statusless row.
- Shared movie in A/B, independent statusless/rating/status/favorite changes, main removal, collection navigation identity, personal-only export/fresh disk restore/repeat import, deletion isolation and another disk reopen. UUIDs/manual order and review/diary content remain checked.
- Failed main removal preserves the row/rating/legacy text/memberships; retry imports legacy text once and repeated removal creates no duplicate review.

Strengthened the existing collection-only removal test to require the actual shared offline result (rather than masking nil with a test fallback), open its detail model with no service, and verify the Library row is not recreated.

Existing tests already cover failed collection updates/reorder rollback, collection deletion isolation, v2/v1 backup compatibility, populated merge/conflicts/invalid data/cancellation/rollback, historical schemas, offline Home updates/rapid duplicate actions, series independence/specials/future/unknown episodes, discovery OR/year/runtime/expiry/cancellation/no writes, artwork coalescing/cancellation/clear/credential invalidation and personal-data expiry preservation. These paths were reviewed and retained instead of rewritten. No new migration fixture is justified by these non-schema repairs; historical definitions and the seven-stage V3 chain remain unchanged.

## Actual validation

- `node /workspace/scratch/ios-foundation/validate.cjs`: PASS; OpenStep project/references/all three target memberships, grammar parsing of 148 Swift files, asset JSON. **Not compilation, type checking, macros or runtime testing.** Checker is environment-provided, not a new project dependency.
- `python3 scripts/validate-design-tokens.py`: PASS, all 44 intended text pairs across adaptive variants ≥4.5:1.
- `git diff --check` and staged equivalent: PASS.
- Frozen/current schema/entity/migration/project comparisons: unchanged; local relative documentation links resolve.
- `scripts/validate-v06.sh simulator-unavailable`: expected prerequisite rejection (exit 69), not an application-test failure/run.

**All XCTest methods are UNRUN**: 392 unit/benchmark + 80 UI = 472 source-inventoried methods. Linux has no Swift compiler, Xcode, Apple SDK or simulator. No native test pass/fail count, device screenshot, migration result, offline relaunch result or performance measurement is available. Existing performance fixtures remain unchanged; no timing improvement is claimed. No GitHub Xcode CI was added.

## Remaining gates and recommendation

Run `scripts/validate-v06.sh <installed-test-simulator-UUID>` on macOS. Prioritize DataIntegrityTests, CollectionTests, LibraryStoreTests, DataMigrationTests, CollectionBackupTests, BackupRestoreTests, TVProgressTests, WatchDiscoveryTests and OfflineArtworkTests, then existing UI suites. Follow the [V0.6 matrix](V0.6_TEST_PLAN.md) for compact/large devices, VoiceOver/large text, confirmation/keyboard/safe areas and actual offline termination/relaunch. Verify the removal dialog before confirming the intentionally removed rating/status/favorite.

Native SwiftData pending-fetch visibility, rollback/index publication, schema adoption from real historical stores and document-picker durability remain unverified. Supported schemas are source-retained candidates, not certified migrations. Existing unknown-store fail-closed behavior and no-destructive-fallback remain. Persistent artwork is still BLOCKED by rights; bounded memory/placeholder behavior and the 150-day lease are unchanged. No known confirmed source defect from this pass remains unaddressed, but absence of native evidence cannot prove absence of data-integrity failures. Begin Apple validation with isolated fixtures; do not upgrade valuable real data based on syntax checks alone.
