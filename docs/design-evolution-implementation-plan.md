# Design Evolution Implementation Plan

Created: 2026-10-11. Audience: developers and coding agents.

Use this plan when implementing selected ideas from the [Kanal concept](Kanal_%20IPTV%20TV%20experience%20concept.html). Evolve the existing application; do not replace its architecture or reproduce the HTML canvas.

## 1. Authority And Scope

- Current source, tests, schemas, and configuration establish implemented behavior. Historical audit text is not a current defect list.
- [Product & UX Requirements](IPTV_App_Product_UX_Requirements.md) establishes product intent.
- [Cross-Device Design Contract](design-guidelines.md) establishes presentation, input, accessibility, and responsive rules.
- [Decisions](decisions.md) controls behavior changes. This plan does not resolve D-8 or D-9, or override the resolved D-7 stop-on-exit policy.
- [Architecture Work Packages](architecture-code-improvements.md) and [Architecture Rules Test](../test/architecture/architecture_rules_test.dart) remain authoritative for engineering boundaries. This document adds design work, not replacements for completed packages.

Creating this plan authorizes planning, not silently deciding its gated product choices. Presentation steps below retain current activation destinations and catalog defaults.

### Preserve

- Material 3, app-owned tokens, constructor injection, existing controllers, and typed navigation.
- Adaptive bottom navigation/rail, current routes, focus restoration, Back precedence, and shell geometry.
- Query-driven paging, group filters, cached content, retryable states, and playlist isolation.
- Current dark palette and branding until D-9 is resolved.
- Stop playback on player route exit; pause VOD and stop live when backgrounded, as specified by D-7.

### Adopt Selectively

- More visual Details using actual artwork and available metadata.
- Channel rows rather than treating channels as movie cards.
- Poster-oriented movie/series presentation and landscape episode presentation.
- Lightweight information following focus on sufficiently large layouts.
- Later, genuine viewing history, explicit resume, and a bounded Continue Watching section.

### Do Not Copy

The fixed 1280x720 stage, CSS dimensions, clipped grids, simulated Enter actions, gradient poster placeholders, fabricated ratings/programs/progress, instructional copy, or automatic playback on focus. Do not infer TV layout from an OS name or keyboard use.

## 2. Execution And Commit Rules

1. Choose one READY step whose dependencies are DONE. Read its owners, nearby tests, relevant local skills, and applicable decisions before editing.
2. Confirm one current behavior and a focused check that could disprove the proposed change. Add or update that check with the implementation.
3. Implement only that step. If it cannot fit one reviewable commit, split it in this table before proceeding; do not hide multiple features behind one step.
4. Run focused validation immediately after the first substantive edit. Then run the required full checks before marking the step DONE.
5. Inspect the diff for unrelated changes, credentials, accidental data-contract changes, and new dependencies.
6. Update this document's status/evidence in the same commit. Record test results and screenshot locations, not claims of unperformed hardware validation.
7. Create a commit only when explicitly requested. Suggested messages below define commit boundaries; they are not permission for an agent to commit automatically.
8. A step must leave a usable application with no dependency on an uncommitted next step. Land contracts with implementations/fakes/tests together. No placeholder buttons or fabricated production data.

For a decision gate, the commit contains only the approved decision and its documentation updates. A blocked optional branch does not block unrelated presentation work.

Rollback means reverting that step's commit through the normal reviewed workflow. Never revert unrelated user edits. Database migrations are append-only: rollback application behavior without assuming a destructive schema downgrade.

## 3. Current Implementation Anchors

Verified against source on the creation date; re-check before implementation.

| Surface | Current Owner And Constraint |
|---------|------------------------------|
| Shell | [AppShellScaffold](../lib/ui/widgets/app_shell_scaffold.dart): compact bottom destinations, medium/expanded rail, content-focus handoff. Keep it. |
| Presentation | [MediaTile](../lib/ui/widgets/media_tile.dart) and [AppTokens](../lib/ui/theme/app_tokens.dart): shared activation, artwork fallback, focus/selection semantics, reduced motion, stable geometry. Extend conservatively. |
| Details | [DetailsScreen](../lib/features/details/details_screen.dart): group, description, focused Play command. [ContentItem](../lib/models/content_item.dart) has poster/logo/description, but no typed rating/year/runtime fields. |
| Catalog | [CatalogScreen](../lib/features/catalog/catalog_screen.dart), [GroupSidebarLayout](../lib/features/catalog/widgets/group_sidebar.dart), [PagedGridView](../lib/ui/widgets/paged_grid_view.dart), and [CatalogViewState](../lib/state/catalog_view_state.dart). Live and movies currently share grid presentation. |
| Home | [HomeScreen](../lib/features/home/home_screen.dart): configurable Live/Movies/Series previews. These are catalog previews, not viewing history. |
| Read API | [CatalogQueryService](../lib/services/catalog/catalog_query_service.dart) and [Catalog Summaries](../lib/services/catalog/catalog_query.dart): bounded queries, selected-item lookup, series/seasons/episodes. Do not fetch complete rows for every tile. |
| User library | [UserLibraryRepository](../lib/services/catalog/user_library_repository.dart): playlist/profile/item-key-scoped favorites, progress, and history storage already exists. Storage availability is not proof of end-to-end player/UI integration. |
| Playback | [PlayerController](../lib/features/player/player_controller.dart) and [Playback Contract](../lib/services/playback/playback_contract.dart): position/duration, seek capability, asynchronous session commands. Resume must respect session identity and lifecycle. |

