# Research and Platform Notes

## 0. Verified platform facts (checked 2026-09-02)

Confirmed against the current LG `flutter-webos` documentation and published plugin list:

- **Target baseline: webOS 26 "Re:New" or newer.** This is the app's confirmed minimum. The `flutter-webos` toolchain does not target older webOS versions.
- **Host OS: Ubuntu 22.04 / 24.04 / 26.04 only.** Windows/macOS are unsupported; use WSL2 or a Docker DevContainer. Developer Mode + Key Server must be enabled on the TV, and the TV registered as a custom device.
- **Toolchain:** `flutter-webos` SDK (Flutter 3.38.10 / Dart 3.10.9), webOS NDK, and `ares` CLI (>= 3.2.4). Build with `flutter-webos build webos --{debug|profile|release}`; deploy with `flutter-webos run -d <device>`. Output IPK: `build/webos/{arch}/{mode}/ipk/{id}_{version}_{arch}.ipk`.
- **Media:** `video_player_webos` provides inline HLS playback via the webOS media pipeline; `video_player_drm` covers DRM-protected streams. There is no custom HLS engine — codec/variant support is whatever the device pipeline provides and must be validated on hardware. `video_player_webos` does not run on the Linux desktop target.
- **Persistence:** `shared_preferences_webos`, `flutter_secure_storage_webos`, `sqflite_webos`, and `path_provider_webos` are available.
- **Networking / system:** `connectivity_plus_webos` for connectivity; `webos_service_bridge` for Luna Service calls (subject to ACG permissions declared in the app config).
- **Remote input:** no dedicated remote-key plugin is published. Remote handling relies on Flutter focus/`Shortcuts`/`Actions` plus hardware key events, which must be validated on real hardware.

These are starting facts; re-verify the installed SDK/NDK/firmware versions before the first hardware test.

## 1. webOS delivery pattern

The app should be treated as a Flutter application packaged for webOS, with generated webOS metadata (`webos/meta/appinfo.json`) and a webOS CLI workflow for packaging, installing, launching, and inspecting the app on a TV in Developer Mode. The implementation agent should verify the exact CLI commands and target-TV compatibility against the current LG webOS TV developer documentation before the first hardware test.

Relevant official references:

- LG webOS TV Developer site: `https://webostv.developer.lge.com/`
- webOS TV CLI documentation: `https://webostv.developer.lge.com/develop/tools/cli-installation`
- webOS TV app development documentation: `https://webostv.developer.lge.com/develop`

These links are starting points, not a substitute for validating the installed SDK version and current TV firmware.

The lifecycle guide is directly relevant to this app. Model cold launch, relaunch, foreground/background visibility, and termination separately. A relaunch may use webOSRelaunch instead of repeating initial launch work. Visibility changes can suspend the app, so pause or release nonessential work when hidden, restore focus and navigation when visible, and persist durable settings before suspension. The platform owns app closing; the app should not add a custom close button.

## 2. Existing IPTV-player patterns worth borrowing

Common patterns across IPTV and streaming applications:

- **Fast entry into content:** show Live TV and Movies/VOD as primary destinations instead of hiding them behind settings.
- **Group-first browsing:** provider groups/categories reduce the cost of navigating large playlists.
- **Persistent search:** search should be available from the home/catalog shell and return both live and VOD items.
- **Poster/logo-led scanning:** logos for channels and posters for movies improve recognition at ten-foot distance.
- **Player as a focused mode:** playback should minimize chrome, show controls only when requested, and make Back predictable.
- **Settings separate from consumption:** playlist management, refresh, and diagnostics belong in Settings rather than interrupting browsing.
- **Graceful degraded metadata:** playlists vary widely, so missing logos, groups, descriptions, and genres must not break the catalog.

## 3. UI experiments to support

Build the first shell so these alternatives can be tested with fixture data:

1. Horizontal content rows with a highlighted card.
2. Two-column or multi-column catalog grid.
3. Compact channel list with logo, title, group, and play affordance.
4. Search-first home layout for large catalogs.

The domain layer should expose the same `CatalogItem`, group, and search data to all variants.

## 4. Risks to validate early

- Playlist URLs may require redirects, unusual headers, or provider-specific behavior.
- M3U metadata conventions differ substantially between providers.
- Large playlists can make naive widget-tree rendering slow on TV hardware.
- HLS support and codec behavior can vary by webOS version and TV model.
- Remote key events and Flutter focus behavior need testing on real hardware, not only the Linux desktop target.
- Relaunch and visibility events can expose duplicate initialization, stale media state, or lost focus if they are not modeled explicitly.
- Recent webOS tooling and emulator availability may differ from older tutorials; keep the development workflow versioned and verified.
- Local storage limits and persistence behavior should be verified on the target TV.

## 5. Research policy for implementation

Before adding an external library or relying on a webOS API, consult the current primary documentation and record the decision in this file or the architecture notes. Prefer platform capabilities and small local utilities for the MVP.

