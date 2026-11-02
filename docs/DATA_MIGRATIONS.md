# SwiftData migrations and integrity — pass 013

Current explicit schema: **LibrarySchemaV1, 1.0.0**. This is a persistence version, independent of app marketing version 0.5.0. Its fields match PR011–012; no personal field is removed, renamed, backfilled or converted in this pass. The five model classes are frozen within `LibrarySchemaV1`, with global `Stored*` typealiases preserving call sites and entity basenames.

**Validation status:** source/project checks only. All new disk-backed XCTest cases are **UNRUN** on this Linux worker. No Xcode build, simulator matrix or signing audit was performed, as requested. Adding VersionedSchema/SchemaMigrationPlan does not retroactively prove an old unversioned store can open. Actual historical store copies and the new tests must pass on Apple SwiftData before any supported migration is called verified. The V0.5 release remains blocked pending that evidence.

## Schema inventory and ownership

| Entity | Persisted content | Uniqueness / logical identity |
| --- | --- | --- |
| StoredLibraryEntry | Kind/provider-qualified value, status, independent favorite, legacy Double rating and optional integer half-star rating, rating timestamp, reserved legacy review text, added/updated dates, saved title/year/poster reference/URL and JSON snapshot | SwiftData unique UUID. Application uniqueness is exact `(mediaKind, mediaValue)`. The namespace is part of the opaque mediaValue; no numeric-ID coercion or case/whitespace normalization occurs. Movie `tmdb:42`, TV `tmdb:42`, and movie `other:42` remain distinct. |
| StoredPersonalReview | UUID, exact media identity, text, created/edited dates, optional viewing-event UUID, saved title/JSON and legacy-import flag | Unique UUID; multiple reviews per title are allowed. At most one explicit review may reference a particular viewing event; referenced event must exist and have the same MediaID. |
| StoredViewingEvent | UUID, exact media identity, optional date-only watched date, recorded/updated timestamps and saved title/JSON | Unique UUID; repeats intentionally have separate UUIDs, never separate library identities. |
| StoredTVSeason | UUID, series value/title/JSON, season number/name, expected counts, listing flags, cached episodes/listed IDs and refresh timestamp | Unique UUID plus application `(TV MediaID, season number)` identity. Season 0 is specials. |
| StoredEpisodeProgress | UUID, series value, provider episode value, season number, watched flag/date and episode JSON | Unique UUID plus application `EpisodeID(series MediaID, opaque provider episode value)`. Mutable season/episode numbers do not define identity. |

There are **no SwiftData @Relationship properties or cascade deletion rules**. Associations use stable raw identifiers/UUIDs. Reviews/events/seasons/flags own their snapshots and survive explicit removal of the library row. Lack of a library row is therefore not an orphan. Only a dangling or cross-media review→viewing UUID is an invalid association.

LibraryStore is the main-actor writer with explicit save and rollback. Clearing status preserves ratings/favorites/reviews/history. Clearing rating preserves status/history. Removing the library row intentionally removes its rating/status/favorite after the existing confirmation, archives reserved legacy text and leaves separate reviews/events/episode flags. Deleting a viewing event detaches review links in the same transaction; deleting a review leaves viewing events and personal data intact. Metadata refresh updates caches and stable episode positions, never watched flags or other personal fields. No migration recreates missing personal records.

## Retained history and declared stages

The repository contains these six distinct published shapes. Historical model methods are not persisted; old library constructors adapt to current domain values while field names/types/defaults/unique attributes are retained. Unchanged review/event/season/progress classes are shared with frozen V1, avoiding redundant historical copies. The separate PR012 test-only Legacy010Schema was removed in favor of the production historical definition.

| Shape / schema identifier | Source | Change from predecessor | Disk fixture |
| --- | --- | --- | --- |
| Foundation / 0.1.0 | PR001 `5060993`, unchanged through PR005 | One library entity with UUID/identity/status/favorite/legacy rating/review/dates | Unversioned fixture, UNRUN |
| Snapshots / 0.6.0 | PR006 `7e8f696` | Optional saved title/year/poster/JSON fields | Unversioned fixture, UNRUN |
| Ratings / 0.7.0 | PR007 `6418725` | Optional half-star units, preserving legacy Double | Unversioned fixture, UNRUN |
| Diary / 0.8.0 | PR008 `5bdf099` | Review and viewing entities | Unversioned fixture, UNRUN |
| TV progress / 0.9.0 | PR009 `7c3de2b`, unchanged PR010 `516bb28` | Season and episode-progress entities | Unversioned fixture, UNRUN |
| Current / 1.0.0 | PR011 `f9d4dfd`, unchanged PR012 `5e5a3cc` | Optional ratingUpdatedAt | Unversioned adoption/repeated opening fixtures, UNRUN |