New component/controller/test names proposed below are not existing APIs. Create them only when the step needs them and follow neighboring naming patterns.

## 4. Step Status

READY means no unresolved product gate, not that prerequisites can be skipped. GATED means an explicit human decision is required. All steps are initially unimplemented.

| ID | Step | Depends On | Status | Suggested Commit |
|----|------|------------|--------|------------------|
| DE-01 | Deterministic visual baseline | None | READY | `test(ui): capture design evolution baseline` |
| DE-02 | Reusable bounded artwork | DE-01 | READY | `refactor(ui): share bounded media artwork rendering` |
| DE-03 | Adaptive visual Details | DE-02 | READY | `feat(details): add adaptive artwork and content hierarchy` |
| DE-04 | Channel row component | DE-02 | READY | `feat(live): add accessible channel row presentation` |
| DE-05 | Paged Live TV list | DE-04 | READY | `feat(live): use paged channel browsing layouts` |
| DE-06 | Poster-oriented catalog tiles | DE-02 | READY | `feat(catalog): add poster presentation for movies and series` |
| DE-07 | Adaptive episode presentation | DE-02 | READY | `feat(series): adapt episode presentation to available space` |
| DE-08 | Focus-following catalog context | DE-05, DE-06 | READY | `feat(catalog): show lightweight focused item context` |
| DE-09 | Presentation checkpoint | DE-03, DE-05, DE-06, DE-07, DE-08 | READY | `test(ui): verify evolved cross-device browsing` |
| DE-10 | Continuity policy decision | DE-09 | GATED | `docs(ux): define viewing continuity policy` |
| DE-11 | Stable playback library identity | DE-10 | GATED | `feat(library): resolve stable playback identity` |
| DE-12 | Session-safe progress/history recording | DE-11 | GATED | `feat(player): persist viewing progress safely` |
| DE-13 | Explicit resume execution | DE-12 | GATED | `feat(player): support explicit session-safe resume` |
| DE-14 | Resume actions in Details | DE-13 | GATED | `feat(details): offer resume and start over actions` |
| DE-15 | Bounded continuity query | DE-12 | GATED | `feat(library): query bounded continue watching items` |
| DE-16 | Continue Watching on Home | DE-14, DE-15 | GATED | `feat(home): add continue watching without replacing previews` |
| DE-17 | Episode progress states | DE-07, DE-12 | GATED | `feat(series): show persisted episode viewing states` |
| DE-18 | Continuity checkpoint | DE-16, DE-17 | GATED | `test(library): verify cross-device viewing continuity` |

Suggested execution: DE-01 through DE-09 first. Pause for visual review, then decide whether to start DE-10. Do not wait for EPG or a new palette to deliver the presentation milestone.

## 5. Presentation Steps

### DE-01 - Deterministic Visual Baseline

**Scope:** Add reproducible screenshot/golden fixtures for the current Details, Live, Movies, Series, Episodes, and Home. Use existing test harnesses; do not introduce a screenshot framework unless the existing tooling cannot serve the need.

**Owners:** Existing UI tests and [Test Support](../test/support/); reference [Shell Layout Tests](../test/app/app_shell_layout_test.dart) and [Navigation Focus Tests](../test/features/navigation_focus_test.dart).

**Checks:** Local deterministic artwork, missing/failed artwork, long titles, large text, empty/error states. No network-dependent goldens, real playlists, or credentials. Record baseline screenshots before redesign.

**Done:** Fixtures reproduce the current layouts, focused checks pass, and screenshot generation/review instructions are recorded here. This is a test-only commit.

### DE-02 - Reusable Bounded Artwork

**Scope:** Extract artwork rendering from MediaTile into a small shared component suitable for tiles and Details. Keep current MediaTile output and activation unchanged. Support explicit poster, landscape, and logo fitting constraints; preserve bounded decoding and accessible fallbacks.

**Owners:** MediaTile, AppTokens, a proposed artwork component under `lib/ui/widgets/`, and scoped tests under `test/ui/`.

**Checks:** Loading, failure, absent image, portrait/landscape/logo fitting, bounded decode dimensions, stable geometry, excluded decorative-image semantics. Compare default tiles against DE-01.

**Done:** MediaTile consumes the shared renderer with no unrelated geometry/theme changes. No second image cache implementation or domain dependency is introduced.

### DE-03 - Adaptive Visual Details

**Scope:** Use ContentItem poster/logo, title, group, and description. At sufficient width/height, place bounded artwork beside content; stack and scroll on compact/short layouts. Prefer a compact title hierarchy over a marketing hero. Retain the existing Play command and initial focus.

