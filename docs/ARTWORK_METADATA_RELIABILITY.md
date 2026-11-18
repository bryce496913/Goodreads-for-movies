# Artwork and metadata reliability — Pass 042

## Authorization decision: BLOCKED

Persistent offline artwork is **not completed or enabled**. The repository contains no app/account-specific authorization resolving durable artwork retention, underlying image rights, actual commercial classification and deletion obligations. This does not mean every provider prohibits caching. Public technical caching guidance and an API token do not establish every right needed by this particular app. No legal certification is claimed.

Official sources reviewed in this pass:

- [TMDB API terms](https://www.themoviedb.org/api-terms-of-use): HTTP 200 on 2026-11-17 and rechecked 2026-11-18.
- [TMDB FAQ](https://developer.themoviedb.org/docs/faq) and [image basics](https://developer.themoviedb.org/docs/image-basics): HTTP 200 on 2026-11-17.
- [TVmaze API](https://www.tvmaze.com/api): HTTP 200 on both review dates.
- [Commons reuse guidance](https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia): HTTP 200 on both review dates.
- fanart.tv's public terms URL returned HTTP 403 on 2026-11-17; current terms could not be evaluated, so it is not treated as an authorized candidate.

TMDB terms §1 cover a conditional license including visual content, a prohibition on caching API information longer than six months, and cessation/purging requirements on termination. §2 requires a written agreement for commercial/revenue-generating use. §3 requires attribution and no implication of endorsement. The FAQ disclaims ownership of API images/data and describes takedown handling; it does not resolve underlying poster rights for this app. Image basics explains sized CDN URLs, not a new offline license. The existing approved logo/notices in About & Credits remain unchanged.

The six-month ceiling is not read as blanket permission for this app's proposed disk cache. We preserve **30-day refresh eligibility and a 150-day maximum**. A shorter technical cache duration alone does not settle commercial classification, third-party rights, offline redistribution, license termination or content physically retained on a dormant device.

Questions requiring an applicable provider/rightsholder authorization or written clarification remain: which account/app/distribution is covered; whether bounded app-managed cross-launch/offline poster/backdrop copies are permitted; whether that grant covers underlying images; attribution placement; allowed duration and deletion after revocation/termination; and treatment of a suspended/powered-off device that cannot run expiry maintenance. No provider was contacted or new integration approved by this pass.

## Alternative source comparison

| Candidate | Persistent storage / licensing evidence | Coverage and identity | Sizes, reliability and operations | Decision |
| --- | --- | --- | --- | --- |
| Existing TMDB | Conditional API content license; six-month ceiling; third-party/account scope unresolved. Noncommercial attributed access is conditional, commercial use requires written agreement. | Movies + TV, existing typed `tmdb:` IDs and metadata routes. | Existing sized URLs, attribution, cancellation, retry and purge paths. No provider migration cost. | Keep current authorized-use configuration and memory-only fallback; proposed persistent artwork stays blocked. |
| TVmaze | API page explicitly recommends server/client image caching and describes stable image URLs as cacheable indefinitely. API data is offered under CC BY-SA with source attribution/ShareAlike requirements; enterprise terms are separately available. This is clearer public client-caching guidance, not a blanket conclusion about every underlying image/right or this app's accepted license obligations. | TV shows/episodes, not a movie replacement. Stable TVmaze IDs; lookup supports IMDb/TheTVDB references. Current app has TMDB identities, so a verified crosswalk/new namespace is needed; name matching alone is insufficient. | Poster/banner medium/original variants and other image types; documented rate limiting (at least 20 calls per 10 seconds/IP), immutable image URLs and show updates. Another adapter, attribution/license handling, mappings and invalidation policy would be required. No SLA is inferred from public access. | Promising TV-only candidate for an explicit integration/license decision; not automatically installed or used, and its indefinite URL guidance does not extend TMDB's lease. Movie coverage and applicable image/ShareAlike scope remain unresolved. |
| Wikimedia Commons | Qualifying files may permit durable reuse under their actual CC/public-domain licenses. Each file's description controls conditions; creator credit, license links, modification/ShareAlike requirements and additional personality/trademark rights can apply. Commons gives no universal warranty for a file's claimed rights. | Some film/TV-related images, with uneven poster coverage. No drop-in complete TMDB poster catalog or guaranteed one-to-one title mapping. File/page IDs and sometimes Wikidata links require verified matching. | File originals/thumbnails vary in quality; per-file attribution/provenance, deletion/replacement tracking and API usage rules add substantial work. No image scraping or bulk feed is authorized here. | Potential per-file licensed supplement after verification and approval, not an automatic movie/TV artwork provider replacement. |

No source has been swapped, no new API credentials requested, and no image URL allowlist expanded. Content simply visible on the web is not assumed free to archive. The conditional 100 MB disk-cache implementation and disk/relaunch acceptance criteria remain **blocked/not implemented**, rather than simulated with URLCache.

## Implementation audit and changes

The baseline is ProviderArtworkLoader's shared sized-URL flights, per-consumer cancellation, credential/cache-generation publication guards and ephemeral cache-disabled transport. ProviderArtworkCache remains a 40-entry / 40,000,000-byte estimated-cost memory LRU, with a 2 MB encoded-response validation limit, original download receipts, explicit expiry and manual clear. Local Library/Home thumbnails stay cache-only; Search/Detail can fetch sized optional artwork. Relaunch/eviction can lose images. There is no persistent artwork directory, manifest or fallback disk/URLCache.

Changes:

- `ProviderArtworkPolicy` explicitly records the blocked durable-storage decision and existing memory/image bounds; there is no runtime authorization switch. Settings explains bounded memory and unavailable offline artwork after relaunch.
- ImageIO inspects frame count, encoded dimensions and estimated decoded cost **before** UIKit decoding. Empty, oversized, invalid, over-dimension and multi-frame artwork is rejected without replacing an existing usable entry. Static sized provider artwork is supported; animated/multi-frame images get placeholders. This mitigates oversized decode allocation; it is not a measured decode speedup or a streaming-download memory guarantee.
- A retained saved poster URL is now visible only while the corresponding title snapshot is usable at the actual presentation time. Exactly expired title metadata cannot continue showing its old poster through the saved-URL fallback while waiting for maintenance.
- Detail recovery status and explicit Refresh/Retry move near the artwork/title instead of below long reviews/history. Missing synopsis, genres, runtime/artwork or TV season catalog are described as unavailable optional fields, not fabricated values or proof that a request failed. Sparse **fresh** snapshots still open without requests; only an explicit refresh tries to fill them before the existing 30-day eligibility point. No new automatic retry loop is introduced, and a genuine provider omission can remain missing after success.
- Existing force/retry paths still respect rate-limit deferral, identity checks, cancellation and credential epochs. Successful responses update only applicable metadata through the shared LibraryStore methods. Failed refreshes preserve their old successful receipt, personal records and existing backoff rules. We do not fetch every saved title on launch.
- Local metadata maintenance/save errors are now separate from provider/network errors: recovery reports a local save problem rather than calling it offline or imposing a provider failure deadline. Credential invalidation also clears old presentation error state.
- Friendly `Title information unavailable` is a **presentation-only** replacement for the exact technical placeholder in Details, Library and dashboard rows. Unknown titles retain a reference label in Details/Library for disambiguation. Persisted placeholder strings, MediaIDs, navigation, filtering and backup fields remain unchanged. Existing episode/season unavailable states and watched-flag controls remain in place.

There is no new persistence writer, destructive migration, provider-data archive, rating/status semantics change or backup format change. Schema, purger, mutation services, collection transactions and episode progress semantics remain unchanged.

## Data integrity and tests

Added **13 unit regressions** in ArtworkMetadataRecoveryTests and **2 UI regressions** in MetadataRecoveryUITests. Tests cover the blocked gate/bounds, fresh memory/relaunch placeholder behavior, invalid/oversized artwork, friendly identity-preserving labels, missing fields, sparse-fresh/no-request then explicit refresh, exact-expiry saved-poster hiding, offline/backoff/manual recovery, rate-limit deferral, cancellation, credential invalidation, collection-only recovery, failed/successful season recovery with exact watched-episode preservation, and local save failure classification.

Deterministic in-memory stores compare canonical portable personal backups before and after expiry, refresh/failure/cancellation/credential changes. Fixtures include identity/status/favorite/rating dates, review-event associations and private text, undated diary, collections with manually reordered memberships, a movie/series sharing a numeric ID and watched episode flags. A collection-only reference stays navigable and refresh does not recreate its removed Library row. Existing season/progress, backup, clear/late-flight, coalescing, LRU, expiry and offline artwork tests remain applicable. The long-content UI regression now verifies refresh before scrolling to the synopsis, matching its new location.

Executed cloud checks:

- OpenStep project/reference validation and complete source membership for all three targets.
- Swift grammar parsing for **175 source/test files** (not compilation/type checking).
- Exact comparison of original build configurations/PBXProject settings with base.
- Semantic design validator: nine assets, four appearances, 44 intended text contrast pairs.
- `git diff --check` and unchanged schema/persistence-mutation sources.
- Official-document HTTP checks listed above; no credential-bearing live API or image smoke request.
- Simulator-unavailable validation reports expected **exit 69 / UNVERIFIED** because this Linux workspace has no Xcode, Swift compiler, Apple SDK or simulator.

Repository totals are **477 unit/benchmark and 97 UI methods**. **Native XCTest, ImageIO/UIKit decode behavior, SwiftData/runtime cancellation and all device/simulator UI/accessibility checks remain unrun for this revision.** Earlier owner device success is not evidence for this change. No screenshot or benchmark result is fabricated. New UI tests attach a recovery screenshot when executed locally. No disk-cache/relaunch-persistence test is claimed because that implementation remains blocked.

Owner validation: run the shared MovieTracker scheme's full Test action, including ArtworkMetadataRecoveryTests, MetadataRecoveryUITests, OfflineArtworkTests, OfflineReliabilityTests, MetadataLifecycleTests, TVProgressTests, Collection/Backup tests and existing Detail/UI tests. Use README's `xcodebuild test` command with an installed simulator, and isolated/copied data. Verify explicit sparse-detail recovery, airplane-mode/failed refresh, rate-limit waiting, missing/expired titles and posters, intact private actions/history/collection order, progress edits, cache clear while loading, credential changes and offline relaunch placeholders. Check compact/large screens, light/dark, largest Dynamic Type and VoiceOver. Persistent offline artwork must still be marked unavailable.

Outstanding limitations: app-specific artwork rights/authorization, incomplete alternative-provider coverage/mapping, no guaranteed offline images after relaunch, buffered transport peak memory and main-actor UIKit decode profiling, dormant-device retention/deletion constraints and unverified native/runtime behavior. No legal certification or release-readiness claim; no merge or Pass 043.
