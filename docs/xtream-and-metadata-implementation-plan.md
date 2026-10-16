# Xtream API And Metadata Implementation Plan

Created: 2026-10-15. Updated: 2026-10-15. Status: XM-01 through XM-03 implemented; later packages pending.
Audience: developers and coding agents implementing source-aware catalogs and richer movie/series details.

## 1. Purpose And Authority

Use this plan for explicit Xtream login, detecting Xtream capabilities from a playlist URL, provider identity, and extensible metadata enrichment. Implementation proceeds only for packages explicitly requested by the user; XM-01 through XM-03 are now complete.

Current source, tests, migrations, and configuration define implemented behavior. Follow [AGENTS.md](../AGENTS.md), [architecture boundaries](../test/architecture/architecture_rules_test.dart), [design rules](design-guidelines.md), and [decisions](decisions.md). Preserve paged browsing, constructor injection, existing playback adapters, Back/focus behavior, and playlist isolation.

This plan extends source and metadata behavior, not playback continuity, recommendations, EPG, or branding. Historical MVP exclusions in older product/handoff documents do not describe the requested future scope. Record approved behavioral decisions before implementing their gated steps; do not silently rewrite those documents.

### References And Evidence

- [Xtream Codes API Explained](https://www.maximusplayer.com/blog/xtream-codes-api-explained), reviewed 2026-10-15, describes the common login, catalog, and detail actions. It is a secondary compatibility guide, not a normative specification or guarantee for every panel.
- The user reports successful authenticated `player_api.php` and `get_live_streams` responses. Treat that as evidence for their provider only; this planning session did not contact it.
- Xtream-compatible panels vary in JSON types, supported actions, category filtering, redirects, and stream formats. Validate behavior against sanitized fixtures and an explicitly authorized provider smoke test.
- TMDB integration must verify current [developer documentation](https://developer.themoviedb.org/docs/getting-started), authentication, attribution, image configuration, rate limits, and usage terms before shipping. This plan does not claim those requirements have been verified.
- Never put real account values, provider responses containing credentials, or credential-bearing URLs in this document, fixtures, screenshots, or logs. Examples use `provider.example` and placeholders only.

## 2. Current Implementation

| Surface | Existing Behavior | Required Extension |
|---|---|---|
| [Source configuration](../lib/services/settings/settings_repository.dart) | `PlaylistSourceKind.url` and `.xtream`; explicit Xtream config has name/server/username/password, but `resolvedUrl` constructs `get.php?...&output=m3u8`. | Separate input method, catalog transport, detected API capability, and account state. Preserve original URL options. |
| [Playlist editor](../lib/features/settings/widgets/playlist_editor_dialog.dart) | URL/Xtream source selector and credential fields already exist. | Improve server parsing, add verification state, inferred source preview and explicit correction/URL-only option. |
| [Form validation](../lib/features/playlists/playlist_form_validation.dart) | Xtream server currently only checked for nonempty input. | Structured HTTP(S) authority/base-path validation and a defined scheme policy. |
| [Playlist controller](../lib/state/playlists_controller.dart) | Saves either source kind and imports through catalog load/refresh commands. | Coordinate source verification without coupling UI to HTTP or changing save/import semantics accidentally. |
| [Secret store](../lib/services/storage/secure_storage_service.dart) | `PlaylistSecretStore` supplies secure storage via platform composition. | Resolve credentials inside data services; expose only safe connection summaries to widgets. |
| [Import worker](../lib/services/catalog/catalog_import_worker.dart) | Streaming M3U pipeline with batching/backpressure, cancellation and hashes. | Keep this path usable; add API mapping/sync in stages without buffering a large catalog on the UI isolate. |
| [Classifier](../lib/services/catalog/catalog_classifier.dart) | URL path, extension, group/provider hints and episode-title inference. | Verified API kinds take precedence for positively mapped records. Never classify a bare numeric URL by ID alone. |
| [Read API](../lib/services/catalog/catalog_query_service.dart) | Bounded summaries; full item lookup only for selected content; series/seasons/episodes queries. | Selected-entity provider identity and metadata lookup without per-card requests. |
| [Catalog storage design](catalog-import-and-browsing-redesign.md) | Local item keys derive from stream URLs; series keys are derived from playlist/group/title. | Separate provider identifiers and metadata bindings; do not replace local identity. |
| [Details](../lib/features/details/details_screen.dart) | Selected item group/description and Play; series activation currently browses seasons. | Async richer movie details and a separately approved series overview transition. |

The presence of credentials or `PlaylistSourceKind.xtream` is not evidence that API authentication has succeeded. Conversely, a URL source can support Xtream metadata while continuing to import its original M3U.

## 3. Source And Capability Model

Proposed types below are design contracts, not existing APIs. Keep them small and typed; do not build a general plugin runtime or add state-management/DI/code-generation packages.

Represent these independent facts:

| Fact | Suggested Values | Reason |
|---|---|---|
| Input kind | URL, explicit Xtream credentials | Remembers what the user supplied and what editing should show. |
| Catalog mode | M3U, Xtream API | Determines import/query strategy, not metadata eligibility. |
| API verification | Unchecked, checking, verified, invalid credentials, unsupported, temporarily unavailable | A timeout is not proof the source is plain M3U. |
| Account state | Active, expired, disabled, banned, unknown | Successful API recognition and subscription availability are different facts. |
| Capabilities | Live catalog, VOD catalog, series catalog, VOD info, series info | Track independently; successful login does not guarantee every action. |
| Connection revision | Monotonic local revision | Invalidates account-scoped requests and cache bindings after edits without hashing secrets into keys. |

Persist only a whitelisted non-secret verification summary: playlist ID, safe endpoint description, selected transport, connection revision, capability results, timestamps and normalized account status. Credentials and the original credential-bearing URL remain in the secret store. Do not persist full authentication responses: `user_info` can echo both username and password.

## 4. Adding And Detecting A Source

### Explicit Xtream Login

1. Collect playlist name, server address including optional port/base path, username and password. Reuse the existing editor rather than create a second setup implementation.
2. Parse with `Uri`, allow HTTP/HTTPS only, reject embedded user-info, fragments, and unexpected query parameters in the server field. Preserve explicit scheme, port and configured base path. Support IPv6 using structured parsing.
3. For bare `server:port`, propose HTTPS in the form but require the user to confirm/edit the scheme before sending credentials. Do not silently attempt HTTPS and then downgrade to HTTP. Preserve explicitly entered HTTP with a clear insecure-transport warning.
4. Preserve case and password contents exactly; avoid the current password trimming behavior in source serialization/deserialization. Define whitespace handling for pasted usernames separately and test it. Encode query and path components through `Uri`, never string concatenation.
5. Offer a verification action and run verification before API import. Saving configuration remains separate from importing it unless an explicitly approved onboarding change says otherwise. Do not switch the active playlist during verification.
6. Store secrets securely and show only name/host/source status after saving. Retain entered fields after recoverable errors, disable duplicate submission, and provide cancellation.

### URL Detection

1. Parse the submitted playlist URL locally. A same-URL query with one nonempty `username` and one nonempty `password` creates an Xtream candidate, especially for `get.php` or `player_api.php`. Reject ambiguous duplicate credential parameters for inference.
2. Derive a candidate `player_api.php` beside a recognized endpoint, retaining its base path, scheme and port. Do not copy unrelated query values into API requests or discard the original `type`, `output`, category/token, or other playlist options.
3. Explain that the app will verify API support with the same credentials on the same origin as part of Add/Verify. For an unrecognized script path with credential parameters, require explicit confirmation of the candidate endpoint. Do not probe unrelated hosts or ports.
4. Request authentication without `action`. Only a structurally valid response with `user_info.auth` equal to accepted `1`/`"1"` confirms authentication. Normalize documented account fields defensively; missing/unrecognized values remain unknown. HTTP 200, HTML, or `server_info` alone is not sufficient.
5. On success, retain URL input provenance and original M3U transport initially, but enable verified Xtream capabilities. Do not force an immediate full reimport or rewrite stream URLs simply because API verification succeeded.
6. On unsupported API, malformed response, timeout, TLS error or denied authentication, distinguish the outcome and retain the URL-only path. A functioning M3U import must not be disabled by optional metadata verification failure. Negative results expire and can be retried manually.
7. Reverify on credential/server changes and explicit retry, not on every launch, card rebuild or focus event. Existing saved sources are probed only during an explicit refresh/verification flow, not by an unsolicited startup scan.

### Stream URL Candidates Are Not Playlist URLs

`/<username>/<password>/<id>` and `/live|movie|series/<username>/<password>/<id>.<extension>` can help map selected content only after a provider connection is verified. Do not crawl all imported stream hosts, infer credentials from arbitrary paths, or treat a direct stream as a playlist automatically.

An unresolved `xui-id="{XUI_ID}"`, empty `tvg-id`, thematic channel name or final numeric path segment does not establish a movie or series identity. A verified live-channel ID must never be sent as `vod_id` merely because the title resembles a film.

## 5. Xtream Client And Endpoint Routing

Introduce a data-layer `XtreamApiClient` with an injected HTTP transport and credential resolver. Widgets/controllers consume safe service interfaces, never client implementations or raw authenticated URIs. Wire implementations in [AppDependencies](../lib/app/app_dependencies.dart); keep platform decisions in `lib/platform/`.

| Operation | Common Action / Parameter | Use |
|---|---|---|
| Verify account | No action | Establish API recognition, authentication, safe account summary and advertised output formats. |
| Live categories/channels | `get_live_categories`, `get_live_streams`, optional `category_id` | Verified kind, channel ID, logo, EPG identity. |
| Movie categories/catalog | `get_vod_categories`, `get_vod_streams`, optional `category_id` | Movie provider IDs, available basic metadata and container extension. |
| Movie detail | `get_vod_info&vod_id=<id>` | Selected movie enrichment. |
| Series categories/catalog | `get_series_categories`, `get_series`, optional `category_id` | Provider series IDs and basic show information. |
| Series detail | `get_series_info&series_id=<id>` | Show metadata plus season/episode records where provided. |
| Guide | `get_short_epg`, XMLTV | Future capability only; not part of this milestone. |

These are common conventions, not an exhaustive guaranteed protocol. Never assume `offset`/`limit` pagination exists. Some category endpoints return complete arrays or ignore category filters. Stream/decode large arrays away from the UI isolate with bounded batches and an explicit response limit; stream large bodies to a temporary file if the chosen JSON parser cannot decode incrementally. Do not use unbounded `join`/`jsonDecode` on large catalog bodies in the UI isolate.

Initial defaults to validate: one concurrent request per provider account, 10-second connection timeout, 30-second detail deadline, 120-second catalog deadline, and 2 MiB auth / 10 MiB detail / 100 MiB per-category response limits. Enforce byte limits while receiving; return a typed failure when exceeded. Make catalog limits configurable after measurements. Respect cancellation, bounded retries, and `Retry-After` for 429/503; do not retry denied credentials or spin on unavailable actions.

Accept common number/string/null variations using explicit normalizers, not dynamic casts scattered through UI code. Normalize IDs as validated strings; distinguish live IDs, VOD IDs, series IDs and episode IDs even if values coincide. Treat unknown fields as ignorable and malformed identity fields as unmappable.

Security rules: redact query/path credentials and response echoes before logging; never log bodies. Do not disable certificate validation. Reject cross-origin credential-bearing redirects unless the user approves a new connection and it is separately verified. Never trust `server_info.url` or ports as authority to resend credentials to another origin. Resolve relative artwork cautiously and do not forward provider credentials/headers to artwork or external metadata hosts. Reject credential-bearing artwork URLs from UI/cache until a dedicated safe media-fetch mechanism exists.

## 6. Catalog Identity And Staged Adoption

### First Deliverable: API Metadata Beside M3U

Keep existing M3U import and playback URLs. Persist explicit provider bindings separately from catalog identity. For a selected `/movie/.../<id>.<ext>` item, use a candidate ID only within its verified connection and declared movie kind; verify via the corresponding endpoint before accepting metadata. Bare numeric paths need typed membership evidence from an API catalog, not a title guess.

M3U-derived series names are not provider series IDs. Fetch/cache `get_series` category-by-category to build candidate bindings. Accept an unambiguous provider mapping supported by stable IDs or verified episode membership; title-only matches are suggestions, never automatic authoritative links. Unmapped/ambiguous shows keep their existing local details and season browsing.

Store provider episode ID -> provider series ID, season and episode number when a selected `get_series_info` response supplies them. Do not issue `get_series_info` for every show during initial catalog import. Initial M3U metadata enrichment may therefore leave some series unmapped; report this honestly rather than fabricate IDs.

### Later Deliverable: API-Native Catalog Sync

This is an explicitly planned later implementation, not just a metadata optimization. For verified Xtream sources, support fetching live channels, VOD movies and series through separate API requests rather than requiring a complete `get.php` M3U download. Verify each catalog capability independently; authentication alone does not prove filtering or pagination support.

#### Category-Based Fetching And Local Batches

1. Fetch `get_live_categories`, `get_vod_categories` and `get_series_categories` for the supported catalog kinds.
2. Queue category-scoped requests: `get_live_streams&category_id=<id>`, `get_vod_streams&category_id=<id>` and `get_series&category_id=<id>`. Start with one request at a time per account; do not download all three complete catalogs concurrently.
3. Decode each response away from the UI isolate and feed bounded row batches through staging/backpressure. Network request size, decoder batch size and local UI page size are separate controls. A category response can still contain thousands of records.
4. Persist completed category scopes and the source revision in the sync session. On cancellation or interruption, retain committed cached scopes and discard incomplete staging. Resume only under the same connection revision; revalidate or restart an interrupted scope because the provider may have changed its contents.
5. Publish a category only after its complete response has been validated and reconciled. UI queries continue to page through `CatalogQueryService`, never through a full in-memory API response. Progress distinguishes completed categories, imported records and failed/pending scopes; do not report an incomplete source as fully synchronized.
6. Fetch movie details and a selected series' seasons/episodes on demand through `get_vod_info` and `get_series_info`, not once per catalog item during import. Keep unavailable details independent from catalog/playback availability.

Category filtering is not guaranteed server-side pagination. Do not invent `page`, `offset` or `limit` parameters; use them only for a separately verified provider extension. If filtering is ignored, categories are unavailable, or uncategorized records require an unfiltered request, use a bounded worker-based whole-kind fallback only under an explicit compatibility policy, or retain M3U mode. Record this reduced batching capability and avoid repeatedly downloading the same complete response for every category. Never use a potentially incomplete category list as proof that unseen items should be deleted.

Add an adapter that maps API categories/items into the current staged catalog pipeline and reads through `CatalogQueryService`. Verified endpoint kind supersedes heuristic classification. Maintain API series records independently from episodes: shows can appear before episode detail has been fetched, with unknown counts instead of false zeros. Populate episodes on demand for a selected show and browse locally in pages.

Before shipping lazy series, specify search coverage: initially global search can find imported show titles and already-fetched episodes, not every unseen episode. Do not promise exhaustive episode search or eagerly fetch every show to achieve it.

Do not mix metadata failure with catalog failure. Stage each authoritative category/type snapshot, record its coverage, and reconcile removals only after that scope completes successfully. A failed or unsupported category request must not delete cached items. Provider categories are not always disjoint; define deduplication by typed provider ID while preserving memberships/order deliberately. Full refresh and category refresh need separate completion evidence.

Existing local IDs, `(playlist_id, item_key)` user data and derived series identities must survive enrichment. Transport changes must not silently create a duplicate playlist or regenerate all user keys. Before enabling API-native mode on an existing source, implement an explicit identity bridge and tests for ID collisions, duplicate URLs, category moves, changed container extensions, credentials, redirects and provider host changes. If a safe bridge is unavailable, keep that source on M3U plus enrichment. Do not change the catalog hash algorithm as part of this feature.

Playback URL construction uses verified item type, provider ID, container extension and user-selected supported output. Preserve original working URLs in hybrid mode. Do not hardcode every stream to HLS, use an API series ID as an episode ID, or use TMDB data to construct playback URLs. Connection counts are advisory account data, not permission to open extra streams for probes.

## 7. Provider-Neutral Metadata Architecture

Keep content sources and metadata providers separate. Xtream can supply both; TMDB supplies descriptive metadata, not playlist credentials, playback entitlement, or playable catalog entries.

Proposed contracts:

| Contract | Responsibility |
|---|---|
| `MetadataSubject` | Local playlist/entity identity, entity type, connection revision, verified provider references, locale and optional title/year hints. No raw stream URL or credentials. |
| `MetadataProvider` | `supports(subject)` and cancellable `fetch(subject)` returning normalized fields or typed unavailable/ambiguous/error states. |
| `MetadataRepository` | Cache-first resolution, request deduplication, provider policy, stale fallback and provenance-preserving merge. |
| `ContentMetadata` | Optional title/plot/artwork/genres/release date/runtime/cast/director/rating/external IDs, plus field provenance, locale, fetch time and freshness. |
| Details controller | Selected-subject request lifecycle and loading/error state; ignore stale completions after navigation, playlist switch or connection edits. |

Use constructor-injected provider lists, not a global static registry. The first production provider is Xtream. A fake second provider must prove the repository/UI have no Xtream-specific dependency before TMDB networking is added.

### Merge And Matching Rules

1. Keep local catalog identity, provider availability, episode relationships and playback links authoritative. Metadata cannot add playable items or reclassify live content as VOD.
2. Default descriptive precedence: explicit user correction, verified Xtream fields, enabled external provider fields, then imported M3U fields. Empty strings/null/invalid placeholders do not overwrite useful values. Missing fields can be filled individually; never discard provenance through a whole-object replacement.
3. Retain original catalog titles for browsing/playback identity. An enriched display title is optional and separately labeled in the view model, not a destructive rename.
4. Store rating source and scale. Do not average incompatible ratings or invent ratings/year/runtime from arbitrary provider title strings. Normalize runtime units only when the field contract is known.
5. TMDB lookup prefers a validated TMDB ID supplied by provider metadata, with media type verified. Next use supported external-ID lookup, then conservative title/year/language candidates. Numeric Xtream IDs are not TMDB IDs.
6. For ambiguous title search, ask the user to choose or leave enrichment unavailable. Persist correction/rejection so repeated visits do not rematch incorrectly. Never attach a confidently styled poster merely because it was the first search result.
7. Distinguish movie, TV show, season and episode subjects. Series overview metadata cannot replace episode-specific fields; remakes, regional variants and specials require explicit disambiguation.

### TMDB Extension

Ship behind explicit opt-in with provider priority/language controls and a clear data-sharing explanation. Send only required IDs/title/year/locale to TMDB, never Xtream credentials, stream URLs, account status, playlist names or provider host. Keep TMDB tokens separate from playlist secrets, reuse the secure-store abstraction with provider-scoped keys, and never embed a privileged application secret in a distributed binary.

Choose user-supplied credentials or an approved deployment model before implementation. Implement required attribution/branding, image configuration, caching restrictions, locale fallback and rate-limit behavior from current official terms. Offline/disabled/misconfigured TMDB must not break Xtream metadata or playback. Provider removal disables network work and clears its credentials/cached data according to an explicit retention policy.

## 8. Storage And Cache Plan

Use new append-only migrations after inspecting the actual latest migration version. Table names below are proposed; do not reserve a version number in advance or edit existing migrations. Keep metadata outside hot catalog rows and bulk import hashing.

| Proposed Storage | Key And Data |
|---|---|
| Source capability record | Playlist ID + connection revision; configured mode, API state/capabilities and timestamps. Secret-store reference, never credentials. |
| Provider entity bindings | Playlist ID + local entity kind/key + provider namespace + typed provider ID + connection revision; mapping confidence/evidence. Namespace includes account scope for Xtream IDs. |
| Metadata cache | Provider + account scope where applicable + entity type + provider ID + locale + schema version + revision; sanitized normalized fields and provenance, fetched/expiry times. |
| Series/episode relation bindings | Account-scoped provider series/episode IDs linked to local series/season/item identities; incomplete/complete fetch state. |
| External match overrides | Local entity + metadata provider + selected/rejected external ID and match evidence. |

Use stable local IDs/revisions in keys; never raw credentials, authenticated URLs or unsalted password hashes. Xtream metadata stays account-scoped even when two playlists share a host. TMDB content can be shared by verified external ID/locale only if current terms and isolation policy permit it.

Initial cache policy to measure: descriptive metadata fresh for 7 days, account/capability verification for 24 hours, unsupported/not-found negatives for 15 minutes. Auth failures are not cached as empty metadata. Serving stale metadata offline is allowed with known provenance; stale account state must never be presented as a fresh subscription check. Revalidate lazily when details open; provide manual retry and use size/age-bounded LRU maintenance, initially 50 MiB excluding artwork and credentials.

On credential/server edits, increment connection revision, cancel old requests, invalidate account verification and account-scoped bindings; keep local catalog/user identity and non-sensitive stale descriptive data only under an explicit retention rule. Playlist deletion removes its bindings/account-scoped cache and secrets, including pending work. Import refresh must not delete user data or external match overrides. Use a durable pending/source-revision mechanism for DB/secure-store updates because they cannot form one atomic database transaction; recover from partial writes without exposing old secrets as the new source.

## 9. Details And Interaction

Movie selection opens existing Details immediately. Render local title/artwork/group/description and Play first, then load enrichment independently. Optional areas include plot, genres, release date, runtime, rating with source, cast/director and supported artwork. Hide unavailable fields. A metadata error gets a bounded safe retry state, not a full-screen playback failure.

For series, propose a series overview with metadata and a clear Browse seasons command before the existing season/episode routes. This changes the current activation destination and is gated for approval in XM-08. Keep a simple season-browser fallback and preserve Back to the original series tile. Do not invent Resume, watched state or episode availability.

Use responsive scrollable composition for portrait, short landscape, desktop and remote-first layouts. Address the known short-landscape/2x Details overflow in the scoped UI step. Keep the card/list preference, focus restoration, visible focus and target sizes; metadata arriving must not steal focus, move Play unpredictably or auto-start a trailer. Trailers/external links require a separate capability and approved action, not an automatic embedded player.

## 10. Work Packages

READY means prerequisites are satisfied, not that this document authorizes coding. Read listed owners and relevant `.agents/skills/` before each implementation. XM-01 through XM-03 are complete; XM-04 is the next unblocked package. Other implementation remains pending.

| ID | Deliverable | Depends On | Status |
|---|---|---|---|
| XM-01 | Source/capability contracts and detection parser | None | DONE (2026-10-15): Local-only contracts/parser, exact password preservation; 29 focused cases and all 315 tests pass. |
| XM-02 | Safe Xtream authentication client and fixture contract tests | XM-01 | DONE (2026-10-15): Injected credentials/transport, sanitized typed results, bounded cancellable HTTP; 59 authentication cases and all 374 tests pass. |
| XM-03 | Source persistence/editor verification and URL promotion | XM-02 | DONE (2026-10-15): Revision-safe persistence/recovery and integrated Add/Edit verification, retry/cancellation and URL-only fallback; all 469 tests pass. Native checks pending. |
| XM-04 | Typed provider identity and hybrid M3U mappings | XM-03 | READY |
| XM-05 | Metadata repository/cache and first Xtream provider | XM-04 | PENDING |
| XM-06 | On-demand series mappings and episode relationships | XM-05 | PENDING |
| XM-07 | Enhanced movie details | XM-05 | PENDING |
| XM-08 | Series overview route and metadata UI | XM-06, explicit navigation approval | GATED |
| XM-09 | Later category-batched Xtream catalog sync and identity bridge | XM-04, XM-06, import/search policy approval | GATED |
| XM-10 | TMDB integration decision, matching and provider | XM-05, privacy/token/terms approval | GATED |
| XM-11 | Cross-device, security and performance checkpoint | XM-07; optional branches if selected | PENDING |

### XM-01: Source Contracts And Detection

Owners: source config, form validators, source tests; proposed small `services/sources/` contracts/parser. Separate credential-bearing config from public summaries. Model input kind/catalog mode/verification/capabilities/revision. Parse recognized credential queries with `Uri`, preserve original URL and output options, specify bare-host scheme confirmation. No network traffic.

Done: parser tests cover schemes, ports/IPv6/base paths, percent encoding, special characters, empty/duplicate parameters, arbitrary credential scripts, direct-stream rejection and exact password preservation. Existing source serialization remains backward compatible and IDs unchanged.

Implemented evidence (2026-10-15):

- [Source contracts](../lib/services/sources/source_contracts.dart) separate input kind, catalog mode, verification, account state, immutable capability results and connection revision. `PlaylistSourceKind` is re-exported from its existing settings import path, retaining enum values and serialized names. Public summaries contain no credential or raw-URL fields.
- [Local detection](../lib/services/sources/xtream_source_detection.dart) returns a credential-bearing `XtreamSourceCandidate`, not a verified connection. It preserves the original URL verbatim, decodes credentials once, and derives a query-free same-origin endpoint with structured `Uri` fields. Recognized `get.php`/`player_api.php` paths do not require endpoint correction; other supported script suffixes (`.php`, `.cgi`, `.asp`, `.aspx`) require confirmation. Unsupported/non-script paths produce no candidate.
- `parseXtreamServerAddress` rejects unsupported schemes, user-info, fragments, queries and invalid authorities. Bare server inputs return an HTTPS suggestion with `requiresSchemeConfirmation=true`; no request is made. These flags must be honored by the later verification/editor flow.
- Explicit source passwords now retain whitespace and special characters on storage round trip and URL resolution. Existing explicit usernames still trim surrounding whitespace for backward compatibility; URL credentials preserve decoded values exactly. No existing playlist IDs are reassigned and no detection-driven import changes occur. Previously saved, already-trimmed passwords cannot be recovered automatically.
- [Detection and compatibility tests](../test/services/sources/xtream_source_detection_test.dart): 29 cases. Parser + existing storage pipeline + architecture checks: 47 passing. Full suite: 315 passing. `flutter analyze` reports only the existing `unawaited_futures` info in `webos/flutter/main.dart`.
- No HTTP client, database migration, editor integration, source-mode switch or provider contact was added. XM-02 supplies authentication; XM-03 connects verification and safe summaries to persistence/UI.

### XM-02: Safe Authentication Client

Owners: proposed `services/xtream/` client/mappers, injected transport/credential resolver, redaction tests and fake HTTP server. Validate auth/account response, typed failures, origin restrictions, cancellation/timeouts, response limits, capability states and safe logs. Parse only necessary safe account fields.

Done: fixture contract tests cover valid string/integer auth, denied/expired/disabled account, invalid JSON/HTML/200, 401/403/407/404/429/503, bad TLS, timeout, oversized body, credential echoes, cross-origin redirects and server-info host substitution. No private provider is needed for automated tests.

Implemented evidence (2026-10-15):

- [Authentication contracts](../lib/services/xtream/xtream_authentication.dart) define an injected playlist/revision credential resolver, explicit endpoint confirmation, cancellation, transport responses and sanitized typed results. Results expose only verification/account state, normalized expiry/counts, whitelisted output formats, failure kind, HTTP status and bounded retry delay. Catalog capabilities remain unknown; authentication does not probe or certify them.
- [XtreamApiClient](../lib/services/xtream/xtream_api_client.dart) validates a confirmed query-free HTTP(S) `player_api.php` endpoint, preserves credentials through structured query encoding, accepts only integer/string auth flags and ignores credential echoes, arbitrary messages and server-advertised endpoints. Logging includes only fixed event names, enum states and numeric HTTP status, never source IDs, bodies, authenticated URLs or exception text.
- The default `IoXtreamAuthTransport` keeps standard certificate validation, enforces a 10-second connection timeout and disables all automatic redirects, including same-origin redirects. Each invocation has its own transport, a configurable 30-second overall deadline (including secret resolution), and a configurable 2 MiB response limit checked both from announced length and received bytes. Completion, cancellation and failure force-close the transport; late secret/header completions cannot initiate further work.
- Authentication makes one attempt with no automatic retries. HTTP 429/503 return safe typed failures and parsed `Retry-After` (seconds or HTTP date, clamped to 24 hours) for an explicit later retry. Catalog/account request scheduling remains with the later integration/sync flow; no background authentication loop was introduced.
- [Smoke test](../test/services/xtream/xtream_api_client_test.dart) and [contract tests](../test/services/xtream/xtream_authentication_contract_test.dart): 59 passing cases. Local HTTP servers verify real request encoding, successful authentication, payload rejection and zero requests to a cross-origin redirect target. Injected failures verify TLS error classification; native device TLS/provider compatibility remains pending.
- Full suite: 374 tests pass. Final authentication suite: 59 pass. `flutter analyze` reports only the existing webOS `unawaited_futures` info. No provider requests, UI wiring, persistence, migrations or source-mode changes were added. XM-03 will supply the secure-store resolver and integrate verification with Add/Edit.

### XM-03: Persistence And Add/Edit Flow

Completed (2026-10-15): persistence/recovery, controller and production dependency wiring, Add/Edit verification and saved status display. Save remains separate from Refresh and does not activate a playlist. API verification does not switch catalog transport or certify catalog/detail endpoint capabilities.

Owners: settings repository, secret store contracts, playlist controller/editor, composition root and new migration. Reuse explicit name/server/username/password fields, add verification and detected-Xtream state, persist safe capability summaries, allow URL-only fallback and explicit retry. Recover from partial DB/secret-store writes. Preserve current save-versus-refresh and active playlist behavior.

Done: legacy URL and explicit Xtream sources load without forced migration/import, verified URL gains API capability while preserving input/output options, secrets stay out of summaries/logs, and credential edits/deletion invalidate the correct revision. Key-event tests cover submit, cancellation, error recovery and Back.

Implemented evidence:

- [Settings persistence](../lib/services/settings/settings_repository.dart) stores safe verification/account state, API opt-in and connection revision separately from secret source JSON. The append-only [v12 migration](../lib/services/storage/source_verification_v12_migration.dart) is registered in the database adapter. Unique secret references and a durable cleanup journal recover interrupted secure-store/database writes without replacing a working source prematurely.
- Source changes invalidate prior verification; names and equivalent normalized server addresses do not unnecessarily change connection identity. Draft edits map to one persisted revision increment. Expected-revision checks inside serialized repository saves reject stale editor writes, and separate verification updates are revision guarded. Existing catalog/user-data identities and original URL options remain intact.
- [Editor controller](../lib/features/playlists/playlist_editor_controller.dart) recognizes URL candidates and explicit credentials, requires confirmation for insecure/ambiguous connections and bare-server scheme suggestions, supports verification/retry/cancellation and URL-only opt-out, and discards stale async results. Saved status and opt-out are restored on reopening without an automatic network request. Saving a failed revalidation replaces an earlier verified state with the latest sanitized failure status, including safe temporary-unavailable state for thrown verifier failures.
- [Add/Edit dialog](../lib/features/settings/widgets/playlist_editor_dialog.dart) uses the editor controller with responsive scrollable form/actions, obscured passwords, host-only API preview, confirmation controls, fixed safe error text and working Back/cancel. [Playlist controller](../lib/state/playlists_controller.dart) saves source configuration independently from import/activation; [composition root](../lib/app/app_dependencies.dart) injects the production [Xtream verifier](../lib/services/xtream/xtream_source_verifier.dart). Credential-bearing drafts stay behind that verifier interface; persisted configurations are resolved through the settings repository's existing secret-store path. No background provider scan or automatic API import was added.
- [Playlist card](../lib/features/settings/widgets/playlist_card.dart) displays a short saved source/verification state without displaying credentials. Authentication remains distinct from catalog capability checks: those capabilities stay unknown until later endpoints are implemented and verified.
- [Persistence recovery tests](../test/services/settings/settings_repository_persistence_test.dart), [editor state tests](../test/features/playlists/playlist_editor_controller_test.dart), [real-database editor tests](../test/features/playlists/playlist_editor_persistence_test.dart), [dialog interaction tests](../test/features/settings/playlist_editor_dialog_test.dart), and [verifier tests](../test/services/xtream/xtream_source_verifier_test.dart) cover failed writes/commits, restart recovery, legacy migration, stale revisions, repeated draft edits, cancellation/late results, retry, URL fallback, safe output, keyboard/Back and no import-on-save.
- Final editor/controller/persistence focused run: 58 passing. Full `flutter test`: 469 passing, including architecture and existing catalog/navigation checks. `flutter analyze` reports only the existing `unawaited_futures` info in `webos/flutter/main.dart`; `git diff --check` passes. No real provider requests were made during implementation. Native Android/TV, Windows and webOS visual/network checks remain pending.

### XM-04: Provider Identity Without Catalog Churn

Owners: catalog schema/protocol/query boundaries, proposed provider binding service, importer/query/storage tests. Retain trustworthy typed provider IDs and mapping evidence. Resolve selected items through playlist/entity references, not by reparsing UI-visible URLs. Scope API requests to a verified account; preserve existing item and user-library keys.

Done: tests prove no cross-account or cross-kind ID collision, bare URLs remain unmapped without evidence, placeholders are rejected, metadata attachment does not change catalog hashes/user data, and legacy items still play. Benchmark mapping overhead before considering native import.

### XM-05: Metadata Repository And Xtream Movie Provider

Owners: proposed metadata contracts/repository/cache and Xtream VOD mapper; composition root, migration and metadata tests. Implement cache-first selected-movie lookup, typed normalized fields, provenance, locale, stale fallback, deduplicated requests and bounded cache maintenance. Include a fake second provider to exercise merge/priority independently of Xtream.

Done: missing/malformed fields, wrong item IDs, unavailable APIs, stale/negative cache, timeout/cancel, in-flight deduplication, playlist switch and credential revision tests pass. Metadata failure never changes playback availability. No per-card or focus-triggered requests.

### XM-06: Series Identity And On-Demand Detail

Owners: Xtream series mapper, bindings, series query service and catalog state. Fetch candidate show IDs category-by-category; request one selected show's detail when confidently mapped. Validate season keys/episode IDs/numbers and preserve specials without violating current schema constraints; add a migration if zero-number specials need representation. Do not silently coerce special episode zero to one.

Done: two shows with the same title, unrelated show IDs, title-only ambiguity, incomplete series, huge detail payload, missing/duplicate episodes, nonnumeric season keys and sparse API metadata have safe fixtures. Existing local series stay usable when no mapping is available; no all-series episode crawl occurs.

### XM-07: Enhanced Movie Details

Owners: Details screen, proposed feature-local controller/view model, shared artwork and tests. Integrate the metadata repository with immediate local fallback. Coordinate with DE-02/DE-03 in the [design evolution plan](design-evolution-implementation-plan.md): reuse completed artwork/layout work, or extract only the minimal shared component here and update both plans. Do not mark those design steps done without their checks.

Done: real optional metadata is visible, loading/offline/failure cannot block Play, stale responses cannot update a different item, focus remains stable, and 360x800/390x844/800x360/1440x900 plus 2x text layouts pass. Capture deterministic local-artwork screenshots, not provider-dependent images.

### XM-08: Series Overview Decision And UI

Before code, record approval in decisions.md for Series -> Overview -> Seasons -> Episodes and the initial focus/Back contract. Then add a typed series subject/route with the same repository, keeping series metadata distinct from episode metadata. Do not repurpose `DetailsRoute(ContentItem)` with a fabricated playable show.

Done: Home/cards/list/Search entry paths use the approved route consistently; Browse seasons remains reachable on metadata failure; Back restores the prior tile/row and paged state. Movie/live activation behavior is unchanged.

### XM-09: API-Native Catalog Sync

Before code, approve mode switching, category completion/stale deletion semantics, lazy series counts/search coverage and identity migration policy. Owners: catalog sync/import coordinator/worker/staging/query service and provider adapters. Use source-aware routing behind the existing repository, not HTTP in widgets. Split category/live/VOD/series implementation into independently testable substeps when needed.

Implement the category-based fetch/session sequence in section 6 for all supported kinds. Separate this package into request scheduling and durable scope tracking, live/VOD import, series-header import, and existing-source transition checks as needed. Category batching is a committed planning requirement for this later milestone; provider limitations determine whether it is available for a particular source.

Done: a filtering-capable fixture imports live, movies and series without requesting `get.php` or unfiltered whole-kind endpoints; bounded memory/import batches and local paging are measured with large synthetic catalogs. Cancel/retry/resume/partial-refresh failures retain cached data; source edits invalidate old checkpoints. The identity bridge preserves favorites/history/progress and hidden groups. Reverting to hybrid M3U is supported without a schema downgrade. Test ignored category filters, absent pagination, oversized categories, uncategorized items, duplicate memberships and incomplete category discovery explicitly; no incomplete scope causes global stale-item deletion.

### XM-10: TMDB Provider

First record token ownership/distribution, opt-in/privacy, language, merge priority, manual matching and current attribution/terms requirements. Implement its adapter with provider-neutral subjects/results only. Never pass Xtream connection objects to it.

Done: exact-ID, external-ID, ambiguous title/year and wrong-media-type matches have tests; user correction persists; attribution is visible as required; disabled/offline/429/token failures leave provider metadata and Play usable. Network assertions prove provider credentials/URLs cannot reach TMDB.

### XM-11: Release Checkpoint

Run focused tests after each meaningful edit, then `flutter analyze` and `flutter test` before marking a package complete. Compare analyzer output to the known baseline rather than suppressing unrelated notices. Run architecture rules and redaction tests; inspect new fixtures, logs and docs for secrets.

Done: migration/recovery tests, fake-provider contract tests, Details accessibility/focus/Back tests, performance measurements and deterministic screenshots are recorded. Separately list Android phone, Android TV, Windows and LG webOS as verified or pending with actual viewport/input/network conditions. A unit test does not certify native HTTP/TLS or provider compatibility. Authorized provider smoke tests must record only safe action/status/timing evidence, never raw URLs/account payloads.

## 11. Recovery, Decisions And Handoff

- Implement one package at a time with its fakes, tests and usable fallback. Do not commit or create branches unless asked. New schema changes are append-only; rollback disables a feature/provider rather than downgrading or deleting unrelated catalog/user data.
- Stop and ask if a provider requires cross-origin credential forwarding, insecure TLS workarounds, opaque authentication, unsupported DRM, or a change to approved playback/navigation semantics. Never bypass provider access restrictions.
- Keep XM-08/09/10 gated until their choices are approved. Their absence does not block hybrid movie metadata.
- Track package status here with date, concrete test evidence, migration names, screenshots and remaining device checks. Update the architecture status table only for work actually completed; this planning document does not complete an implementation package.
- Each handoff states supported source inputs, verified capabilities, unmapped/ambiguous content limitations, cache/privacy behavior and exact next unblocked package.

First useful milestone: explicit/detected Xtream verification plus safe movie enrichment over existing M3U catalogs (XM-01 through XM-05 and XM-07). Then deliver series mapping/overview with its route decision. API-native import and TMDB can follow independently; neither is a prerequisite for useful provider metadata.