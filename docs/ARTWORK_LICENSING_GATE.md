# Pass 030 — artwork rights gate (2026-11-16)

**Outcome: BLOCKED — permission for this app's persistent offline artwork cache is not established.** No disk cache is implemented or activated. This is not a determination that TMDB prohibits all caching; a retention ceiling alone does not settle the applicable account, distribution or underlying image rights.

Official sources fetched successfully (HTTP 200) on the review date:

- https://www.themoviedb.org/api-terms-of-use
- https://developer.themoviedb.org/docs/faq

Terms §1.A includes visual content in TMDB Content and grants a conditional license. §1.C prohibits caching information from TMDB/APIs longer than six months. This confirms a ceiling, not an app-specific authorization to persist third-party artwork across launches. §1.D requires ceasing use and promptly deleting/purging cached content when the license terminates. §2 requires a written commercial agreement for direct or indirect commercial/revenue-generating use. The FAQ describes attributed noncommercial use and states: “We do not claim ownership of any of the images or data in the API.” It describes DMCA removal, not a blanket transfer of underlying artwork rights to this app.

No applicable account acceptance record, distribution/commercial classification, written commercial authorization or third-party artwork authorization was supplied/found in the repository. The reviewed public pages do not settle app-managed cross-launch artwork retention and dormant-device deletion for this app. Additional provider/rightsholder confirmation is required to resolve that scope; this pass cannot assert whether one specific permission instrument would be sufficient in every case. No artificial caching exemption, dormant-device exception or legal/distribution certification is claimed.

| Question | Decision / unresolved scope |
| --- | --- |
| App-managed artwork download to disk | Not authorized by this pass; applicable permission scope remains unconfirmed. |
| Retention between launches / offline relaunch | Not established; memory-only fallback continues. |
| Cache duration | Preserve conservative 150 elapsed days, below the reviewed six-month ceiling; no lease renewal from access or personal edits. |
| Delete at metadata expiration | Existing metadata/artwork leases remain enforced; no expired offline artwork display. Exact physical dormant-device deletion is not established. |
| Commercial versus noncommercial | Public noncommercial access with attribution is conditional; commercial use requires a written agreement. Actual app classification remains an owner gate. |
| Third-party images | FAQ disclaims ownership; applicable underlying rights remain unresolved. |
| Authorization termination | Cease use and purge cached provider content per §1.D; existing credential/epoch invalidation remains. Manual artwork clear is not a substitute for full termination handling. |
| Written permission | Needed where commercial use or unresolved artwork/retention scope requires it; none was supplied. |

The conditional 100 MB disk target, atomic files, disk LRU/reconstruction, backup exclusion and disk-backed relaunch criteria are **blocked/not implemented**, rather than silently simulated with URLCache. Existing 40-entry / 40,000,000-byte estimated-cost memory bounds and 2 MB per-response validation remain the active policy. The 150-day metadata maximum and original retrieval receipts are unchanged.

## Implementation audit and compliant fallback

Reviewed AGENTS, README, metadata/offline policies, ProviderArtworkLoader, ProviderArtworkCache/EphemeralAsyncImage, sized MetadataImageResolver, TMDB image-configuration retrieval, URLSessionMetadataTransport, LibraryCachedPoster, detail artwork, active maintenance, startup legacy URLCache cleanup, credential epoch handling and LibraryStore provider clearing. Existing behavior was ephemeral transport (no cookies/URLCache/redirects), bounded memory LRU, URL single-flight, independent consumer cancellation, last-waiter transport cancellation and generation/epoch publication guards. Search/detail can download optional sized artwork; local Library/Home/diary use cache-only thumbnails. No disk-managed artwork existed.

Changes retain that architecture:

- Canonical keys normalize only validated sized image.tmdb.org paths. Encoded filename aliases share entries/flights; variant sizes remain separate, and unsafe/original/query-bearing URLs remain rejected.
- Manual clear cancels managed flights and releases consumers immediately, then ignores late responses. A new consumer cannot join a stale generation/credential flight. It performs no filesystem operation and does not purge textual metadata or user records.
- Observable generation/revision removes retained visible images after clear/expiry and allows cache-only rows to reuse session images without new HTTP. Existing placeholders replace missing/cleared artwork; no fabricated artwork is bundled or downloaded.
- Settings shows approximate **memory** cost, a confirmed **Clear Temporary Artwork** action, truthful relaunch limitations and completion feedback. This synchronous memory-only clear has no filesystem-failure path; transport failures continue through existing image placeholders, not a false disk-success message.
- Credential provider removal invokes the same cancellation primitive after its existing metadata purge transaction. Personal mutations/purge logic and metadata receipt policy are unchanged.

The cache retains the successful image download receipt and does not update it on read, normalization, clear or personal edits. New actual successful downloads have their own receipt. No persistent provenance/file manifest is invented under a blocked gate. Unknown/nonfinite receipts fail closed, future receipts are not displayed and exactly-expired entries are removed. Reopening constructs an empty memory cache; no fake relaunch persistence is claimed.

## Executed evidence and remaining platform checks

Executed: two unauthenticated official-document GETs (HTTP 200); project/reference/source membership checks for all three targets; Swift grammar parsing for 135 source/test files; asset JSON and semantic contrast checks; diff whitespace, documentation-link and unchanged metadata-policy/domain/schema checks. These are not Swift compilation/type checking, image decoding, SwiftData or simulator tests. No live TMDB API/image smoke request or credentials were used.

All **384 XCTest methods are UNRUN**: Linux has no Swift compiler, Xcode, UIKit/SwiftData SDKs or simulator. Seven new methods cover the memory-only fallback: canonical key variants/receipts, immediate manual clear with noncooperative late response/retry, credential epoch rejection, exact-expiry/no-renewal/restart fallback, personal record/metadata preservation, changed-reference failure, and Settings confirmation. Existing LRU/count/byte bounds, multiple consumers, cancellation, invalid/oversized images and offline retry tests remain. No disk-backed artwork test ran and none is claimed.

Local review: run OfflineArtworkTests, OfflineReliabilityTests, MetadataLifecycleTests and BetaPreparationUITests plus the existing persistence/UI suites. With deterministic transports, clear while loading, finish an old response, retry with current authorization, change image references, expire the clock and verify placeholders and intact personal data. In the simulator, verify visible Search/detail/Library/Home images disappear after Settings clear, no clear-triggered automatic redownload occurs, new session images can be reused by cache-only rows, confirmation works at large text, and force-quit/offline relaunch shows placeholders alongside intact text/ratings/reviews/diary/progress. Record actual local results before accepting runtime behavior.

Remaining blockers: app/account classification and third-party image rights; permission for proposed durable/offline storage and deletion scope; actual Apple runtime/decoding/cancellation/observation tests; buffered transport peak memory and main-actor decode profiling. No claim of legal certification, secure erasure, complete cache-rights coverage or distribution readiness. Do not begin pass 031 automatically.
