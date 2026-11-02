# TMDB authentication and request reliability — pass 015

## Official authentication review — 2026-11-02

HTTP 200 was returned by the official [application authentication](https://developer.themoviedb.org/docs/authentication-application), [rate-limit](https://developer.themoviedb.org/docs/rate-limiting), and [error reference](https://developer.themoviedb.org/docs/errors) pages. The application-auth page supports v3 `api_key` query authentication or the **API Read Access Token** as `Authorization: Bearer …`; Bearer is the documented default and works across v3/v4. This client uses HTTPS v3 metadata GETs and the Bearer header only. It does not add query-string credentials or user authentication/session endpoints.

The rate-limit page says the original 40-per-10-second limit was retired, describes changeable upper limits and requires respecting 429. The app does not treat an approximate allowance as a guaranteed quota. Error documentation distinguishes 401 authentication failure from 403 forbidden outcomes and 404 missing resources; those now have separate typed client errors. Backend status messages/bodies are not shown to users.

## Approved development configuration and security limits

Use an authorized personal/development token under the applicable TMDB account/usage terms. Save the **raw token without a Bearer prefix** in Profile → Settings for an installed build. The device Keychain uses non-synchronizing WhenUnlockedThisDeviceOnly storage. In Debug only, an optional token in a **private, unshared Run scheme** overrides that device setting. Release ignores the development environment override. Saving validates syntax, not account authorization; a provider 401 remains a distinct authentication failure.

`Configuration/.env.example` has only a placeholder; the app does not load dotenv files automatically. `.env`, `.env.*`, `xcuserdata/` and `Config/Local.xcconfig` are ignored. Never put a real token in source, shared schemes, Info.plist, xcconfig/build settings, resources, test fixtures, logs, screenshots or PR bodies. Unit fixtures contain explicitly nonsecret markers. Missing/placeholder input, invalid input format, unavailable credential storage and provider rejection are separate user-facing states; factories preserve those errors rather than converting every failure into “missing token.”

Configuration descriptions, debug descriptions and reflection mirrors redact the token. API URLs contain metadata/search parameters only; Authorization is a header. The client has no request/header/body logging, returns sanitized typed errors and normalizes Retry-After to numeric seconds before exposing it as error data. Raw URLSession errors/URLs and raw backend bodies are not propagated to UI. Redirects are rejected, TLS trust is not relaxed, cookies and response caches are disabled, and no analytics/proxy service is introduced.

**A token injected into an iOS bundle is not a secret.** This repository does not bundle one. Keychain protects storage on the device but does not turn a client-held credential into an unrecoverable production secret: the device user, an instrumented/compromised process or a malicious distributed client can extract/use it. The present bring-your-own-authorized-token configuration is for controlled development/internal testing. Broad distribution still needs a provider-approved credential/deployment and abuse-control decision. No unapproved proxy, token broker or commercial license is created by this pass. See [metadata policy](METADATA_POLICY.md) for separate content rights/retention gates.

## Error contract

| Condition | Typed outcome | Automatic retry |
| --- | --- | --- |
| Missing/placeholder, invalid token format, inaccessible Keychain | missingCredential / invalidCredentialFormat / credentialUnavailable | No HTTP request |
| 200/other usable 2xx JSON | Validate payload and typed identity, then map optional fields | No retry needed |
| 401 / 403 / 404 | unauthorized / forbidden / notFound | Never |
| 429 | rateLimited with sanitized Retry-After seconds if valid | Only within the small wait/attempt budget; otherwise return and enforce cooldown |
| 500, 502, 503, 504 | server(status) | Bounded transient retry |
| Other 5xx, including 501 | server(status) | Never automatically |
| Other HTTP, including rejected redirects | http(status) | Never automatically |
| Timeout / interrupted connection / failed connection / DNS resolution | timedOut / connectionLost / connectionFailed / dnsFailure | Bounded transient retry |
| Explicitly offline/data disallowed | offline | No; user can retry after connection recovery |
| TLS/certificate failure | secureTransport | Never; no insecure fallback |
| Invalid/non-HTTP response, empty 2xx body, invalid JSON/payload/ID/page | invalidResponse / emptyResponse / invalidPayload | Never |
| Task or transport cancellation | CancellationError | Stop; never reinterpret as offline/retry |

Malformed or missing required identities fail before persisted metadata is updated. Nullable dates/posters/runtime/counts remain optional; absent series/episode counts are not presented as verified zero. Empty optional synopsis/cast/genres keep established fallback rendering. Provider/source namespace and media kind remain part of identity. Existing exact-ID, duplicate-episode and strict date checks remain in place.

## Bounded retries and cooldown

The existing `TMDBMetadataService` actor owns one retry loop around the existing injected `MetadataTransport`; there is no second client or retrying transport wrapper. Ordinary idempotent JSON GETs use **at most two retries / three transport attempts**. Backoff starts at 0.5 seconds then 1 second, with **maximum two seconds per wait and three seconds cumulative wait**. The original request is reused. Policy, clock and cancellable wait are injectable; tests advance a clock or wait on explicit synchronization rather than sleeping to guess completion.

Retry-After accepts integer delta seconds or an HTTP date. A valid server-directed wait is never shortened to fit the automatic budget: if it exceeds the budget, the typed failure is returned immediately and the shared actor refuses new requests until the full deadline. Missing/invalid 429 headers use a one-second service cooldown and bounded backoff. Valid Retry-After on other HTTP failures is also respected, even if the failure itself is nonretryable. Raw/malformed header text is never copied into a typed rate-limit error. Expired cooldowns are cleared.

The cooldown is shared across Search/detail/season calls using that actor, not just across repetitions of one query. A late 429 from an obsolete but noncooperative transport still establishes its service cooldown, while that caller receives cancellation and cannot replace results. In-flight requests already sent before a throttle cannot be recalled retroactively. This is not an account-wide quota system: explicit service recreation/credential change resets ephemeral actor state. Persisted detail/season retry eligibility from pass 014 remains a separate, more conservative 15-minute automatic refresh floor; explicit retry can bypass ordinary refresh backoff, but not a client/provider cooldown.

Cancellation is checked before authorization/sending, after transport and before result publication; every retry rechecks the credential epoch/archive gate. `Task.sleep` is interruptible. Shared image-configuration flights keep the existing independent-consumer semantics and make **one transport attempt per explicit flight**, with no automatic retry loop; canceling one consumer does not cancel another consumer’s flight and may wait for bounded request completion. Artwork also keeps its single-attempt ephemeral transport and placeholder behavior.

The existing URLSession request/resource timeouts remain 30/60 seconds. Retry count and added wait are bounded, but there is no new operation-wide timeout racing a still-running transport. Repeated slow attempts can therefore take the sum of their individual timeouts; no measured end-to-end latency claim is made. User/search cancellation interrupts retry waits and cancels cooperative URLSession requests.

## Search concurrency and mapping

The 300 ms Swift Concurrency debounce, normalized-empty-query guard, request cancellation and query/filter generation checks remain. Pagination sets its in-flight flag synchronously, never appends from an old query/filter generation, deduplicates exact typed IDs, and validates page/totals before appending or advancing. Clearing or changing a query cancels obsolete work. Retry loops do not own UI state or append data; the same generation checks still control publication.

Invalid JSON, wrong IDs/pages, duplicate episode IDs and inconsistent required fields cannot reach metadata persistence. A failed refresh does not renew its cache lease or erase ratings/reviews/history. New regression coverage checks a malformed refresh leaves the prior snapshot/private data intact and a later successful explicit request recovers.

## Tests and execution evidence

Added **15 NetworkingHardeningTests and 3 SearchModelTests**. Existing single-attempt mapping tests explicitly inject `.none` while new tests exercise the production retry policy. Coverage includes header-only auth and redaction, all major HTTP categories, missing fields, timeout/DNS/connectivity/TLS, retry limits/budgets, delta/date Retry-After, cooldown across queries, retry-wait cancellation, authorization changes, canceled late 429, malformed/empty responses, persistence-safe failure/recovery, preserved configuration errors, filter-change pagination races and wrong-page rejection.

Repository inventory is **257 methods (217 unit, 40 UI)**. **All XCTest remains UNRUN on this Linux worker without Swift/Apple frameworks.** Passed here: project/reference/three-target source membership checks, Swift grammar parsing for **113 files** (not type checking), resource metadata, documentation links, bounded credential-pattern inspection and whitespace. No Xcode compilation, simulator, signing or device-build validation was performed. No GitHub Xcode CI was added.

## Live smoke checks — not executed

The runtime reports no configured secrets/credential bindings, and a presence-only check found no TMDB_READ_ACCESS_TOKEN. No token values, secret files, environment dump or Keychain contents were inspected. Public documentation access does not establish authenticated API integration. Do not describe mock fixtures as live verification.

| Narrow check | Endpoint | This pass |
| --- | --- | --- |
| Movie search | GET /3/search/movie | NOT RUN — no authorized credential |
| TV search | GET /3/search/tv | NOT RUN — no authorized credential |
| Movie details from returned ID | GET /3/movie/<id> | NOT RUN — no authorized credential |
| TV details from returned ID | GET /3/tv/<id> | NOT RUN — no authorized credential |
| Season/episode list from returned series | GET /3/tv/<id>/season/<number> | NOT RUN — no authorized credential |

After owner/provider approval and legitimate local configuration, run those specific calls through the configured app/client with one small search page and one selected title/season per media type. Record only endpoint, status, sanitized shape/ID consistency and whether the operation succeeded. Do not capture Authorization headers, full request objects/URLs, private text or credential-bearing logs. Do not run bulk requests, bypass throttles, commit live response snapshots or change the unresolved licensing/retention gates merely because authentication succeeds. No credentials are requested in chat.
