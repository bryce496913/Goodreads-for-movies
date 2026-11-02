# Offline saved-library reliability — pass 017

## Capability matrix and audit

The audit starts from main after PR 016. All availability below assumes the local store opens successfully. Provider content is usable only within its original retrieval lease; personal data has no metadata-cache lease. No real network, Xcode/device build or runtime UI checks were performed for this pass.

| Screen / action | Local availability | Network-dependent behavior |
| --- | --- | --- |
| Library and local organization | Saved identities, statuses, favorites, ratings and unexpired title/year/thumbnail reference; local filters/sorts/search | None. Library thumbnails only read the bounded memory cache. |
| Movie / TV Detail | Freshest valid local snapshot from Library, diary, reviews or saved TV seasons; available synopsis/genres/release/runtime/counts/artwork references; identifier placeholder when missing/expired | Opening fresh saved metadata needs neither credentials nor HTTP. Opening metadata eligible for refresh may attempt a request, with the valid local snapshot retained on failure. Explicit Refresh/Retry requires a configured service. |
| Detail cast | Previously loaded cast in the bounded session detail cache, within that snapshot lease | New credits retrieval is optional, not required to open fresh saved metadata. Cast is not persisted to a new SwiftData entity. After relaunch it can be unavailable until explicit refresh. |
| Seasons / episode lists | Existing catalog and episode bodies within their leases, including partial listings; persistent stable IDs, watched flags/dates and season anchors remain after expiry | Fresh saved listings open before credential/backoff checks. Missing/eligible lists need an authorized request to obtain new provider information; failure terminates loading and retains flags. |
| Episode edits | Individual watched/unwatched edits and eligible batch actions are local | No network. Expired episodes expose identifier placeholders and unknown air dates. Explicit individual edits remain possible; batch watched still excludes future/unknown air dates. |
| Ratings, reviews and diary | Read/edit/delete through the existing local writer, including undated/dated repeat events and review associations | No metadata request is a prerequisite. Removing a Library entry still intentionally removes its rating/status/favorite while retaining reviews/diary/progress, as before. |
| Viewing history | Persisted chronological events and private reviews, current ratings; valid saved title or identifier fallback | None. Retains watched-date versus recorded-date semantics. |
| Home / Profile | Local Sendable dashboard aggregation of ratings, reviews, diary and progress | None. No synthetic episode completion or duplicate movie count from rewatches. Provider titles/artwork can become placeholders without removing personal totals. |
| Search discovery | Existing in-process results within lease; no persistent search catalog or offline index of unsaved titles | New search and pagination require the provider. The separate Library search works offline. |
| Artwork in Search / Details | Valid bounded memory entries only; accessible placeholders on absence/failure/eviction/relaunch | Sized image retrieval is optional. Shared in-flight requests, explicit detail refresh or reopening can recover; no reachability watcher continuously retries images. |
| About / Settings | Bundled credits, local settings and Keychain credential configuration | External links require connectivity. Credential validation syntax is local; account authorization is a provider request. |

Descriptions/counts/season bodies appear only if previously fetched. Saving a summary does not invent complete details, cast, episode listings, years or counts. A missing provider snapshot is different from a missing personal record: placeholder detail screens retain rating/status/review/diary access for the exact MediaID. Movie and TV IDs sharing a number remain distinct.

## Local snapshot and refresh behavior

`LibraryStore.cachedMedia(for:)` is the shared local lookup for navigation and detail hydration. It chooses the newest usable exact-ID snapshot across Library, events, reviews and saved season show snapshots; ties retain the established source priority. Review-only, diary-only and season-only histories remain navigable without recreating a Library row. Opening fresh retained TMDB data returns before checking credentials, fetching credits or fetching image configuration. Fresh partial episode listings likewise do not require complete coverage or a token.

UI messages distinguish saved content, content due for refresh, known-expired content, and no usable saved content. Actual retrieval dates are shown when known. A network failure is reported alongside the local snapshot rather than labeling a placeholder “previously loaded details.” Recent-failure deferral is distinct from provider rate limiting; reopening a screen during backoff does not record another failure or move the deadline. Buttons requiring a metadata service are hidden when no usable service is configured. Missing season screens now have a loading indicator and an explicit retry when configured, rather than an unreachable retry action.

Refresh remains **context-driven**: reopen an eligible detail/season screen or explicitly retry after connectivity recovers. There is no global bulk reconnection fetch, continuous failure loop or new connectivity observer. HTTP retry/cooldown limits from [pass 015](TMDB_NETWORKING.md) remain. Existing generation, cancellation and credential-epoch checks protect result publication. Automatic refresh waits through persisted failure backoff; explicit retry overrides ordinary failure backoff, while rate limiting remains respected. Fresh local content can still open during a backoff.

Successful refresh only updates replaceable metadata on matching existing records. It never writes user ratings, review text/dates, diary identities/dates, favorite/status flags or episode watched flags. The writer rejects older known retrieval timestamps for title/season replacements and preserves a newer local snapshot when a rating/status edit originates from an older screen. A matching existing poster URL survives an optional artwork/configuration failure; a changed poster reference does not reuse the old URL. All writes retain the single main-actor transaction/audit/explicit-save/rollback path. There is no schema change or new writer.

Provider receipt time is an application retrieval fact, not a remote content version or server revision. Equal receipt timestamps do not establish an ordering between unrelated responses. Current per-model generation/credential checks and independent personal fields remain the primary protection against UI/request races; no unsupported remote version guarantee is claimed.