`LibraryMigrationPlan` declares five ordered lightweight stages between these shapes. Every change is optional-field/entity addition; there is no deduplication, deletion, rating rounding, timestamp fabrication, status conversion or review import during migration. Logical duplicate rows retain their UUIDs/content and are reported rather than merged. No new database composite uniqueness constraint is imposed on existing potentially conflicting rows.

### Recognition and historical limits

Before opening an existing library, the factory compares public Core Data entity-version hash dictionaries against reference metadata generated from the retained schemas. It checks actual entity hashes, not just a marker file, filename, app version or a guessed source version. Unknown/mismatched schemas fail closed. Reference stores are empty UUID paths in OS temporary storage, have no user records, are cached by schema for the process, and are **never returned as the application container or used as a fallback**. Current-first matching usually needs only one reference; an older source may require all six. OS temporary cleanup owns those empty references.

Hash recognition is an additional guard, not proof that SwiftData recognizes historical unversioned version identifiers, nested/global type adoption or a particular OS/SDK’s store metadata. The explicit chain must still execute successfully. The tests deliberately create sources using **unversioned Schema(models)**, matching earlier application behavior, plus an explicitly versioned old-source case. Real stores produced by earlier app binaries remain required evidence; reconstructed nested fixture classes alone cannot establish all runtime/model metadata equivalence.

Not claimed supported/verified: local model edits absent from git, intermediate unmerged shapes, downgrades, unknown future schemas, arbitrary Core Data stores, corrupted stores, cross-device copies with incomplete journals, or every OS/Xcode combination. All six retained candidate paths currently lack execution evidence. Unknown stores are preserved and rejected; they are not opened without the plan as a recovery shortcut.

## Opening and failure safety

Both default and explicit-URL container factories use the same frozen schema and migration plan. The default ModelConfiguration name/location is retained; no App ID or user-store location change is introduced. In-memory test containers use the same model plan but no disk-backup path.

For an existing disk file:

1. Validate the SQLite header. Empty/invalid existing files are not treated as fresh installations.
2. Use SQLite’s **online backup API** with a read-only source to create a coherent snapshot, including committed WAL pages. Do not copy a live `.store` file alone. A unique sibling `StoreSafetyBackups/<UUID>/<original filename>` is used. COMPLETE is written only after the snapshot succeeds. Failed partial directories lack that marker and must not be treated as complete snapshots.
3. If backup fails (including busy/locked storage, corruption, permissions or disk space), do not attempt the model open/migration. The user gets a retryable diagnostic stage/code, not an empty library.
4. Check known-schema hashes through read-only Core Data metadata. If matching fails, retain the complete backup and stop before migration.
5. Open with the declared plan. If SwiftData throws, retain the pre-open snapshot and surface a sanitized `open` diagnostic. Never retry without the plan, change URL, delete journals/store, seed personal records or silently use memory/fresh persistent storage.

If the main file is absent but `-wal` or `-shm` remains, stop with `incompleteStore`; do not create an empty replacement. A genuinely new path without store/journals can create a new empty database. The app’s recovery screen displays the diagnostic stage and numeric code, never raw NSError userInfo, SQL, review text or credential data.

A complete snapshot is retained on **every existing-store open**, including normal reopens, and is not automatically pruned or restored. This intentionally trades storage/startup I/O for recoverability in this data-safety pass. Snapshot creation is coherent under SQLite transactions; migration still requires a single app owner of the source with no concurrent external writers. Existing snapshots contain private data and are subject to the existing provider-retention/privacy gate. Current fields use no external binary storage; adding external-storage attributes requires extending/revalidating the backup design. No runtime latency/disk-use benchmark is claimed.