**Owners:** DetailsScreen, shared artwork, AppTokens, and proposed Details widget tests under `test/features/`.

**Checks:** Empty description/group, missing artwork, long title/description, 2.0 text scale, short landscape, Play activation exactly once, Back restores the originating tile. No rating/year/runtime parsing from arbitrary strings.

**Done:** Real available content is more legible and visual on compact and expanded layouts; no new action, route, or playback behavior exists.

### DE-04 - Channel Row Component

**Scope:** Add a logo/name/group row with a visible focus ring and selected semantics. Reuse shared activation/focus behavior where practical; extract only enough interaction code to avoid copying MediaTile's key handling. Keep the existing tile default unchanged.

**Owners:** Shared UI widgets and their tests. A proposed `ChannelRow` consumes a safe summary, not ContentItem/stream URLs.

**Checks:** Touch/Enter/Select activate once; focus differs from selection; disabled behavior if needed; missing logos; long names; 48/56 logical target baselines; reduced motion and semantics.

**Done:** A tested component exists without changing catalog routes. Do not show a playing indicator, channel number, quality badge, or program progress unless the caller supplies verified data.

### DE-05 - Paged Live TV List

**Scope:** Replace only Live catalog grid presentation with a lazy paged channel list. Reuse group selection, All default, query ordering, errors, and retry. Use existing narrow group controls and wide sidebar rules. Do not add video preview, EPG, zapping, favorites, or direct playback.

**Owners:** CatalogScreen, GroupSidebarLayout, paging widgets, and nearby catalog/state tests. Share paging triggers/state views rather than creating a separate data loader.

**Checks:** Initial/next-page load, underfilled viewport, retry after load-more failure, retained rows on failure, group changes during requests, hidden groups, resize preservation, directional navigation and Back restoration. Activation still opens Details.

**Done:** A large fixture is browsable through bounded queries on phone, desktop, and remote-first layouts, without loading the whole catalog.

### DE-06 - Poster-Oriented Catalog Tiles

**Scope:** Add explicit presentation variants for movies and series, then adopt them only in those catalog grids. Retain current Home strips until a separate step changes them. Use actual artwork and readable titles outside or below imagery; do not rely on text over unpredictable artwork.

**Owners:** MediaTile, AppTokens, movie/series branches of CatalogScreen, scoped UI tests.

**Checks:** Portrait and landscape source images, artwork absence, long titles, grid track stability, focus ring clipping, text scale, density at medium/expanded widths, existing activation routes and paging.

**Done:** Movies/series have intentional artwork-led presentation with no rating sorting, catalog query changes, or global radius/palette rewrite.

### DE-07 - Adaptive Episode Presentation

**Scope:** Present compact/short episode browsing as readable thumbnail/title/episode-number rows; retain a landscape-tile grid when constraints permit. Keep the existing Series -> Seasons -> Episodes route model and paging. Integrated season tabs are a later navigation decision, not part of this commit.

**Owners:** Episode branch of CatalogScreen, shared artwork/interaction, episode tests.

**Checks:** Missing episode number, long provider titles, no artwork, resize with current page/focus/scroll preserved, sequential keyboard navigation, activation to Details, empty/error/retry states.

**Done:** Episode layouts adapt without invented duration, watched labels, progress, or new navigation.

### DE-08 - Focus-Following Catalog Context

**Scope:** Add a stable information area for the focused Live/movie/series summary when content constraints leave adequate browsing space. Show title, group, artwork, and existing series counts only. No itemById call per focus movement in this step. Do not add a duplicate Play action.

**Owners:** MediaTile/ChannelRow focus callbacks, CatalogScreen and feature-local context widget/state. Keep selection and focus as distinct state.

**Checks:** Rapid focus movement, route changes, group reset, focused item removal, pointer and touch use, panel removal on resize, preserved paging/scroll/focus, absent artwork, no playback or repository write on focus. Expose the same essential information through accessible row/tile labels and Details.

**Done:** Context changes without grid movement, excessive announcements, data reloads, or expensive requests. Hide the panel when space is insufficient. Avoid a constantly announced live region.

### DE-09 - Presentation Checkpoint

**Scope:** Review representative screenshots against DE-01, add missing cross-feature regression cases, and fix only defects in DE-02 through DE-08. Split unrelated defects into separate work. Record accepted visual changes and remaining device checks.

**Checks:** Full verification matrix below; compare steps to find content, launch playback, and return to the same item. Check realistic messy provider titles and sparse artwork, not only ideal fixtures.

**Done:** Full analyzer/tests pass, accepted screenshots are recorded, and each native target is marked verified or pending. The app remains independently useful without any continuity step.

## 6. Continuity Steps

### DE-10 - Continuity Policy Decision

**Scope:** Record explicit approved answers in decisions.md before implementing behavior:

