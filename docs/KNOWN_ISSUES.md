# Known issues — V0.7 integration and historical releases

## Current V0.7 disposition — Pass 043

**READY PENDING NATIVE TEST EXECUTION**, not V0.7 VALIDATED. See [V0.7 evidence and precise commands](V0.7_TEST_PLAN.md) and [acceptance checklist](V0.7_RELEASE_CHECKLIST.md). Source audit/static checks and authored integration regressions support isolated native validation; they do not establish safe runtime upgrades on valuable original data.

| ID / severity | Finding | Disposition |
| --- | --- | --- |
| V07-001 / P1 evidence gate | No current-revision Xcode compile, full XCTest, copied-store migration, backup/relaunch or core accessibility/navigation execution is available in Linux. This is not an observed crash/test failure. | Native execution required before VALIDATED. Prior owner device passes apply to earlier code only. Stop/preserve data on migration/restore failure; never reset the store. |
| V07-002 / blocked provider feature | Applicable durable/offline artwork rights remain unconfirmed; disk caching is not implemented. | Existing bounded memory/placeholder fallback only. Pass 042 rights/alternative-provider decision remains authoritative; do not count persistent artwork as completed. |
| V07-003 / P2 evidence gap | Main-actor capture/purge/integrity/index costs, JSON/image decode/buffered HTTP memory and new UI/Charts layouts lack native profiling/accessibility evidence. | Existing large fixtures plus new Calendar/fast-log benchmarks are authored, timings UNRUN. Run compact/large/large-text/VoiceOver/light-dark checks and fix measured issues. |
| V07-004 / P2 release limitation | No automatic cloud sync or guaranteed offline provider Browse/Similar/artwork after relaunch. | Personal workflows remain local; provider requests need network/authorized configuration. Use manual personal-only backups; no new service or provider added. |

No additional confirmed unresolved P0/P1 **production source defect** was established in this bounded review. That is not proof of absence; V07-001 remains a real validation gate. The stabilization diff adds cross-feature tests, benchmark harnesses and evidence documentation without rewriting production behavior. Schema V3, seven-stage migration plan, portable v2/v1 backups, Pass 035 archive safety and Pass 036 transaction ownership are preserved.

## Historical V0.6 disposition — Pass 035

**READY FOR PERSONAL DEVICE VALIDATION. V0.6 VALIDATED is not established.** The fixed source finding below and passing Linux static checks support isolated owner-run Apple validation, not a claim of verified real-store upgrade safety. See [checklist](V0.6_RELEASE_CHECKLIST.md) and [actual test evidence](V0.6_TEST_PLAN.md). TestFlight, signing for distribution and uploads are deferred, not V0.6 completion gates.

| ID / classification | Current finding | Disposition |
| --- | --- | --- |
| V06-001 / P1 source defect | Recovery conversion could traverse substituted backup-directory links, then open/delete outside the managed folder. | Fixed by rejecting linked directories and linked/nonregular managed files before conversion. Four regression cases authored, native UNRUN. Invalid/unknown paths are preserved and reported, retaining provider blocking. |
| V06-007 / P1 source defect | Archive-only folders bypassed validation of corrupt/unsupported recovery JSON. | Fixed by revalidating supported recovery archives and preserving/reporting unknown nonempty folders. Three native regressions authored, UNRUN. |
| V06-002 / P1 evidence gate | All SwiftUI/SwiftData compilation, migration, disk/relaunch and UI tests remain unexecuted on Linux. No observed native failure is claimed. | Run full shared scheme and real copied historical stores before promoting to validated or upgrading valuable data. Never reset a failed database. |
| V06-003 / gated provider feature | Pass 030 persistent artwork rights remain unresolved; live provider/account authorization is not verified here. | Disk artwork remains disabled. Bounded memory/placeholder fallback is implemented; owner authorization is required for provider activation. No legal certification. |
| V06-004 / P2 | Large-scale main-actor capture/integrity/index work and image decode lack native performance evidence. | Added 500-collection/5,000-membership/discovery benchmarks; all timing/memory results UNRUN. Profile before optimizing. |
| V06-005 / P2 | Native accessibility/custom move actions, sheet announcement timing, multiline name field, numeric year formatter, compact safe areas and long localized strings remain unverified. | Complete Pass 034/035 native manual matrix and record screenshots/results. |
| V06-006 / P2 documentation defect | Historical text claimed no export/restore, six schema shapes and obsolete repeated-read costs. | Corrected for personal-only v2/v1 backups, eight retained shapes/current V3 and current remaining costs. |

