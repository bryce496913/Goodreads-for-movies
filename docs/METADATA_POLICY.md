# TMDB metadata policy — pass 014, reviewed 2026-11-02

This policy separates personal records from replaceable provider content. It implements conservative expiration and refresh behavior; it is **not** a certification of a provider license or of runtime compliance. No XCTest, Xcode/device build, simulator matrix or signing audit ran in this Linux pass. Distribution remains blocked pending execution evidence and the owner decisions below.

## Official requirements reviewed

The following official pages returned HTTP 200 on the review date:

- [API Terms of Use](https://www.themoviedb.org/api-terms-of-use). The prior `/documentation/api/terms-of-use` URL redirects here.
- [Developer FAQ](https://developer.themoviedb.org/docs/faq).
- [Getting Started](https://developer.themoviedb.org/docs/getting-started).

API terms §1.A define TMDB Content broadly, including audio/visual content and other information available through, on or from TMDB/API. Section 1.C prohibits: **“Cache, for longer than 6 months, any information obtained through or from TMDB or the TMDB APIs.”** No saved-Library, diary, poster, offline or permanent-archival exception was found. Artwork is treated as provider content, not exempt because an HTTP response/cache header permits storage. The terms provide a ceiling, not an app-specific refresh schedule or a mandatory 30-day interval.

Section 1.D requires ceasing API/content/key use and promptly deleting/purging all cached TMDB Content when the license terminates. Section 2 requires a separate written commercial agreement for commercial/revenue-generating use, directly or indirectly. The FAQ describes noncommercial developer API access as free with attribution; that is not a license approval for this app or a waiver of restrictions. Getting Started links account registration/token use to agreement with the terms. Current restrictions also cover prohibited uses, including AI/ML applications; no such feature is introduced.

Section 3 requires a less-prominent TMDB logo, no endorsement implication and the notice “This [website, program, service, application, product] uses TMDB and the TMDB APIs but is not endorsed, certified, or otherwise approved by TMDB.” The FAQ additionally specifies an approved logo, its standard product/API notice, and About/Credits placement. Existing official `blue_long_2` SVG is unmodified (SHA-256 `9665a76b1ae401a510ec1e0ca40ddcb3b0cfe45f1d51b77a308fea0845885648`). About & Credits displays both notices, preserves aspect ratio/colors, and gives the app name greater visual prominence. Branding-asset permission and third-party content rights remain part of the owner's provider review, not an invented caching exemption.

## Ownership boundary

| Retained personal data / references | Replaceable TMDB content |
| --- | --- |
| Exact typed/provider-qualified media identity; persistent row UUIDs | Provider title, synopsis, genre names/IDs, release dates, runtime, series status, counts |
| Watchlist/Watching/Watched status and independent favorite flag | Saved poster/backdrop references, resolved URLs and downloaded artwork |
| Integer half-star/legacy rating and its own change timestamp | Domain/SwiftData JSON metadata copies, cast previews, provider configuration |
| Private review text, original/edited dates, explicit event association, legacy-import flag | Duplicated provider title/snapshot fields on reviews and viewing events |
| Diary event identity, optional watched date, recorded/updated dates, repeat events | Season names/listings/coverage, episode titles/descriptions/dates/runtime |
| EpisodeID, watched/unwatched flag/date, structural season anchor used to associate a user's action | Episode JSON content beyond the minimal identifier/association placeholder |

Stable external IDs and structural anchors are retained solely to identify personal actions, as required by the app’s data model. This is not a claim that the terms expressly exempt identifiers; the owner must confirm that treatment with the applicable license. No provider title, poster or description is reclassified as user-owned merely because a title was saved or reviewed. User-authored text is not parsed or deleted because it mentions a title. Pure season cache content is not a viewing event or episode-completion record.

## Freshness and schema

The operational maximum is **150 elapsed days**, safely below six calendar months; refresh becomes eligible at **30 elapsed days**. These intervals are application choices, not quoted TMDB mandates. `MetadataPolicy` treats exactly `fetched + 150 days` as expired. Unknown, nonfinite or future retrieval timestamps are unusable. Clocks are injectable in the policy, store, session cache, detail/search models and actual provider adapter for deterministic boundary tests.

Successful TMDB response mapping stamps optional `metadataRetrievedAt` on Movie, TVShow, TVEpisode and season-detail values. The timestamp travels with each copied JSON payload, so changing a status/rating/favorite, writing a review, copying metadata, opening a title or failing a request cannot give an older copy a new lease. Legacy title/episode payloads without provenance are removed on maintenance, not assigned a migration-time lease. Existing actual season-list retrieval timestamps can bound season header validity; they never renew an undated episode payload.

Current persistence schema is **LibrarySchemaV2 (2.0.0)**: V1’s five frozen entity definitions are reused, plus `StoredMetadataState`. The new table uses UUID uniqueness with application-level `(MediaID, scope)` uniqueness (`title` or `season:<number>`), and stores last successful retrieval, attempt, sanitized failure category and retry eligibility. No provider response/error body or credential is stored there. V1→V2 is additive; migration and historical adoption remain unverified until the disk tests run. See [DATA_MIGRATIONS.md](DATA_MIGRATIONS.md).

## Expiration, refresh and offline rendering

Before the app root is presented, LibraryStore enables metadata maintenance and clears expired/unknown-age TMDB fields in the existing transaction/rollback path. It does not delete library rows, ratings, private reviews, diary events, watched flags or their timestamps/identities. Foregrounding and a cancellable 60-second active-app maintenance loop repeat local cleanup. A conservative 150-day limit provides a margin to the six-month legal ceiling; there is no claim of hard real-time deletion while iOS suspends the process.

Expired library metadata columns/JSON become nil; review/event cached titles become explicit identifier placeholders and their provider JSON becomes nil. Season cache bodies/coverage are removed when no longer valid. Progress records retain flags, stable IDs and structural association, with minimal placeholder JSON rather than invented episode numbers, descriptions or air dates. UI labels distinguish an episode reference from a real provider episode number. A metadata-unavailable title still exposes the existing personal rating/review/history actions offline. Profile totals continue to count personal records, not cache availability.

Session detail/search/configuration caches also enforce the lease. Active views discard expired presentation data, Search reports expiry without automatically fetching every saved title, and a new title response does not renew old cast/configuration data. Refresh is user-context-driven on opening eligible detail/season screens or explicit retry; startup/local filtering/cleanup do not make metadata requests. Reopening fresh details reuses a valid snapshot rather than repeatedly retrieving the title. Missing extras are attempted separately; errors do not continuously loop.

Successful refresh replaces matching cached snapshots on existing library/review/event rows without changing personal dates/status/rating/text or creating a personal library record. A failure preserves the original successful timestamp; once expired, the failed request cannot justify stale offline display. Automatic attempts back off 15 minutes. Retry-After seconds or HTTP dates are respected with at least that floor; explicit retry may override ordinary offline backoff but not rate-limit delay. Credential changes clear failure backoff, invalidate older service epochs, and check authorization before/after requests so late old responses do not repopulate cleared content.

Artwork downloads now use an ephemeral, cookie/cache-disabled transport with bounded image sizes, a 2 MB per-image cap and a 40-entry memory cache. Library/Home use memory-cache-only thumbnails and do not fetch on local filter changes. No new app-managed disk artwork cache is written. Legacy URLCache responses are cleared at startup and on explicit credential/cache removal. Images can disappear on eviction/relaunch even while textual metadata is fresh; offline artwork is never promised.

## Safety backups and recovery archives

Raw pre-open SQLite snapshots also contain provider metadata. After a successful app open, recognized snapshots in StoreSafetyBackups are migrated/read locally and converted to **verified PersonalData.json recovery archives**. These contain personal fields/UUIDs/associations/flags and stable references, excluding provider titles, descriptions, dates, artwork and JSON snapshots. Only UUID/series/season anchors needed by personal episode flags are retained, with blank metadata on recovery. Invalid legacy floating values have an explicit reversible encoding. Bytes are atomically written, re-read and decoded, with duplicate-UUID rejection, before raw SQLite snapshot/journal files are removed. Conflicts remain a recovery-review gate rather than being silently upserted. The live user store is never deleted by this conversion.

Archives can be recovered through an internal explicit primitive into an **empty** destination, with the caller controlling save/rollback and owner authorization; there is no automatic restore/import or new export UI. The source migration backup still remains raw if the app cannot safely open/migrate it. Unknown/corrupt/incomplete raw archives are **not deleted or mislabeled compliant**: they stay recoverable, produce a visible warning, and block production provider activation until reviewed. Old managed backups are not silently treated as permanent metadata archives. Existing forced-failure migration tests still verify source/backup safety before any successful-open conversion.

## Outstanding owner/legal and operational gates

- Confirm the actual account, distribution/noncommercial classification, commercial agreement if needed, third-party artwork/data rights, approved branding use and current privacy disclosures. An API token or this document does not grant those rights. No live API request was made during this pass.
- Confirm identifier/season-anchor retention for personal records and the adequacy of foreground/lazy expiry with the provider. iOS cannot execute cleanup while a device is powered off or indefinitely suspended; a device unused for over six months can physically retain old bytes until next launch. There is **no dormant-device exception claimed**. If literal physical retention cannot be authorized, adopt a stricter memory-only provider-storage architecture before distribution.
- Review/recover unknown or unreadable safety archives without destroying personal records; provider activation remains blocked while those archives are unresolved. Owner-created copies, OS/device backups and filesystem/free-page forensic remnants are outside the app’s verified purge guarantees. No secure-erasure or blanket compliance claim is made.
- If a license ends, cease use/distribution as required, remove device **and** private Debug-scheme credentials, and clear provider content; credential removal clears current TMDB metadata without deleting personal records. Review bundled branding and retained unknown archives with TMDB. Do not mistake 401/403 alone for proof of permanent license termination or invent a license extension.
- Execute V1→V2/historical migration, maintenance, recovery-archive, background/offline and attribution tests on Apple frameworks before closing the release gate. No Xcode/device checks were performed in this pass as requested. The release remains **NOT READY — BLOCKERS REMAIN**.

## Tests and actual evidence

Added **16 MetadataLifecycleTests**, **3 MetadataArchiveTests**, one provider receipt-mapping test and one attribution/policy UI test: **21 new methods; 239 repository methods (199 unit, 40 UI)**. Cases cover fresh/approaching/exact expiry, unknown/future clocks, independent leases, personal-field preservation, successful mocked refresh/reuse, offline failure without renewal, rate-limit/date backoff, disk state reopen, episode flags, explicit clear, session/image expiry, credential epoch/archive activation gates, metadata-free archive round-trip, known-backup conversion, unknown-backup preservation and attribution presence. No real credentials/network are required by tests.

All XCTest methods remain **UNRUN** here. Passed static checks: Swift grammar for 111 files, project membership/references, resources, unchanged V1 stored-field comparison, document links and whitespace. Grammar parsing does not type-check Swift, expand @Model or prove retention/migration/recovery behavior. No Xcode build, simulator/device matrix, signing check, TestFlight upload or GitHub Xcode CI was performed.