### Recovery procedure

Quit all processes using the store. Preserve the original main file and all journals/support files; do not uninstall, reset or delete anything to unblock launch. Locate the complete StoreSafetyBackups UUID directory through the app container (a PersistenceOpenError also retains its URL for diagnostics). Work on **copies** of the original and the chosen COMPLETE snapshot in an isolated test container. Confirm source schema, counts, IDs, text, dates, ratings and flags before selecting a recovery/migration fix. Never overwrite the actual user store until a concrete recovery has been validated and the owner authorizes restoration. Do not upload private stores to a PR/chat or commit them. Backup-directory cleanup is an explicit owner decision after verified recovery, not automatic application behavior.

## Integrity safeguards

A read-only audit on reload reports duplicate UUID/logical identities, invalid media identities, dangling/cross-media/multiple review associations and inconsistent episode/series snapshot identities. It does not delete, merge, renumber, guess missing fields or recreate parents. Existing conflicts remain visible via the load warning; reads retain records. Invalid legacy rating values remain preserved and use existing unavailable-rating behavior.

Every writer path checks pending records before saving and rolls back a transaction that adds a new integrity issue. Existing issue signatures are retained as the read baseline, allowing unrelated valid edits without silently “repairing” legacy conflicts. Exact target lookup still rejects multiple library matches. TV lookups reject duplicate series/season and series/episode keys across catalog/cache/single/batch operations, including **season unwatch**, which previously could clear both conflicting watched rows. Batch operations resolve the owned season UUID before acting. These are application-level single-writer safeguards, not a claim that UUID uniqueness prevents logical duplicates or that multiple independent processes may race safely.

## Regression tests and results

Added **14 DataMigrationTests** and **8 DataIntegrityTests**, all disk-backed (plus a disk SQLite/WAL backup case), with temporary UUID directories and fixed fixture record IDs/content. They cover each retained historical shape, all available personal fields, typed/provider identity, ratings/legacy text/associated and independent reviews, dated/undated repeat events, cached seasons/flags, two repeat opens, idempotent post-migration edits, explicit stage execution, corrupt/empty/unknown stores, missing-main journals, blocked backups, an injected migration-stage failure with both original/backup content checks, committed WAL inclusion, logical duplicate rejection, ownership/no cascades, metadata/status preservation and failed saves across reopen.

The earlier stabilization migration test now uses the same retained TV-progress schema instead of a second mutable copy. All 22 new XCTest methods and previous suites are **UNRUN** here. Static parsing does not expand @Model, establish schema hashes or validate SQLite/Core Data behavior. No Xcode build, simulator matrix or device signing audit was performed. No GitHub Xcode CI was added.

For the owner’s later persistence-only XCTest run, select DataMigrationTests, DataIntegrityTests and the existing persistence/library/rating/diary/TV/dashboard suites in Xcode. Record OS/Xcode, each actual executed method, failures/skips, source schema/version and before/after record checks on copies of historical stores. Do not replace a failed test with a reset. Only then promote a named source path from candidate to verified.

## Adding the next schema

1. Keep every shipped persisted definition frozen. Do not edit V1’s stored fields or the historical models. Non-persisted feature helpers may evolve without changing attributes/relationships.
2. Create V2 with the required new definition(s), retaining entity basenames and stable identifiers; reuse unchanged frozen classes explicitly. Point current global aliases/registry at V2 and leave old schema types reachable.
3. Choose a distinct persistence version/checksum and append one ordered stage. Do not add duplicate schema shapes solely to mirror marketing versions. Use lightweight migration only for supported additive changes; otherwise design/test a custom stage without fetching unavailable source/destination models in the wrong phase.
4. Preserve personal ownership and association/deletion rules. Do not introduce composite unique constraints that cause upsert/data loss on existing duplicates. Make any conflict repair explicit and reviewable.
5. Update schema recognition, backup coverage (including any external-storage changes), disk fixtures and full-content/reopen/failure tests. Test real unversioned/adopted historical copies and reject unknown future/downgrade stores.
6. Verify failed stages leave a usable pre-open snapshot and recoverable diagnostics. Record actual execution evidence and historical gaps in this document before claiming support. Never add automatic destructive reset, no-plan retry or empty-store fallback.