- What playback event counts as watched, and how often progress is checkpointed.
- Minimum resumable position, completion rule, unknown-duration behavior, and treatment of seeking near the end.
- Whether completed items remain in recent history but leave Continue Watching.
- Resume versus Start Over presentation, retry semantics, and whether Home activation still opens Details. Resolve the relevant D-8 questions explicitly; retain All unless separately approved.
- Initial focus on Home: retain current first-available behavior or approve history-backed behavior, including section visibility and fallback.
- Episode policy: resume only an in-progress episode in this milestone; define series deduplication if desired. Do not infer next-episode autoplay approval.
- Active playlist/profile scope, history retention, hidden-group exclusion, and explicit clear/remove behavior.

**Done:** Policy values and representative scenarios are approved, affected guidelines updated, and DE-11 through DE-18 can be marked READY. D-7 remains unchanged. This commit contains no application code.

### DE-11 - Stable Playback Library Identity

**Scope:** Trace catalog summary/item-key to selected-item/player flow and add a typed, playlist/profile-scoped identity boundary where missing. Inject UserLibraryRepository through existing composition; supply fakes. Never derive identity by exposing or logging stream URLs, or assume a row ID is an item key.

**Owners:** Catalog query/summary mapping, user library, selected-item command/navigation boundary, PlayerController, and composition root as required.

**Checks:** Identical row IDs across playlists, refresh/reorder preserving item keys, removed item, playlist switch during lookup, profile isolation, late lookup completion and disposal. All existing callers continue working.

**Done:** A player session can carry verified immutable library identity without changing start position or writing progress. Any API change includes all consumers and tests in this commit.

### DE-12 - Session-Safe Progress/History Recording

**Scope:** Record progress/history from PlayerController using DE-10 policy and DE-11 identity. Throttle writes, serialize pending checkpoints, and prevent an older session overwriting newer progress. Handle pause/background/exit before state is cleared. Do not block route exit indefinitely on storage.

**Owners:** PlayerController, injected user-library boundary, composition, library/player tests.

**Checks:** VOD versus live, unknown duration, failed startup, rapid replacement, Start Over resetting old progress, pause/background, exit before load completes, storage failure, database closing, duplicate events, disposal and write ordering. Use FakeAsync pumping for widget timers.

**Done:** Restarting preserves genuine progress/history, stale sessions cannot corrupt it, live has no false resume progress, and D-7 behavior still passes. Failures are logged safely without raw UI exceptions.

### DE-13 - Explicit Resume Execution

**Scope:** Add an explicit start-position command to the player session, separate from any UI. Load first; seek once only when the same session is ready and the adapter supports seeking; apply the approved invalid-position policy. Keep zero-position starts as the default for existing callers.

**Owners:** PlayerController and playback tests; adapter changes only if tests demonstrate a missing readiness contract.

**Checks:** Seek unsupported, duration absent/shorter than stored progress, failed seek/load, delayed readiness, rapid session replacement, retry and cancellation, position applied exactly once. No focus event starts playback.

**Done:** Fake-adapter tests establish command ordering and session safety. Backend resume checks are recorded per target; unverified adapters are not claimed supported.

### DE-14 - Resume Actions In Details

**Scope:** Load progress through an injected feature boundary and offer Resume/Start Over according to DE-10. Preserve the ordinary Play action when no valid resumable progress exists. Refresh covered Details when returning from playback; avoid stale async updates on another item.

**Owners:** Details feature, shared formatting, player commands, scoped widget tests.

**Checks:** Loading/lookup failure, no progress, completed content, unknown duration, unsupported seek, playlist/profile switch, focus on the approved primary action, both commands invoke once, Back restoration, text scale and labels.

**Done:** Users can explicitly choose where playback starts, and returned Details reflects the latest session without a second redundant resume dialog.

### DE-15 - Bounded Continuity Query

**Scope:** Extend the library read API with a bounded summary query for resumable movies/episodes, including progress needed by the UI. Existing recent-history storage alone is not this query. Filter hidden groups, missing catalog items, completion, and playlist/profile in the data layer. Specify stable ordering/tie-breaks and enforce a limit.

**Owners:** UserLibraryRepository, catalog safe-summary models as needed, SQLite and fake implementations, [Library Repository Tests](../test/services/catalog/user_library_repository_test.dart).

**Checks:** Limit, ordering, exclusions, same key in another playlist/profile, refresh/removal/reappearance, unknown duration and policy edges. Avoid per-card progress lookups and full-library materialization. Inspect query plans on a large synthetic catalog; add append-only indexes only if needed.

**Done:** One bounded read supplies the Home slice and accurate progress, with all implementations covered and no UI access to SQL.

### DE-16 - Continue Watching On Home

**Scope:** Add a bounded row above existing configurable previews. Use real progress and explicit continuation labels. Observe library changes/return-from-player through a narrow feature owner; generation-guard playlist changes. Keep existing sections and navigation, and avoid a generic recommendation hero.

**Owners:** HomeScreen, a proposed Home continuity state owner, library read boundary, shared media presentation, Home tests.

**Checks:** Empty row disappears, first launch, completed/removed/hidden item, refresh failures, section preferences, focus restoration, latest item arriving late, rapid playlist switching, activation follows DE-10, title/progress semantics and resize.