## Retention handling

The [existing metadata policy](METADATA_POLICY.md) remains unchanged: refresh eligibility at 30 elapsed days, a conservative 150-day retention maximum below the terms' six-month ceiling, and no lease renewal from personal edits, reads, failures or migration. Unknown/future/nonfinite receipt dates are unusable. Expiry strips provider fields/bodies but preserves personal records, UUIDs, exact media IDs and episode associations.

Before stripping a payload with a known original receipt, cleanup now remembers that **original** receipt fact in the existing V2 metadata-state table. It does not set a new success time, attempt time or retry deadline. This allows a later offline opening/relaunch to report “expired” after the body is gone. Unknown historical provenance remains “unavailable,” not a fabricated expiry date. Explicit clearing does not harvest new receipt facts. Recovery archives remain personal-only and do not restore provider bodies.

The foreground maintenance loop, startup purge, unresolved safety-archive activation gate and dormant-device/backup limitations from pass 014 still apply. No destructive reset, personal-record deletion or permanent provider archive was added.

## Artwork cache design and limits

`AGENTS.md` explicitly says **“Do not restore permanent provider snapshots or disk artwork caching.”** This pass follows that project constraint. The reviewed provider terms set a caching ceiling; they do not make artwork a permanent offline entitlement or approve every app's distribution/content rights. No new app-managed disk artwork cache is introduced, and ephemeral URLSession/URLCache is not presented as guaranteed offline storage. Legal/distribution gates remain in [METADATA_POLICY.md](METADATA_POLICY.md).

The existing memory cache now uses:

- Exact HTTPS sized TMDB URL keys, with a fixed `/t/p/<size>/<filename>` shape and allowed sizes w185/w300/w342/w500/w780. Original/full-resolution paths, query credentials, traversal, other hosts and redirects are rejected.
- Maximum 40 entries and **40 MB estimated cost** (encoded bytes plus width × height × 4). Entry data is capped at 2 MB; decoded dimensions are capped at 2,048 per axis. LRU eviction and byte-budget cleanup release owned entries. Estimated cost is not a measured process-RSS guarantee.
- Original image retrieval timestamps and the same retention predicate; reads do not renew expiry. Cache clear changes a generation so late responses cannot repopulate a cleared cache or publish into a waiting consumer.
- One shared request per sized URL, a maximum of 20 concurrent distinct flights, independently cancelable consumers and cancellation of the request when its last waiter leaves. Credential/archive authorization is checked before retrieval and publication. No credential is put in an artwork URL/header or logged.
- Existing ephemeral, cookie/cache-disabled transport with bounded request/resource timeouts; no image retry loop. A failed/missing/oversized image terminates in a placeholder. Explicit detail refresh recreates artwork tasks even when the URL is unchanged.

Limits apply to retained entries and validated responses. The existing transport buffers a response before the 2 MB validation; it is not a streaming byte-limit transport. UIImage decoding/cost accounting still occurs on the main actor and should be profiled locally if artwork decoding becomes a bottleneck. Memory images may disappear on eviction, explicit clear, process termination or memory loss; there is **no offline poster/backdrop guarantee across relaunch**. Fresh saved text and personal records do not depend on image availability.

## Tests and evidence

Added **12 OfflineReliabilityTests and 7 OfflineArtworkTests**. Tests use isolated in-memory or temporary disk-backed stores, injected service/transport failures, injected clocks and continuation gates; no real connectivity, credentials, production seed data or fixed network sleeps are required. Coverage includes:

- Saved movie/TV hydration without any service calls; fresh partial season access without credentials.
- Disk-container reopening with offline rating/review/diary/progress edits, cached text and local dashboard statistics.
- Offline failure, unchanged backoff deadline on reopening, explicit reconnection recovery and preservation of local edits.
- Exact expiry, original receipt preservation, identifier-only access, review-/season-only navigation, and editing retained episode references.
- Older title/season response protection and personal edits from stale screens.
- LRU/count/byte eviction, expiry, empty new cache after relaunch, missing/invalid/oversized artwork, forbidden original URLs, shared download/independent cancellation, cleared-cache late-response rejection and explicit image retry.

Static inspection found the older PNG fixture had an invalid IDAT CRC. It was replaced in the existing lifecycle test and new artwork tests with a deterministic 1×1 RGBA PNG whose chunk checksums validate. This validates fixture bytes, not UIKit execution.

**All XCTest remains UNRUN** on this Linux worker without Swift/Apple frameworks. Repository inventory is **304 methods: 264 unit-target methods (including the existing 15 benchmarks) and 40 UI methods**. Passed here: project/reference/source membership across three targets; grammar parsing for 122 Swift files (not compilation, macro expansion or type checking); resource metadata/privacy parsing; PNG fixture CRC validation; documentation links; whitespace checks. No Xcode compilation, simulator, signing or device-build checks were performed. No GitHub Xcode CI added.

Locally, run OfflineReliabilityTests and OfflineArtworkTests plus the existing MetadataLifecycleTests, MediaDetailTests, TVProgressTests, persistence/disk-integrity suites and UI regressions with the shared scheme. Then manually validate cold launch in airplane mode, Library → movie/TV → reviews/diary → cached season, edit personal data, terminate/relaunch, and reconnect/retry an eligible refresh. Verify missing images use placeholders and fresh/expired/unknown metadata messages are accurate. Disk-container reopening is a deterministic persistence regression, not evidence of an actual iOS process-termination/device run. Local runtime execution and screenshots remain outstanding.
