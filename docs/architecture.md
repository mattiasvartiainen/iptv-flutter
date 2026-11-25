# Architecture Notes

## 1. Guiding principle

Separate product behavior from presentation. The first release should make it cheap to replace a row-based catalog with a grid, hero layout, or compact TV guide without changing playlist parsing or playback.

## 2. Suggested layers

```text
webOS project metadata (`webos/meta/appinfo.json`)
        |
UI shell and view components
        |
Application state + navigation
        |
Domain services
  - playlist service
  - catalog service
  - search service
  - playback service
  - settings service
        |
Platform adapters
  - fetch/network
  - platform storage / persistence adapter
  - Flutter media adapter / webOS media APIs
```

Keep the layers lightweight. This is not a requirement to introduce a framework or dependency container.

## 3. Proposed source layout

```text
lib/
  main.dart
  app.dart
  models/
  state/
  navigation/
  screens/
  widgets/
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

The exact structure may be adjusted after the first scaffold, but services should not import screen-specific code.

## 4. Internal content model

Use a normalized item shape similar to:

```text
{
  id,
  type: 'live' | 'vod' | 'unknown',
  title,
  streamUrl,
  group,
  logoUrl,
  posterUrl,
  description,
  metadata,
  sourceIndex
}
```

`metadata` may retain provider-specific attributes without forcing the UI model to understand every provider extension. `id` must be deterministic for a playlist item and must not expose credentials in rendered text or logs.

## 5. Playlist pipeline

```text
URL input
  → validate and normalize
  → fetch text
  → parse M3U records
  → normalize metadata
  → classify Live/VOD
  → build groups and search index
  → publish catalog snapshot
  → persist playlist configuration
```

Run fetch + parse off the UI isolate (`compute`/`Isolate`) so large playlists do not freeze the main thread. The service API should therefore be async and cancellable. Only publish a new catalog after the pipeline succeeds. Retain the previous catalog until then so a transient refresh failure does not destroy a working setup.

## 6. State and navigation

Use one application state owner with explicit transitions. Avoid screen-local mutable state and event handlers that independently mutate application state.

Minimum state areas:

- `app`: startup and current screen.
- `playlist`: configured URL, loading status, last successful load, error.
- `catalog`: normalized items, groups, counts, loading status.
- `search`: query, active type, results.
- `player`: selected item, media status, error.
- `settings`: user preferences and UI experiment flags.

Flutter widgets should be repeatable from state. A screen may own ephemeral widget state, but it should not own the application source of truth.

### Planned content-selection flows (2026-11-25)

The [Xtream and metadata plan](xtream-and-metadata-implementation-plan.md#9-details-and-interaction)
defines the requested flows. Movie and Series details are implemented; direct
Live activation remains planned:

- Live channel activation opens the existing player directly, without Details.
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

Use a small persistence adapter backed by the verified webOS plugins for MVP local persistence. Store only what is needed, and split by sensitivity:

- **Playlist URL (contains credentials): `flutter_secure_storage_webos`.** Never write the credential-bearing URL to plain shared preferences, logs, or analytics.
- **User settings and last navigation context: `shared_preferences_webos`.**
- **Cached catalog (optional, for large playlists): `sqflite_webos`.** See the catalog-cache decision in [`decisions.md`](decisions.md).
- Use `path_provider_webos` for any file paths needed.

Treat stored data as untrusted and version the storage schema. Never assume a stored playlist remains valid; validate and refresh it at startup according to the chosen product behavior.

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
sessions, introduce new subscriptions or change native surface caching.

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

The app must model platform lifecycle explicitly rather than treating every entry as a cold start. Flutter lifecycle callbacks should be used for app visibility, with a small webOS platform adapter for launch/relaunch behavior:

- webOSLaunch: initialize the app and inspect launch parameters.
- webOSRelaunch: restore or update the existing app without duplicating expensive initialization; only use handlesRelaunch when there is a concrete background-before-foreground need.
- visibilitychange (and the backward-compatible webkit variant if required by the selected TV baseline): pause polling, abort nonessential work, and release or pause playback resources when hidden; restore state when visible.
- Termination: do not depend on a termination callback. Persist important settings at mutation time and when the app is backgrounded.
- Root Back/close behavior: do not implement a custom close button. Keep the app’s internal navigation stack separate from the platform’s app-exit behavior.

Recommended MVP policy: use the simplest relaunch configuration, restore the last stable UI state, do not auto-refresh while hidden, and refresh the playlist only from an explicit user action or a documented foreground-start policy.

## 10. Error taxonomy

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
