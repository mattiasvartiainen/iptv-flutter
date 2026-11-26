# Architecture Notes

> **Current architecture and intent (updated 2026-11-26).** Source, tests and
> migrations establish implemented behavior. [Architecture tests](../test/architecture/architecture_rules_test.dart)
> enforce boundaries; [work packages](architecture-code-improvements.md) track
> completed versus planned work. [Decisions](decisions.md) reserve human choices.
> Older scaffold plans and audit snapshots are identified in the [docs index](README.md).

## 1. Guiding principle

Separate product behavior from presentation. The first release should make it cheap to replace a row-based catalog with a grid, hero layout, or compact TV guide without changing playlist parsing or playback.

## 2. Layers and ownership

```text
main.dart -> PlatformProfile -> AppDependencies
                              | constructs/owns injected services + controllers
                              v
IptvApp / AppShell -> AppScope -> features + shared UI
                                | commands / narrow state listeners
                                v
feature/cross-feature controllers -> service interfaces
                                    | injected implementations
                                    v
catalog/import/metadata/storage services + playback session/adapters
```

Keep the layers lightweight. This is not a requirement to introduce a framework or dependency container.
`AppDependencies` is the existing composition root. Profiles select native
implementations; shared UI selects geometry from constraints and input behavior
from injected capabilities. UI does not construct native media/database/HTTP
implementations. Imports and local re-exports are checked by the architecture
tests, including conditional branches. The checks are source-level guards,
not a complete type-resolved dependency graph.

## 3. Current source layout

```text
lib/
  main.dart
  app.dart
  app/              composition, startup, shortcuts and typed navigation
  platform/         platform identity, profiles, flags and native selection
  features/         screens, focused widgets and feature controllers
  ui/               shared widgets, formatters and theme
  models/
  state/            cross-feature state and paged collections
  services/
    playlist/
    catalog/
    search/
    playback/
    settings/
  platform/
assets/
test/
webos/
  meta/appinfo.json
```

Services do not import screen-specific code or Material widgets. The pragmatic
`PlaybackAdapter.buildVideoView()` contract can expose a Flutter `Widget` for
native surfaces without exposing the native player implementation. The
`playback_adapter.dart` compatibility barrel exports contracts/errors only;
profiles/tests import native/fake implementations explicitly.

## 4. Internal content model

`ContentItem` carries the selected playable item's imported data:

```text
{
  id,
  type: 'live' | 'vod',
  title,
  streamUrl,
  group,
  logoUrl,
  posterUrl,
  description,
  metadata,
  sourceIndex,
  catalogPlaylistId,
  catalogItemKey
}
```

`metadata` may retain provider-specific attributes without forcing the UI model to understand every provider extension. `id` must be deterministic for a playlist item and must not expose credentials in rendered text or logs.
Paged catalog projections represent groups, series, seasons and episodes.
Descriptive enrichment is separate from playable identity and local streams.

## 5. Playlist pipeline

```text
Configured playlist / verified source
  → worker download + incremental parse/normalize
  → bounded batches with backpressure
  → short, import-session-scoped SQLite staging transactions
  → set-based reconciliation + search indexing
  → committed catalog revision
  → paged queries through CatalogQueryService
```

The production v9 pipeline downloads/parses in a worker isolate; the application
owns database writes, without holding a transaction during network download.
Cancellation/recovery use durable import sessions. Keep the last successful
catalog visible until reconciliation commits. Never load the full production
playlist into UI state or fetch descriptive movie/series metadata during import.
The [catalog design](catalog-import-and-browsing-redesign.md) and
[v9 implementation sequence](implementation-steps-2026-09-28.md) document the
pipeline lineage; later append-only migrations extend it.

## 6. State and navigation

Ownership is split, not a single god controller:

- `NavigationController`: typed `AppRoute` stack, rendered by `Navigator.pages`.
- `AppController`: thin cross-feature command facade.
- `PlaylistsController`: configured sources, refresh/cancellation and friendly errors.
- `CatalogViewState` / `PagedCollection`: bounded browsing windows and stale-query guards.
- `AppPreferencesController`: settings state.
- Feature controllers: search and selected-movie/series enrichment/selection.
- `PlayerController` / `PlaybackSession`: latest-request-wins playback/lifecycle.
- `TelemetryController`: opt-in diagnostics configuration and delivery status.

Flutter widgets should be repeatable from state. A screen may own ephemeral widget state, but it should not own the application source of truth.

### Content-selection flows (2026-11-26)