No known unaddressed P0/P1 **source defect** was established by this bounded review after the path fix. This does not waive P1 evidence gates or prove an absence of runtime defects. Existing private data stays local; no cloud sync/automatic backup was added.

## Historical V0.5 release record

The following earlier distribution/release notes remain historical; distribution-specific signing/TestFlight gates do not define the current V0.6 implementation gate.


Pass 014 adds a conservative metadata lifecycle; see [METADATA_POLICY.md](METADATA_POLICY.md). It has not executed on Apple frameworks.

Release classification: **NOT READY — BLOCKERS REMAIN**. Severity describes release impact; an unexecuted check is an evidence gap, not an observed crash. No observed P0 incident was established by this static pass. Absence of runtime evidence does not establish absence of P0/P1 defects.

| ID / severity | Finding / reproduction | Resolution or release gate |
| --- | --- | --- |
| BETA-001 / P1 gate | Clone on this Linux worker and invoke `scripts/validate-v05.sh`: exit 69, no Xcode/SDK/simulator. No iOS build or XCTest evidence exists. | Run Debug/Release and all tests on macOS; repair diagnostics/failures. Compiler warnings and runtime behavior cannot be enumerated reliably here. |
| BETA-002 / P1 gate | Open Signing/Assets: default ID is `com.example.MovieTracker`, no team, and the supplied AppIcon has not been validated in an archive. An uploadable signed/validated archive cannot be claimed. | Owner supplies registered ID/team and validates a real Release archive, including the configured icon. Preserve existing app identity for data-upgrade tests. |
| BETA-003 / P1 gate | Attempt upgrade of an actual pre-011 store: no executed migration evidence is available. Frozen schemas now have an explicit additive plan, including V2 lifecycle state, but historical adoption still lacks runtime evidence. | Execute the new PR010 fixture test and real historical store copies. Do not wipe/recreate the database on failure. Unsupported upgrades must stay blocked until repaired safely. |
| BETA-004 / P1 gate | Inspect API terms §1.C and persisted `snapshotData`, season/episode JSON: terms prohibit caching TMDB information longer than six months; pass 014 adds 150-day leases, local purge and personal-only backup conversion. | Execute the lifecycle/migration/recovery tests and obtain owner/provider confirmation of identifier retention, dormant-device lazy cleanup and account rights. Unknown raw archives block provider activation; no archival exemption is claimed. TestFlight distribution remains blocked. |
| BETA-005 / P1 gate | Settings has no real authorized token in this environment; no live request, provider account/rights or privacy disclosures have been validated. | Confirm account authorization/distribution use, current terms, provider privacy/retention and actual device Search. Complete App Store Connect privacy and export compliance. The bundled manifest is not a substitute. |
| BETA-006 / P1 gate | Simulator/device layout, accessibility, offline/force-quit durability and resource usage have never been executed here. | Complete the named test matrix and physical-device run, with evidence. Fix inaccessible actions, stalls, crashes or data loss before internal testing. |
| BETA-007 / P2 | Save a title, relaunch offline after the OS evicts artwork: text/progress survive, but rows may show placeholders. Library/Home posters read bounded memory only. Cast/session metadata also expires. | Expected current caching limit; do not promise permanent offline artwork/cast. No disk artwork cache is written. |
| BETA-008 / P2 | Change/remove a provider token while a detail page remains on another tab, then revisit that still-open page. Its retained model uses the prior service. | Reopen that destination. New Search requests cancel/restart with the new service; local data remains usable. |
| BETA-009 / P2 | Edit content on two installations or reinstall/change App ID: no cloud sync exists; manual personal-only export/Keep Existing restore is implemented in Pass 018 and extended for collections in Pass 032. | Local-only limitation. Preserve backups and app identity; never suggest reinstall as data repair. Keychain tokens are device-only and may outlive uninstall, so use explicit Remove Credential when deauthorizing a device. |
| BETA-010 / P2 | Large libraries/season lists: commits reconcile/audit and rebuild affected indexes on the main actor; source snapshot capture and season decoding can still scale with collection size; image decoding also occurs locally. | Profile using the representative datasets. Dashboard heavy aggregation is off actor, but no latency/frame-rate/memory claims are supported. Optimize measured stalls before accepting performance. |

