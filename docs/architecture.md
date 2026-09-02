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

## 7. Persistence

Use a small persistence adapter backed by the verified webOS plugins for MVP local persistence. Store only what is needed, and split by sensitivity:

- **Playlist URL (contains credentials): `flutter_secure_storage_webos`.** Never write the credential-bearing URL to plain shared preferences, logs, or analytics.
- **User settings and last navigation context: `shared_preferences_webos`.**
- **Cached catalog (optional, for large playlists): `sqflite_webos`.** See the catalog-cache decision in [`decisions.md`](decisions.md).
- Use `path_provider_webos` for any file paths needed.

Treat stored data as untrusted and version the storage schema. Never assume a stored playlist remains valid; validate and refresh it at startup according to the chosen product behavior.

## 8. Playback abstraction

Define a small interface before building the player UI:

```dart
load(item)
play()
pause()
stop()
back()
onStateChange(listener)
```

The webOS adapter wraps the `video_player` API with the `video_player_webos` implementation for supported HLS streams; use `video_player_drm` only if a target provider requires DRM. Playback rides the webOS media pipeline, so codec/variant support must be validated on hardware early (see [`decisions.md`](decisions.md)). Because `video_player_webos` does not run on the Linux desktop target, desktop development uses the shared `media_kit` adapter or the fake/fixture adapter. Keep the interface so a future desktop backend, including VLC/libVLC, can be added without changing screens or application state.

Flutter webOS reports a Linux-like target platform, so platform selection must not rely on `defaultTargetPlatform` alone. Desktop runs use `media_kit`; webOS builds pass `--dart-define=IPTV_WEBOS=true` and use the webOS adapter. Desktop backend selection remains behind `IPTV_DESKTOP_BACKEND`, with `fake` and `media_kit` supported today; `vlc` is reserved for a future adapter and is not implemented yet.

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



