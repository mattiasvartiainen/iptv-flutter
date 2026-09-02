# Platform Facts & Decisions Log

This file captures what has been verified about the `flutter-webos` platform and the engineering
decisions that must be made before or during the first build. Update an entry's status when it is
resolved, and reflect the resolution in the affected document.

Legend: ✅ resolved · 🔶 open · 🔬 needs a hardware/tooling spike

## Verified facts

- **Target baseline:** webOS 26 "Re:New" or newer. ✅
- **Build host:** Ubuntu 22.04 / 24.04 / 26.04 only; Windows host must use WSL2 or a Docker DevContainer. ✅
- **Toolchain:** `flutter-webos` SDK (Flutter 3.38.10 / Dart 3.10.9), webOS NDK, `ares` CLI ≥ 3.2.4. ✅
- **Playback plugins:** `video_player_webos` (inline HLS via the webOS media pipeline), `video_player_drm` (DRM). No custom HLS engine. ✅
- **Persistence plugins:** `shared_preferences_webos`, `flutter_secure_storage_webos`, `sqflite_webos`, `path_provider_webos`. ✅
- **Network/system plugins:** `connectivity_plus_webos`, `webos_service_bridge` (Luna Service, ACG-gated). ✅
- **Remote input:** no dedicated remote-key plugin; handled via Flutter focus + hardware key events. ✅

## Decisions to address

### D1 — HLS playback validation 🔬 (highest risk)
Keep the app-level playback interface stable and run Phase 0 validation in two steps:
1) Linux/desktop spike with the current `media_kit` adapter to validate UI states and telemetry.
2) webOS hardware spike with the `video_player_webos` adapter for real compatibility.
Run 3–4 representative streams (different codecs, live vs VOD), record startup latency/buffering
behavior/outcome, and decide whether `video_player_drm` is required.
- Affects: [architecture.md](architecture.md) §8, [implementation-plan.md](implementation-plan.md) Phase 0/6.

### D2 — Desktop playback adapter ✅
`video_player_webos` does not run on the Linux desktop target. Keep a desktop adapter behind the same
interface for Linux/Windows development. Current implementation uses `media_kit`; only revisit this
choice if concrete stream compatibility failures appear. Reserve `vlc` as a future backend option
without adding it to the current implementation.
- Affects: [architecture.md](architecture.md) §8.

### D3 — Credential storage split 🔶
Playlist URL (contains credentials) → `flutter_secure_storage_webos`. Settings and last navigation
context → `shared_preferences_webos`. Never log or render the credential-bearing URL.
- Affects: [architecture.md](architecture.md) §7, PRD non-functional requirements.

### D4 — Catalog cache strategy 🔶
Decide whether to re-parse the playlist on every launch or cache the normalized catalog in
`sqflite_webos`. Drives the data model and the startup refresh-vs-last-good behavior (Phase 7).
- Affects: [architecture.md](architecture.md) §4/§7, [implementation-plan.md](implementation-plan.md) Phase 7.

### D5 — Off-main-thread parsing 🔶
Run M3U fetch + parse on an `Isolate` (`compute`) so large playlists never block the UI. The
playlist service API must be async and cancellable.
- Affects: [architecture.md](architecture.md) §5.

### D6 — Remote key & focus validation 🔬
Confirm webOS remote keys (arrows, OK, Back, color keys, media keys) map into Flutter
`HardwareKeyboard`/focus on hardware. Build focus on `FocusTraversalGroup` + `Shortcuts`/`Actions`.
- Affects: [architecture.md](architecture.md) §9, [implementation-plan.md](implementation-plan.md) Phase 0/2.

### D7 — State management approach ✅
Use a single injectable `ChangeNotifier` application controller for the MVP.
Reconsider a state-management package only if the app grows beyond this simple state model.

### D8 — Relaunch policy vs manifest 🔶
`webos/meta/appinfo.json` currently sets `handlesRelaunch: true`, but the architecture recommends the
simplest relaunch config unless there is a concrete background-before-foreground need. Decide the
policy and align the manifest.
- Affects: [architecture.md](architecture.md) §10, `webos/meta/appinfo.json`.

### D9 — App manifest identity 🔶
Replace the scaffold defaults in `webos/meta/appinfo.json` (`id: com.flutter.app.iptv-flutter`,
vendor "LG Electronics", title "Flutter iptv_flutter app") and add a real icon before packaging.
- Affects: `webos/meta/appinfo.json`.

### D10 — Rendering backend 🔶
Default is Skia. Evaluate enabling Impeller via `webos/meta/flutter-conf.json` as a performance lever
during on-device testing; not a day-one change.
- Affects: `webos/meta/flutter-conf.json`.

