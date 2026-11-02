# Known V0.5 issues — 2026-11-02

Pass 014 adds a conservative metadata lifecycle; see [METADATA_POLICY.md](METADATA_POLICY.md). It has not executed on Apple frameworks.

Release classification: **NOT READY — BLOCKERS REMAIN**. Severity describes release impact; an unexecuted check is an evidence gap, not an observed crash. No observed P0 incident was established by this static pass. Absence of runtime evidence does not establish absence of P0/P1 defects.

| ID / severity | Finding / reproduction | Resolution or release gate |
| --- | --- | --- |
| BETA-001 / P1 gate | Clone on this Linux worker and invoke `scripts/validate-v05.sh`: exit 69, no Xcode/SDK/simulator. No iOS build or XCTest evidence exists. | Run Debug/Release and all tests on macOS; repair diagnostics/failures. Compiler warnings and runtime behavior cannot be enumerated reliably here. |
| BETA-002 / P1 gate | Open Signing/Assets: default ID is `com.example.MovieTracker`, no team or approved AppIcon. An uploadable signed/validated archive cannot be claimed. | Owner supplies registered ID/team/icon and validates a real Release archive. Preserve existing app identity for data-upgrade tests. |
| BETA-003 / P1 gate | Attempt upgrade of an actual pre-011 store: no executed migration evidence is available. Frozen schemas now have an explicit additive plan, including V2 lifecycle state, but historical adoption still lacks runtime evidence. | Execute the new PR010 fixture test and real historical store copies. Do not wipe/recreate the database on failure. Unsupported upgrades must stay blocked until repaired safely. |
| BETA-004 / P1 gate | Inspect API terms §1.C and persisted `snapshotData`, season/episode JSON: terms prohibit caching TMDB information longer than six months; pass 014 adds 150-day leases, local purge and personal-only backup conversion. | Execute the lifecycle/migration/recovery tests and obtain owner/provider confirmation of identifier retention, dormant-device lazy cleanup and account rights. Unknown raw archives block provider activation; no archival exemption is claimed. TestFlight distribution remains blocked. |
| BETA-005 / P1 gate | Settings has no real authorized token in this environment; no live request, provider account/rights or privacy disclosures have been validated. | Confirm account authorization/distribution use, current terms, provider privacy/retention and actual device Search. Complete App Store Connect privacy and export compliance. The bundled manifest is not a substitute. |
| BETA-006 / P1 gate | Simulator/device layout, accessibility, offline/force-quit durability and resource usage have never been executed here. | Complete the named test matrix and physical-device run, with evidence. Fix inaccessible actions, stalls, crashes or data loss before internal testing. |
| BETA-007 / P2 | Save a title, relaunch offline after the OS evicts artwork: text/progress survive, but rows may show placeholders. Library/Home posters read bounded memory only. Cast/session metadata also expires. | Expected current caching limit; do not promise permanent offline artwork/cast. No disk artwork cache is written. |
| BETA-008 / P2 | Change/remove a provider token while a detail page remains on another tab, then revisit that still-open page. Its retained model uses the prior service. | Reopen that destination. New Search requests cancel/restart with the new service; local data remains usable. |
| BETA-009 / P2 | Edit content on two installations or reinstall/change App ID: no cloud sync/export/restore flow exists. | Local-only limitation. Preserve backups and app identity; never suggest reinstall as data repair. Keychain tokens are device-only and may outlive uninstall, so use explicit Remove Credential when deauthorizing a device. |
| BETA-010 / P2 | Large libraries/season lists: store commits reload collections on main actor, Library sorts/projections and season JSON/progress can repeat on redraw; image decoding also occurs locally. | Profile using the representative datasets. Dashboard heavy aggregation is off actor, but no latency/frame-rate/memory claims are supported. Optimize measured stalls before accepting performance. |

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
