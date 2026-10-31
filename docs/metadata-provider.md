# Metadata provider evaluation and integration

## Decision and verification status — 2026-10-31

**TMDB is the provisional initial provider for development, not an approved production data license.** The implementation is an opt-in development service connected to Search after a nonempty user query; app startup remains network-free. No provider data, logo assets, or credentials are bundled. Do not ship provider-backed screens until current terms, attribution, commercial rights, and deployment model are confirmed.

Official-document retrieval was attempted on the date above. The environment proxy rejected `https://developer.themoviedb.org/docs/getting-started` with HTTP 403 (`CONNECT tunnel failed`). No TMDB environment variable or credential binding was present. Accordingly, **current terms have not been verified, no authorized live request was run, and real movie/TV retrieval is not claimed as successful**. Required domain additions were saved for environment settings, preserving `api.github.com`: `developer.themoviedb.org`, `www.themoviedb.org`, `api.themoviedb.org`, and `image.tmdb.org`. Saving a draft does not apply network access or establish license approval.

The table separates implementation assumptions from findings that still need verification against official sources. These links are review targets, not a claim that blocked pages were read.

| Area | Provisional integration assumption / required confirmation | Official source |
| --- | --- | --- |
| Access conditions | Obtain an authorized developer API application and accept the current terms. Confirm approval requirements and intended application classification before live use. | [Getting started](https://developer.themoviedb.org/docs/getting-started), [API terms](https://www.themoviedb.org/api-terms-of-use) |
| Authentication | Implement API v3 HTTPS with an API Read Access Token in `Authorization: Bearer …`. Query-string API keys are not used. Verify the issued credential supports these endpoints. No user authentication is needed for public metadata. | [Application authentication](https://developer.themoviedb.org/docs/authentication-application) |
| Attribution / branding | Plan visible TMDB attribution in About/Credits using their approved logo and the prescribed notice, historically “This product uses the TMDB API but is not endorsed or certified by TMDB.” Recheck exact current wording/logo/link/placement rules before displaying any TMDB content. Search now includes a TMDB text link and the notice, but approved logo assets and current placement requirements remain unverified release prerequisites. | [FAQ](https://developer.themoviedb.org/docs/faq), [Logos and attribution](https://www.themoviedb.org/about/logos-attribution) |
| Noncommercial / commercial | Do not assume unrestricted or universally free commercial use. Historically, developer access for noncommercial use required attribution; commercial use required a separate arrangement. Confirm current definitions and obtain any required written commercial license before monetization/distribution. | [API overview](https://www.themoviedb.org/documentation/api), [API terms](https://www.themoviedb.org/api-terms-of-use), [FAQ](https://developer.themoviedb.org/docs/faq) |
| Rate limits | Do not hardcode a guaranteed request allowance. Treat HTTP 429 as a rate limit, surface Retry-After when supplied, and require a later explicit call. No automatic retry loops or authentication retries. | [Rate limiting](https://developer.themoviedb.org/docs/rate-limiting) |
| Images / sizing | Retrieve secure base URL and available sizes from `/configuration`. Resolve poster thumbnails at `w185` by default and backdrops at `w300`, with explicit bounded larger sizes. Unsupported sizes and missing/unsafe references return nil, never fall back to `original`. | [Image basics](https://developer.themoviedb.org/docs/image-basics), [Configuration](https://developer.themoviedb.org/reference/configuration-details) |
| Caching / retention | Current permissions, allowed retention, refresh and deletion rules are **not verified**. Do not assume permission for a persistent metadata/image cache or redistribution. This pass uses no custom image cache and no stored provider responses. Configuration is reused only in memory for the service instance; reassess even this policy against the approved terms before production. | [API terms](https://www.themoviedb.org/api-terms-of-use), [FAQ](https://developer.themoviedb.org/docs/faq) |
| Movie / TV support | Candidate v3 endpoints below are implemented from their established documented shapes. Actual current responses and authorized access still need live verification. | [Movie search](https://developer.themoviedb.org/reference/search-movie), [TV search](https://developer.themoviedb.org/reference/search-tv), [Multi-search](https://developer.themoviedb.org/reference/search-multi), [Movie details](https://developer.themoviedb.org/reference/movie-details), [TV details](https://developer.themoviedb.org/reference/tv-series-details) |
| Genre metadata | Separate movie and TV genre lists; keep provider payloads out of feature/domain interfaces. | [Movie genres](https://developer.themoviedb.org/reference/genre-movie-list), [TV genres](https://developer.themoviedb.org/reference/genre-tv-list) |

If the current terms prohibit the intended use, stop provider activation and document the restriction; do not scrape, proxy around restrictions, or describe developer access as a commercial license. The production architecture and licensing decision require separate approval.

## Credentials: local development only

`Configuration/.env.example` contains a placeholder, not a working token. `.env` files and Xcode `xcuserdata` are ignored. The app does **not** automatically load dotenv files. No secrets belong in source, Info.plist, xcconfig build values, asset catalogs, tracked/shared schemes, logs, fixtures, or PR text.

1. Confirm current TMDB terms and obtain your own approved **API Read Access Token** through TMDB's developer settings. Do not paste it into chat.
2. In Xcode, duplicate the MovieTracker scheme for local use and **uncheck Shared before entering any credential**. Verify the scheme is in ignored `xcuserdata`, not tracked `xcshareddata`.
3. In that private scheme's Run → Arguments → Environment Variables, set `TMDB_READ_ACCESS_TOKEN`. Never commit the local scheme or the value. If you use a local `.env`, it remains ignored and must be passed to the process explicitly; it is not an app resource.
4. A developer caller can also create the service inside an async context:

```swift
let configuration = try TMDBConfiguration.localDevelopment()
let metadata: any MediaMetadataService = TMDBMetadataService(configuration: configuration)
let movies = try await metadata.searchMovies(query: "Arrival", page: 1)
let shows = try await metadata.searchTVShows(query: "Severance", page: 1)
let artwork = try await metadata.imageResolver()
let poster = artwork.posterURL(reference: movies.items.first?.posterReference)
```

No credential means `MetadataError.missingCredential` when explicitly constructing this configuration; normal app launch stays offline and credential-free. Tests inject a fake transport and nonworking test-only credential, never the process's real credential.

**Client credentials are extractable.** Even a token injected into a running development app can be inspected. Do not embed a supposedly secret production provider token in an iOS binary. Production requires a provider-approved deployment model; if credential confidentiality is required, design a backend/token-brokering arrangement with provider authorization, suitable scope/lifetimes, and abuse controls. Token brokering alone does not make a long-lived client token confidential or grant content rights. No backend is built here.

## API architecture and behavior

- `MediaMetadataService`: provider-independent search/detail/genre/image-resolution interfaces. `MetadataPage`, `MediaSearchResult`, and `MediaGenre` contain domain values, not raw DTOs.
- `TMDBMetadataService`: actor with fixed HTTPS API host, bearer headers, URLComponents query encoding, page validation, and mapping. Search calls it only for explicit user input; no requests run automatically on app startup.
- `MetadataTransport`: injected Sendable async transport. The URLSession implementation is ephemeral with caching disabled, finite timeouts, cancellation propagation, redirects refused (avoiding forwarding authorization), and no logging or automatic retries.
- `TMDBResponses`: Codable provider DTOs. Required malformed records reject the page with `invalidPayload`; people in multi-search are intentionally filtered. Unknown media types reject safely rather than being misidentified as movies.
- Domain identity remains `MediaID(kind:value:)`, not a TMDB integer or DTO. The boundary generates opaque, provider-qualified values such as `tmdb:123` to avoid future cross-provider collisions. The kind independently separates movie 123 from TV 123. Only the TMDB adapter interprets that value; future screens must treat it as opaque. Genre IDs use the same namespace.
- Missing descriptions become empty strings. Missing/invalid dates and artwork stay unavailable. Nonpositive runtime/season counts become nil; TV runtime is the first positive reported episode runtime. Backdrop and runtime fields are optional domain metadata, with no persistence migration or automatic save added.
- Search pages must be 1...500. Returned `totalPages` is capped at the reachable provider limit; `nextPage` stops there. Provider `totalResults` remains unmodified, including people excluded from multi-search display. A zero-results page is valid; an empty HTTP body is a distinct error.
- Structured errors distinguish validation, auth (401/403), rate limit (429 with optional raw Retry-After), server, other HTTP, offline, timeout, transport, invalid/empty responses, and invalid payloads. Error descriptions omit credentials, request bodies, and provider error text. Retry-After is advisory and is not automatically scheduled.
- Requests check task cancellation before sending and after transport/decoding/mapping, including transports that finish successfully after cancellation. No service method mutates feature/UI results. SearchModel now cancels old tasks **and** gates result assignment by query/filter generation; see [Search behavior](search-discovery.md).
- Configuration requests share an in-flight task and reuse the successful configuration in memory. A canceled configuration consumer cannot cancel another consumer's shared request; it checks cancellation before returning (it may wait for that shared request's bounded timeout). Failed configuration can be retried by an explicit later call, with generation checks protecting a newer request from older failed waiters. Search/detail calls are not globally coalesced: SearchModel debounces input and cancels superseded searches, rather than sharing cancellation ownership across independent consumers.
- The image resolver only accepts the configured HTTPS `image.tmdb.org` host, advertised bounded sizes, and single-file image references. It rejects absolute URLs, path traversal, queries, missing images and unsupported sizes. It performs no download or custom caching.

## Validation record and local checks

This Linux environment has no Swift compiler, Xcode, Apple SDK, or iOS simulator. **No Swift/XCTest execution, iOS build, or live-provider success is claimed.** Static Swift grammar parsing and project membership/reference checks are recorded in the PR. The existing Xcode test target includes credential-free mock cases for movie/TV/multi-search, typed identity, missing metadata, details/genres, malformed records/JSON, auth, rate limit, server/network errors, empty results/body, pagination, cancellation (including a late success), image paths/sizes and configuration reuse/retry. These tests still require local execution.

Run in your normal credential-free scheme on macOS:

```sh
xcodebuild test -project MovieTracker.xcodeproj -scheme MovieTracker \
  -destination 'platform=iOS Simulator,id=<SIMULATOR_UUID>' \
  -only-testing:MovieTrackerTests/MetadataServiceTests \
  CODE_SIGNING_ALLOWED=NO
```

Then run the full existing suite using README instructions. No GitHub Xcode CI is added. No live test runs as part of the unit suite.

Optional live verification is a **separate manual development check** after network permission, provider terms, and your local credential are approved. Use the private scheme to call movie/TV search and detail endpoints, both genre endpoints, and configuration/image resolution. Check empty/missing fields and pagination against actual payloads, then exercise offline and cancellation behavior. Record only endpoint names/statuses and sanitized observations—never headers, tokens or full request dumps. Review attribution before connecting any returned content to a screen. Current-provider verification and commercial/caching approval remain prerequisites, not completed acceptance criteria.