The [Xtream and metadata plan](xtream-and-metadata-implementation-plan.md#9-details-and-interaction)
defines the requested flows. Movie and Series details and direct Live
activation are implemented:

- Live channel activation opens the existing player directly, without Details.
  Catalog, Home and Search share a type-aware, guarded selected-item lookup.
  Opening the Live section does not autoplay; player Back returns to the
  originating route without adding a channel information screen.
- Movies retain Details and Play, with immediate local data and on-demand,
  provider-first metadata through an injected provider-neutral repository.
  The selected-movie Xtream provider and scoped v14 metadata cache are implemented.
- Series open one overview with artwork/information and seasons. Selecting a
  season loads paged episodes below on the same screen, without another route.
  `SeriesDetailsRoute` and its feature-local controller own transient selection.
  Verified Xtream sources use category-filtered discovery and validate every
  local episode against the selected provider show's membership. A separate
  v15 cache stores sanitized show information, isolated by playlist/revision/
  locale; metadata never replaces local streams or introduces playable episodes.
  The append-only v16 migration indexes cache foreign-key lookups and scopes
  invalidation to the affected playlist/show. Live/movie writes and unchanged
  episode/ordinal updates preserve Series metadata; no enrichment is fetched
  during playlist imports.
  Append-only v17 adds an episode-only `(series_key, id)` index for keyset
  membership pages. Every member is checked once inside the cache transaction;
  the transaction still prevents storing metadata for a concurrently changed show.
- Plain M3U/M3U8 remains supported. API/external metadata is optional; unavailable
  enrichment never blocks local browsing or playback.

Use the existing typed navigation, constructor injection and `ChangeNotifier`
patterns. Keep episode availability and playback identity in the catalog, not
in descriptive metadata. No additional state-management framework is required.
Shared asynchronous item activation deduplicates repeated OK and rejects lookup
completions after navigation or catalog rebinding. Lookup failures have safe
logging and a focus-preserving shell notification; they do not open Details.
Xtream responses use capped typed byte storage and transferable isolate input.
Before JSON allocation, a shared scanner bounds nesting, value/key count and
individual string size. Oversized/complex responses fail explicitly without
blocking local playback. Invalid movie cache rows are removed so Retry can fetch
fresh metadata.

## 7. Persistence

Production composition injects database/settings/catalog and secret-store
interfaces. Split persistence by sensitivity:

- **Credential-bearing playlist URLs:** behind `PlaylistSecretStore`, selected
  by the platform profile. Never put them in logs, UI, analytics or plaintext preferences.
- **Settings/source configuration:** `SettingsRepository`; production uses the
  injected SQLite database and secret store. Separate telemetry settings also
  use an injected store with secrets kept behind the secret-store interface.
- **Catalog, user library and metadata caches:** SQLite repositories; browsing
  stays paged. Schema changes are append-only migrations, never edits to an old
  migration. WAL stays disabled due to measured import regression.
- **Database factory and directory resolution:** selected inside platform profiles.

Treat stored data as untrusted and version the storage schema. Never assume a stored playlist remains valid; validate and refresh it at startup according to the chosen product behavior.
The executable schema record is [storage migrations](../lib/services/storage/storage_migrations.dart)
and the [persisted migration matrix](../test/services/storage/database_migrations_test.dart).
Historical SQL in `database-schema.md` / `schema_v1.sql` is reference material,
not a schema to apply.

## 8. Playback abstraction

`PlayerController` owns a `PlaybackSession`, which wraps the injected
`PlaybackAdapter`. The contract exposes state/events, load/play/pause/stop,
seek/volume, capabilities, a video surface and awaitable disposal. Optional
track commands use `PlaybackTrackAdapter`; navigation Back belongs to the
controller, not the native backend.

Session guarantees:

- Each load, including a retry of the same item, replaces the logical session
  immediately. Obsolete completions, errors and detached-resource events cannot
  replace the latest state or stop its playback.
- Ordinary commands run serially. Replacement skips obsolete queued commands
  and drains commands already in flight before allocating the next resource.
  Stop may interrupt initialization, including an explicit stopped-item restart.
- Back/stop cancels initialization without waiting for an initialized event and
  prevents subsequent autoplay. Native cancellation must finish before a new
  resource loads. MediaKit opens without autoplay, then plays only if still
  current; video_player adapters detach and dispose cancelled controllers.
- Background Live stops and requires explicit restart. Playing VOD pauses and
  resumes only for the same session/item; already-paused VOD stays paused.
  Pending loads are cancelled. Opening while backgrounded stays stopped and
  requires explicit restart after foreground return.
- Disposal suppresses events synchronously and returns the same cleanup future
  on every call. `PlayerController.dispose()` remains synchronous for Flutter;
  `disposalComplete` exposes native cleanup to the composition root. Cleanup
  failures remain observable/logged, and other owned resources still release.
  No hard timeout is promised for an unresponsive native plugin.
- Current command failures reach the owner; obsolete failures are safely logged
  without changing the replacement session. Track completion means native
  request acceptance, not confirmation of the selected track.

Deterministic tests cover replacement/retry, command serialization, cancellation,
late errors, background/foreground, requested-item retention and disposal.
Mocked native interfaces cover MediaKit, Android video_player and LG
video_player_drm; they do not replace device/native-engine validation.

Capability flags describe fixed backend support, not current stream readiness,
track availability or codec compatibility. The session rejects unsupported
commands with `UnsupportedError` before invoking the backend; advertised track
support requires `PlaybackTrackAdapter`. UI still gates controls with both flags
and current media state. Play is independent of pause support. Volume is a
per-stream 0-100 percentage, not system volume; DRM remains unadvertised until
a licence/configuration flow is implemented.
An unsupported direct session call leaves its current playback unchanged;
selecting an unsupported item through the player stops previous output and
reports failure for the requested item rather than leaving the old video playing.

Adapters own video-widget identity for each native resource. Android and LG
cache a `PlaybackVideoSurface` that listens to native values for aspect ratio
while retaining its video child (invalid dimensions use 16:9). A disposed or
cancelled controller invalidates its surface; MediaKit can reuse its surviving
player/surface across loads. State changes signal availability/replacement.
The controller queries the current surface instead of caching the first widget,
so a stopped-item restart or same-session replacement cannot show an old view.

Native initialization failures use `PlaybackException`, carrying only a
`PlaybackErrorKind`, never the native message/URL. `playbackErrorKind` preserves
typed/configuration errors before falling back to the shared legacy-text mapper
for command/cleanup failures. Unsupported operations are not unsupported-media
errors. State events carry error kinds; the owner logs safe failures and the
error panel maps kinds to product text. Track/favourite failures remain nonfatal.

The dedicated webOS adapter wraps LG's separate `video_player_drm` API for ordinary streams and embedded audio/subtitle selection. Android retains standard `video_player`; desktop uses `media_kit` or the fake/fixture adapter. Playback rides the webOS media pipeline, so codec/variant support and transparent native-plane compositing must be validated on hardware (see [`decisions.md`](decisions.md)). Keep backend selection in `lib/platform` and expose unsupported LG volume/custom headers honestly.

Flutter webOS reports a Linux-like target platform, so platform selection must not rely on `defaultTargetPlatform` alone. Desktop runs use `media_kit`; webOS builds pass `--dart-define=IPTV_WEBOS=true` and use the webOS adapter. Desktop backend selection remains behind `IPTV_DESKTOP_BACKEND`, with `fake` and `media_kit` supported today; `vlc` is reserved for a future adapter and is not implemented yet.

`PlayerScreen` owns the only control overlay; MediaKit's default controls are
disabled. Tap/hover reveal controls without pausing; centre Play/Pause and Space
toggle playback. Remote OK reveals/focuses the centre control before activating
it. Playing controls hide after four idle seconds, but remain visible while
paused, focused, scrubbing or choosing a track. Hidden controls are excluded from
focus, semantics and pointer input. Visible Back exits immediately; Escape/system
Back close a chooser first, otherwise hide controls before exiting.

Player presentation lives in `lib/features/player/widgets/`: `PlayerControls`
composes the responsive overlay and controller command bindings; `PlayerHeader`
renders safe title/status/facts and favourite state; `PlayerSeekBar` renders the
owner-provided preview; `PlayerTrackDialog` and `PlayerErrorPanel` receive data
and callbacks without navigation or service dependencies. `PlayerScreen` retains
focus-node lifetime, auto-hide timers, input/Back policy, seek-preview state and
chooser session/focus restoration. Presentation widgets do not own playback
sessions or change native surface caching. Scoped `ValueListenable` listeners
are detached when their widgets are disposed.

`SelectedValueBuilder` compares immutable selected values before rebuilding.
The screen selects status/buffering/errors and current video-widget identity,
so same-session surface replacement still appears immediately. Controls select
status, duration and technical facts separately from position and volume.
Only the seek/time slice and opt-in diagnostics rebuild on position changes;
hidden position slices detach and read the latest state when revealed. Track
dialogs select only their track kind's list and confirmed selection, preserving
focus across position ticks and unrelated track-kind updates. Playback events
remain unthrottled and seek-preview ownership is unchanged.

Android reuses `PlaybackMediaInfo` while mapped dimensions are unchanged.
LG caches mapped tracks by the pinned plugin's native list identity and reuses
media info while mapped dimensions and selected audio index are unchanged.
Selection/dimension updates reuse the existing track lists; list replacements
remap only the changed kind. Credential-derived language-label filters are
prepared once per load and cleared with all metadata caches on resource disposal
or replacement. Native metadata remains unknown when unreported, including
LG subtitle confirmation. MediaKit already maps metadata only on metadata/track
events, not on position events. None of this runs during playlist import.

`PlayerLayout` owns the overlay breakpoint and compact/regular geometry.
`PlayerControls` resolves it from `LayoutBuilder` constraints; dialogs use their
available window height and text scaler for bounded lazy track lists. The
existing short-window breakpoint remains 500 logical pixels, independent of OS
and primary input. Layout policy has no playback/controller dependencies.

`PlayerTheme` is a `ThemeExtension` installed by `AppTheme.dark()`. It centralizes
video background, overlay foreground/secondary/warning colors, directional
scrims and the controls fade duration. Customize these with
`ThemeData.copyWith(extensions: [PlayerTheme(...)])` at the composition boundary
or an inherited `Theme`; keep other extensions when present. Material controls,
typography and focus rings still inherit the shared app theme, whose injected
input capabilities select 48/56-pixel command targets. Reduced motion disables
the fade, not the four-second auto-hide behavior; accessible navigation keeps
controls visible. Native-plane backends always retain a transparent video
background. Presentation updates do not load, stop or replace playback resources.
Android TV detection and new device-specific layouts remain separate work.

Playback state carries backend-neutral technical facts and track lists. Unknown
facts remain absent; source FPS is not a rendered-FPS counter, and audio sample
format/channel count are not guessed into codec or 5.1 labels. Absolute seek
commits once per pointer scrub; native video widgets retain identity across
position updates. Track/favourite failures are reported without stopping video.

Selected database items carry their stable playlist/item key into playback.
Favourites use the existing user-library table and injected interface, with
indexed single-item reads and captured write identity. No full favourite list,
new migration, metadata fetch or import-time work is introduced.

## 9. Remote and focus behavior

- Define a single focus-management strategy built on Flutter `FocusTraversalGroup`, `Shortcuts`, and `Actions`. There is no dedicated webOS remote-key plugin, so remote keys arrive as hardware key events that must be validated on real hardware (see [`decisions.md`](decisions.md)).
- Make focusable elements explicit.
- Preserve or restore focus after data loads and rerenders.
- Handle directional movement consistently with Flutter focus traversal; do not rely only on implicit focus order.
- Map Back/Escape to the Flutter navigation stack, not to arbitrary widget behavior.
- Keep focus styling in shared Flutter theme/widget tokens so UI experiments retain accessibility.

## 10. webOS lifecycle integration

Implemented playback visibility uses Flutter `AppLifecycleListener`, with the
session guarantees in section 8. Do not map web-app DOM `visibilitychange` /
`webkitvisibilitychange` events directly into this native Flutter app.
Native launch/relaunch parameter handling remains a separate platform/hardware
integration task; it is not implemented merely because an older plan lists
`webOSLaunch` or `webOSRelaunch`.

- `handlesRelaunch` policy is still reserved by D8 in [decisions](decisions.md).
  Do not change the manifest based on the old MVP recommendation alone.
- Do not depend on a termination callback; persist important mutations promptly.
- Keep internal Back/navigation separate from platform app-exit behavior.
- Validate foreground/background, native-plane rendering and real remote Back
  on LG hardware. Mocked interfaces and Windows builds are not that evidence.

New refresh/restore policy requires separately approved work; this documentation
does not authorize auto-refresh or change current playlist activation behavior.

## 11. Error taxonomy

Represent errors with user-safe categories rather than raw exceptions:

- invalid URL;
- network unavailable;
- access denied or authorization failure;
- playlist format invalid;
- playlist empty;
- media unsupported;
- media unavailable;
- storage unavailable.

Detailed diagnostics may be available in developer logs, but user-facing messages should not echo credentials or provider URLs unnecessarily.