**Done:** A genuine prior viewing session appears on Home after restart, with no fabricated progress, duplicate unbounded history list, or unexpected autoplay.

### DE-17 - Episode Progress States

**Scope:** Add bounded page-level progress reads and show in-progress/completed states for loaded episodes. Do not perform one database request per widget. Derive labels from DE-10, not title text. An unwatched episode is not necessarily newly added.

**Owners:** Episode presentation, query/library boundary, feature state and tests.

**Checks:** Partial/unknown duration, completed episode, missing progress, page load/resize, profile isolation, no N+1 queries, stale responses after season change, progress distinguishable without color alone.

**Done:** Episode rows/tiles show actual viewing state, retain existing activation routes, and do not start the next episode automatically.

### DE-18 - Continuity Checkpoint

**Scope:** Add restart-and-return integration coverage using real SQLite fixtures and fake playback. Review Home -> Details -> Resume -> Back -> Home and Series -> Episodes -> Details -> Player flows. Record native resume outcomes and remaining backend limitations.

**Checks:** Playlist refresh preserves progress, same title in different playlists stays isolated, completion removes an item according to policy, failures retain usable browsing, route exit stops playback, background VOD/live rules remain unchanged.

**Done:** Full checks pass and continuity is usable independently of EPG, autoplay, PiP, enrichment, or theme work.

## 7. Movie Metadata Provider And Details Enrichment

This branch implements metadata for the selected movie's Details view, with TMDB as the first provider. It does not enrich the entire playlist, change movie identity, add rating sorting, or cover television series. It can run after DE-03 independently of the continuity branch.

### Architecture

```text
DetailsScreen
		-> MovieDetailsController (feature-local state)
				-> MovieMetadataRepository (matching, cache, fallback)
						-> MovieMetadataProvider (vendor-neutral interface)
								-> TmdbMovieMetadataProvider (HTTP and TMDB mapping)
						-> metadata cache abstraction
```

All names in this section are proposed. Put vendor-neutral contracts/models and data implementations under `lib/services/metadata/`; put presentation state under `lib/features/details/`. Wire dependencies at the existing composition root. Screens and controllers must not import TMDB implementations, HTTP clients, database adapters, or vendor JSON models. Add architecture-rule coverage for this boundary.

The provider retrieves metadata; the repository decides which result belongs to a local movie and how it is cached. Neither replaces CatalogQueryService or UserLibraryRepository. Keep stream URL, playback identity, progress, playlist membership, and provider metadata separate.

### Proposed Common Contract

Interface sketch, not an existing API. Implement its named value/result types in MM-01 before using it:

```dart
abstract interface class MovieMetadataProvider {
	String get sourceId;

	Future<MovieSearchResult> search(MovieSearchRequest request);

	Future<MovieMetadataResult> fetchDetails(
		MovieMetadataReference reference, {
		required String languageTag,
	});
}
```

- `MovieSearchRequest`: title, optional release year, language tag, and bounded page/result request. No ContentItem or stream URL. The adapter must not exhaust every search page.
- `MovieMetadataReference`: opaque `(sourceId, externalId)`. Only the matching provider interprets its ID; no `tmdbId` field in shared UI/domain models. Reject references belonging to another source.
- `MovieCandidate`: reference, localized/original title, optional release date/year, and optional artwork, sufficient for conservative matching. Do not expose TMDB response objects.
- `MovieMetadata`: reference, localized/original title, nullable overview/release date/runtime, genre labels, optional bounded poster/backdrop URLs, and optional rating with its scale, vote count, and source. Include language/provenance and fetched time where appropriate; no vendor genre IDs in UI.
- `MovieSearchResult` and `MovieMetadataResult`: typed success, no-match/not-found, unavailable/disabled, unauthorized, rate-limited, and failed outcomes as applicable. Search success can carry bounded candidates/next-page information. Failure may carry safe retry timing, not raw exception text, request headers, tokens, or response bodies.
- The repository adds resolved, ambiguous, unmatched, fresh/stale-cache, and retryable-failure states. Ambiguous candidates are not provider errors. Keep matching policy out of the HTTP adapter.

Use immutable Dart value types and sealed result types following local conventions, without new model-generation/state-management packages. Cancellation strategy must be explicit: abort transport work when supported and otherwise discard stale results using request/session generations. Deduplicated requests need ownership rules so leaving one view does not cancel another consumer's lookup.

### TMDB Adapter

Use an injected HTTP client and credential/configuration boundary. Reuse the project's HTTP package when appropriate, but do not reuse playlist-specific downloading/import logic for metadata requests. TMDB-specific endpoints, serialization, authentication, image configuration, and error mapping stay inside the adapter.

Verified API references on 2026-10-11:

