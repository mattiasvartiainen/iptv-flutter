# High-Level Implementation Plan

## Phase 0 — Confirm the hardware baseline

### Deliverables

- Target baseline is confirmed: **webOS 26 "Re:New" or newer**. Record the exact tested TV model and firmware version.
- Stand up the **Ubuntu (native or WSL2/DevContainer)** toolchain: `flutter-webos` SDK, webOS NDK, `ares` CLI; `flutter-webos doctor -v` shows all required items green.
- Enable Developer Mode + Key Server on the TV and register it as a custom device; confirm `flutter-webos devices` sees it.
- Confirm the exact package/install/launch workflow (`flutter-webos build webos` / `run -d <device>`), including Developer Mode session expiry.
- **HLS playback spike (highest risk):** play 3–4 representative streams (different codecs, live vs VOD) on hardware via `video_player_webos`; record which formats work. Decide whether `video_player_drm` is needed.
- **Remote/focus spike:** verify webOS remote keys (arrows, OK, Back, color keys, media keys) map into Flutter `HardwareKeyboard`/focus on hardware.
- Confirm lifecycle behavior for launch, relaunch, Home/Recents visibility changes, Back, and app close.

### Exit criteria

An empty hello-world webOS package installs and launches on the target TV, a representative HLS stream is confirmed playable on hardware, and remote key handling is confirmed usable.

## Phase 1 — Scaffold the installable app

### Deliverables

- Create the Flutter app structure, `webos/meta/appinfo.json`, Dart entry point, Flutter theme, and app assets.
- Add a minimal screen shell with shared layout tokens.
- Add a development fixture mode so UI can be built without a live provider.
- Add package/install/launch scripts or a documented command sequence.
- Add lifecycle event handlers and a single startup/resume coordinator.

### Exit criteria

The app launches into a stable empty/setup screen and can be rebuilt without manual file edits.

## Phase 2 — Build the remote-first UI foundation

### Deliverables

- Implement view mounting and application state ownership.
- Implement deterministic navigation stack and Back handling.
- Implement launch/relaunch/visibility handling without duplicate initialization.
- Implement reusable focusable controls, focus styling, and directional navigation.
- Implement loading, empty, error, and confirmation surfaces.
- Establish a component shell that can swap row/grid/list layouts.

### Exit criteria

Fixture content can be browsed entirely with the remote, and focus remains visible after every view transition.

## Phase 3 — Implement playlist input and persistence

### Deliverables

- Build setup/settings screens for a playlist URL.
- Validate and normalize input.
- Persist the URL and versioned settings locally.
- Add safe replace, refresh, remove, and retry flows.
- Ensure credential-bearing URLs are not unnecessarily rendered in logs or UI.

### Exit criteria

A user can enter a URL on the TV, save it, restart the app, and see the saved configuration.

## Phase 4 — Implement the M3U/M3U8 catalog pipeline

### Deliverables

- Implement fetch with explicit timeout and cancellation behavior.
- Parse standard M3U records and preserve useful `EXTINF` metadata.
- Normalize records to the internal content model.
- Add Live TV/VOD classification and deterministic fallback behavior.
- Build groups, counts, and a normalized search index.
- Add unit tests using representative fixture playlists, including malformed metadata.

### Exit criteria

Known fixture playlists produce stable catalog snapshots, and failure cases render actionable UI states.

## Phase 5 — Add browsing, search, and details

### Deliverables

- Build Home with Live TV, Movies/VOD, Search, and Settings destinations.
- Build group navigation and content list/grid variants.
- Build remote-friendly search input and results.
- Build details view with logo/poster fallback behavior and play action.
- Test both small and large fixture catalogs.

### Exit criteria

A user can locate a known channel or movie from Home using groups or search and open its details.

## Phase 6 — Add HLS playback

### Deliverables

- Implement playback service and native media adapter.
- Add player screen, loading state, basic controls, and Back behavior.
- Handle unsupported, unavailable, timeout, and retry states.
- Test several representative HLS streams on real target hardware.
- Keep player integration isolated so a later webOS-specific adapter can replace it.

### Exit criteria

A supported HLS stream starts from a catalog item, can be exited with the remote, and failures return the user to a usable state.

## Phase 7 — Integrate persistence and startup behavior

### Deliverables

- Decide whether startup refreshes automatically or uses the last successful catalog first.
- Restore playlist/settings safely.
- Preserve useful browse context without creating confusing stale states.
- Add storage migration/version handling.

### Exit criteria

Restarting the app produces predictable behavior with valid, invalid, unavailable, and removed playlists.

## Phase 8 — Hardware QA and packaging

### Deliverables

- Test install, launch, update/reinstall, and removal.
- Test relaunch, Home/Recents return, visibility suspension, and platform app close behavior.
- Test remote navigation from every screen.
- Test network loss, empty playlists, malformed entries, large catalogs, and playback failures.
- Check performance, memory, focus visibility, text clipping, and ten-foot readability.
- Create a release checklist and package naming/versioning convention.

### Exit criteria

The MVP acceptance criteria in `product-requirements.md` pass on the target TV, with known limitations documented.

## Suggested work order inside each phase

1. Define or update a small fixture and acceptance scenario.
2. Implement the domain/service boundary.
3. Implement the simplest UI consuming that boundary.
4. Test with fixture data using the Linux desktop Flutter target.
5. Package and test on the TV.
6. Record deviations and update docs.

## Definition of done for MVP

- Requirements and known limitations are documented.
- The app installs and launches on the chosen recent LG TV target.
- A playlist URL can be added, persisted, refreshed, and removed.
- Live TV and Movies/VOD are browsable when supplied by the playlist.
- Search and remote navigation work across the main catalog flows.
- At least one supported HLS stream plays on hardware.
- Failure states are actionable and do not strand the user.
- No credentials are committed to the repository or emitted in normal logs.