Pass 015 adds mocked authentication/HTTP/retry hardening, but authenticated live Search/details/season checks remain unexecuted because no authorized credential is configured. Current client-held credentials are not a confidential production-secret solution. See [TMDB_NETWORKING.md](TMDB_NETWORKING.md).

## Repaired in pass 012

| Finding / prior impact | Repair / regression coverage |
| --- | --- |
| P1 source build defect: five diary calls referenced nonexistent `writeDiary` after the transaction helper was renamed. | All use existing `writeTransaction`. Offline integration, rollback and migration tests complement the existing 17 diary tests. Static grammar alone did not detect this defect; real compilation remains mandatory. |
| P1 installed-beta Search setup failure: only an Xcode Run environment credential was supported. A TestFlight app cannot receive that scheme environment. | Native Settings saves/removes a device Keychain token and refreshes Search’s service; no embedded secret or account feature. Keychain tests use unique isolated service names; UI tests use memory-only credentials. Live authorization and device Keychain behavior remain unverified. |
| P1 provider attribution gap: no approved logo or About/Credits placement. | Official unmodified TMDB SVG and FAQ notice in local About & Credits. Attribution layout and provider/distribution rights still need owner validation; BETA-004 remains. |
| P2 accessibility risk: Search’s segmented filters can compress at accessibility sizes. | Same native menu fallback used by Library, with a largest-category UI regression test. Runtime layout still unverified. |
| P2 stale artwork error risk during service replacement. | Canceled artwork tasks cannot publish failure into the replacement configuration. Search replacement regression checks obsolete search results remain rejected. |
| P2 obsolete UI navigation test: it scrolled a ScrollView after Profile changed to List and expected removed placeholder Settings text. | Scrolls the actual app content and checks the real credential status screen. |

No user database was reset, migrated in this Linux runtime, seeded, or deleted. Existing schema declarations are unchanged in this pass. No GitHub Xcode CI, archive upload or PR merge was performed.

- Pass 016 removes redundant success-path reloads and repeated read scans, but integrity audit, metadata purge and index rebuilding remain main-actor costs. All large-library benchmarks and new concurrency regressions await native execution; see [performance report](PERFORMANCE_CONCURRENCY.md). No measured speedup is claimed.

- Pass 017 supports saved text and personal edits without mandatory provider calls, but artwork remains process-memory-only under the project policy. Offline tests and disk-container reopen regressions are authored but unrun; see [offline matrix and remaining limits](OFFLINE_RELIABILITY.md).

- Pass 018 adds manual personal-only JSON export and Keep Existing Data merge. Native document pickers, disk save-failure regressions and maximum-size responsiveness are unverified. Backups are plaintext and not automatic; invalid existing ratings/integrity errors block preparation. See [backup and restore](DATA_BACKUP_AND_RESTORE.md).

Safety snapshot creation also rejects a substituted symbolic-link backup root before writing private data; the linked-root regression verifies no external snapshot is created. Native execution remains UNRUN.

## Pass 036 pre-device follow-up

**READY PENDING XCODE VALIDATION.** Nested committing writers could flush outer pending changes before rollback; a main-actor transaction ownership guard now rejects reentry before the nested save. Shared offline routing missed collection-only identities; indexed membership lookup now returns an identity placeholder. Main Library removal confirmation explicitly preserves collections and warns about ID-only display; it continues to explicitly remove the entry's rating/status/favorite. No new cascade, schema or backup-format change. Four new unit methods and strengthened offline coverage are authored, all native UNRUN. See [scope, tests, reviewed-correct paths and remaining data-integrity gates](PRE_DEVICE_HARDENING.md). Do not treat these source repairs as executed SwiftData or device validation.