- [Movie Search](https://developer.themoviedb.org/reference/search-movie): `GET /3/search/movie`, with `query`, `language`, optional year filters, adult-content policy, and bounded pagination.
- [Movie Details](https://developer.themoviedb.org/reference/movie-details): `GET /3/movie/{movie_id}`, localized via `language`; response includes overview, release date, runtime, genres, image paths, vote average, and vote count.
- [TMDB FAQ And Attribution](https://developer.themoviedb.org/docs/faq): verify current terms before release; non-commercial access requires attribution, and commercial use requires the appropriate agreement.

Resolve TMDB image paths to HTTPS URLs using documented configuration and supported sizes, verified during MM-03; never send a relative vendor path to the artwork widget. Request only the fields/endpoints needed for movie Details. Cast, videos, recommendations, and series metadata are outside this branch.

Handle missing/malformed fields conservatively. Runtime is descriptive metadata, not the player's authoritative stream duration. A rating with no votes is unavailable, not a displayed `0.0`. Preserve the rating's source and scale rather than presenting it as a universal score.

### Matching, Cache, And Privacy

- Build lookup input from local title and trustworthy optional year/external-ID evidence. Strip only known provider decorations under a tested policy; preserve meaningful digits, subtitles, accents, and original titles. Never assume arbitrary ContentItem.metadata contains a valid TMDB ID.
- Prefer a verified existing mapping. Otherwise search with bounded requests and conservatively compare original/localized title and year. A sole or first result is not sufficient proof. Define evidence thresholds in MM-02; unknown-year remakes and close candidates remain ambiguous.
- An unresolved match leaves local Details intact. Manual candidate selection/correction is a later interaction package unless separately approved; do not ship an ambiguous-match state with a nonfunctional correction button.
- Cache source records by source/external ID/language and local mappings by playlist/stable item key. Store match provenance, policy version, and title/year fingerprint; revalidate when local evidence changes. A stale title-to-movie mapping must not silently follow a changed item.
- Apply approved fresh/stale/negative-cache lifetimes and bounded eviction. Deduplicate concurrent lookups; do not negative-cache timeouts, unauthorized responses, or rate limits as permanent no-match. Offline stale metadata remains available and distinguishable from fresh data.
- Use append-only migrations only when persistent cache tables/indexes are needed. Do not rewrite catalog import tables or attach metadata by volatile row ID. Preserve profile isolation if manual overrides later become profile-specific.
- Query only on opening movie Details, never on every tile focus or playlist import. No complete-catalog lookup, per-tile network calls, or synchronous network dependency for playback.
- Send only approved title/year/language or verified external IDs to the provider. Movie titles reveal viewing interests; document this data flow and any opt-in/disable policy. Never send playlist names, stream URLs, credentials, progress, or user history.
- No production tokens in source, fixtures, logs, committed environment files, or screenshot artifacts. A token embedded through a build define is extractable, not secure storage. Decide between a controlled backend credential boundary and user-supplied secure configuration; keep the provider interface unchanged either way. Agents must not request secrets through chat.

### Commit-Sized Metadata Steps

| ID | Step | Depends On | Initial Status | Suggested Commit |
|----|------|------------|----------------|------------------|
| MM-01 | Neutral contract/models and fake provider | None | READY | `feat(metadata): define vendor-neutral movie provider` |
| MM-02 | Configuration, matching, and usage policy | MM-01 | GATED: human policy/configuration decision | `docs(metadata): define TMDB integration policy` |
| MM-03 | TMDB provider adapter | MM-02 | GATED | `feat(metadata): implement TMDB movie provider` |
| MM-04 | Matching repository and persistent cache | MM-03 | GATED | `feat(metadata): cache and resolve movie metadata` |
| MM-05 | Injected movie Details state | MM-04 | GATED | `feat(details): load metadata through an injected repository` |
| MM-06 | Enriched movie Details presentation | MM-05, DE-03 | GATED | `feat(details): present optional movie metadata` |
| MM-07 | Metadata integration checkpoint | MM-06 | GATED | `test(metadata): verify fallback and vendor isolation` |

After MM-02 approval, mark remaining MM steps READY subject to dependencies. Do not add these dependencies to DE-03 or DE-09: local-only visual Details remains a complete deliverable.

### MM-01 - Neutral Contract/Models And Fake Provider

**Scope:** Implement the contract and value/result types above, with a deterministic fake and provider contract tests. Define nullable metadata and source-scoped references without a vendor dependency. Keep this an additive contract/test commit; no HTTP calls or Details changes.

**Checks:** Bounded search input/output, empty candidates, optional fields, non-TMDB source references, typed failures, rating scale/count, immutable results, and invalid cross-provider reference handling.

**Done:** A fake provider can supply movie Details data through the neutral interface. Shared types contain no TMDB JSON/SDK imports, and tests demonstrate a second source namespace without implementing a second production vendor.

### MM-02 - Configuration, Matching, And Usage Policy

**Scope:** Record approved credential delivery, non-commercial/commercial terms, attribution placement/assets, language/fallback and adult-content policy, matching thresholds, cache lifetimes/eviction, request budgets, retry limits, and privacy/disable behavior in decisions.md. If a backend is chosen, separately scope its provisioning and authenticated client contract before MM-03; this plan does not assume a backend exists.

**Checks:** Review current TMDB documentation and approved logo assets. Plan the required About/Credits attribution and notice: "This product uses the TMDB API but is not endorsed or certified by TMDB." Provider-required attribution is an exception to omitting instructional concept copy.

**Done:** Policy and configuration prerequisites are explicit and approved, with no committed secret and no code depending on an unavailable credential/backend. This is a documentation-only decision commit.

### MM-03 - TMDB Provider Adapter

**Scope:** Implement search/details mapping behind MovieMetadataProvider, using injected HTTP/configuration/credentials. Map authentication, timeout, malformed payload, 404, 429, and server/network errors to neutral outcomes. Bound retries/concurrency and respect retry timing when supplied. Provide disabled behavior when configuration is absent.

**Checks:** Fixture responses via a fake HTTP client; URI encoding, language/year parameters, source reference validation, HTTPS image resolution, null fields, minutes-to-duration conversion, no-vote ratings, request timeout, 429 handling, auth header redaction, and canceled/stale calls. Never require real credentials in automated tests.

**Done:** Adapter contract tests pass and consumers can swap it for the fake without changing application code. No TMDB types escape the adapter; no live-network test is required to commit.

### MM-04 - Matching Repository And Persistent Cache

**Scope:** Add a vendor-neutral repository over the provider/cache boundaries with verified-match, ambiguous, no-match, disabled, stale, and failure results. Implement tested matching and bounded cache policy. Inject storage; add a new migration only if necessary. Keep local movie mappings separate from imported catalog identity.

**Checks:** Remakes/same titles, translated titles, provider suffixes, no year, duplicate candidates, conflicting known IDs, match fingerprint changes, source/language isolation, persistent reopen, eviction/expiry, negative-cache policy, stale offline fallback, deduplication, deleted/reordered catalog items, and storage shutdown/failure. Use real SQLite fixtures for cache/mapping tests and fakes for provider calls.

**Done:** Matching and cached metadata survive restart without overwriting local content or causing network calls for unrelated items. Split cache schema and repository behavior into separately numbered commits first if this scope proves too large.

### MM-05 - Injected Movie Details State

**Scope:** Add feature-local state consuming only MovieMetadataRepository and wire it through existing app composition/scope patterns. Load once per selected movie/language, retaining local data immediately. Guard route/item/playlist changes and disposal; expose cached results without requiring a new state-management package.

**Checks:** Delayed results for the previous movie, switching playlists/language, disposal, concurrent views, refresh/retry, missing configuration, cached versus fresh data, and metadata failure while Play remains functional. Live and episode Details must not trigger movie lookups.

**Done:** Movie Details can observe typed metadata state through an injected boundary; route behavior, player commands, and library progress remain unchanged. Add architecture tests that forbid vendor/HTTP/SQL imports in Details UI/state.

### MM-06 - Enriched Movie Details Presentation

**Scope:** Compose optional overview, poster/backdrop, release year, genres, runtime, and source-labeled rating into DE-03's layout. Apply the approved metadata precedence; preserve local title/stream identity and local fallback. Add approved TMDB About/Credits attribution/assets in the same deliverable. No new Play/Resume behavior, rating sort, cast carousel, or recommendation section.

**Checks:** Long localized text, sparse data, missing artwork, no-match/ambiguous/disabled/error states, stale offline data, rating scale and zero-vote hiding, safe retry, 2.0 text scale, remote focus, attribution reachability, and Play activation exactly once while metadata loads/fails. Metadata arrival must not steal focus or reset scroll.

**Done:** Movie Details is richer when a trustworthy match exists and fully usable without it. All displayed values have provenance, required attribution is reachable, and player duration/progress does not use metadata runtime.

### MM-07 - Metadata Integration Checkpoint

**Scope:** Verify selected movie -> lookup -> cache -> Details -> playback -> Back across restarts and failures. Use fake HTTP and real SQLite fixtures; compare DE-03 local-only and enriched screenshots. Record optional manual configured-TMDB smoke checks without tokens or URLs containing secrets.

**Checks:** Offline startup, service outage, credential rejection, rate limits, wrong/ambiguous match, playlist refresh/reorder, language change, catalog item removal, no network lookup during tile focus/import, and attribution. Demonstrate substituting the fake provider through composition with unchanged Details code.

**Done:** Full analyzer/tests and architecture checks pass; enrichment remains optional, bounded, vendor-isolated, and independent of continuity. Record native checks as verified or pending rather than inferring them from adapter tests.

## 8. Separate Follow-Up Tracks

These are intentionally not implementation-ready steps. Before starting a track, create a dedicated plan with decision gates, verified APIs, and separate testable commits. None is required for DE-09 or DE-18.

| Track | Required Decision/Discovery | Expected Commit Sequence |
|-------|-----------------------------|--------------------------|
| EPG and now/next | Guide source, refresh/retention, timezone/DST, channel-ID matching, ambiguous/unmatched behavior, licensing and secret handling. | Source/matching decision; bounded guide contract + fixtures; append-only cache schema; cancellable ingest; now/next queries; channel context UI; virtualized time grid; hardware QA. No preview playback implied. |
| Live zapping | Resolve D-8 activation policy; specify selected-group order, wrap/end behavior, channel key handling versus control focus, and buffering cancellation. | Policy; bounded adjacent-channel lookup; session replacement commands; overlay UI; remote/race tests. Root key mappings alone do not implement zapping. |
| Favorites/recent channels | Initial library contracts exist; decide entry points, hidden-group behavior, visibility/preferences, and mutation feedback. | Policy; bounded lookup/state; Details favorite command; Home/live favorites slice; playlist/profile and navigation tests. |
| Catalog-wide/series metadata and rating sorting | Movie Details provider work is scoped in section 7; broader enrichment needs its own provider contracts, matching, request budget, licensing and projection policy. | Approve broader scope; bounded enrichment queue; safe summary projection; explicit sort controls; manual match correction; provider/playlist isolation tests. Do not turn selected-movie lookup into a full-playlist crawl. |
| Integrated series detail | Decide whether/how season tabs replace current nested routes and preserve deep-link/Back context. | Route decision; selected-season state; combined detail UI; bounded next-episode lookup; navigation regression tests. Autoplay remains separate. |
| Next-episode autoplay | Opt-in/default, countdown cancellation, completion detection, missing episodes, ordering and background behavior. | Policy; successor query; guarded continuation command; cancelable overlay; lifecycle/race/hardware tests. |
| Mini-player/system PiP | Revisit D-7 explicitly, including route/session lifetime, close/Back, audio ownership, platform support, and Android lifecycle. | Decision; backend capability spike; shell session ownership; in-app mini-player; Android integration; single-stream and lifecycle QA. Do not just reparent a video widget. |
| Theme/branding | Resolve D-9, including name/fonts, light theme, persistence, and contrast. | Visual decision; semantic palette; theme preference; screen verification. Do not combine with layout commits. |
| Voice/search suggestions | Supported platforms/APIs, permissions, privacy, history retention and fallback typing. | Decision/spike; injected capability contract; recents/suggestions data; input UI; accessibility/platform tests. |
| Sports/recommendations | Trusted metadata, relevance controls, provenance, privacy and confidence/no-data presentation. | Decision; bounded matching/ranking; explanatory result model; optional Home section; false-match and no-data tests. |

## 9. Verification And Evidence

Every code commit runs its focused tests first, then:

```powershell
flutter analyze
flutter test
```

Use the selected Flutter SDK. Do not substitute `dart run` for Flutter widget/native-assets tests. If the full checks fail for unrelated existing issues, report the exact baseline and stop claiming the step is green; do not repair unrelated modules in the same commit.

For scoped widget tests, use `flutter test <test-file>` or editor test tooling. Run the architecture rules after changes crossing feature/data/platform interfaces. Read relevant local skills: responsive layout for presentation changes, Dart unit tests for policy/controllers, mocks only when actually needed, and static analysis for Dart verification.

Apply the full [Design Contract Matrix](design-guidelines.md#verification-matrix) to the touched surface. At minimum cover compact portrait, compact short landscape, medium, expanded desktop, and remote-first TV viewports; pointer/touch and keyboard/remote; text scale 1.0/2.0; reduced motion; safe areas; keyboard insets where input exists.

Each UI step includes loading/empty/error, absent/failed artwork, long titles, target-size/semantics checks, stable geometry, and key-event activation/Back tests where applicable. Capture deterministic after screenshots for direct comparison with DE-01. Browser screenshots of the concept do not verify Flutter rendering.

Native checks are separate: Android phone, Android TV, Windows, and LG webOS. Record actual viewport/scale, remote key mapping, focus visibility, distant readability, stream/backend, and outcome without URLs. Use supported WSL/Linux tooling for webOS builds. Pending native checks remain pending even when widget tests pass.

### Per-Step Evidence Template

Append one entry when completing a step:

```text
Step:
Date:
Commit (if explicitly requested and created):
Changed owners:
Focused checks and result:
flutter analyze result:
flutter test result:
Screenshot paths and reviewed viewports:
Native checks: verified / pending, with target and outcome:
Approved decision reference (gated steps):
Known limitations or follow-up:
```

## 10. Milestone Acceptance

**Presentation milestone, DE-09:** Existing browsing/playback/navigation continues working; Details is visual and adaptive; Live is channel-oriented; movie/series/episode presentation fits the content; focus context is lightweight; no whole-catalog UI loading or new behavior is hidden inside a reskin.

**Continuity milestone, DE-18:** Approved genuine progress survives restart/refresh, explicit resume is session-safe, Home offers a bounded continuation slice, and episodes show real viewing states. Single-stream ownership, stop-on-exit, security, paging, and cross-device input contracts remain intact.

**Movie metadata milestone, MM-07:** Movie Details consumes a common MovieMetadataProvider through matching/cache and feature-state boundaries, with TMDB as an interchangeable adapter. Trustworthy metadata and attribution are displayed when available; offline, disabled, ambiguous, and failed lookup preserve local browsing/playback. No vendor type or credential leaks into UI or catalog identity.

Neither milestone claims delivery of the entire concept. The useful outcome is a better application at each commit boundary, not visual parity with static sample screens.