# Coding Agent Handoff

## Mission

Build the first vertical slice of the IPTV webOS app: installable shell, playlist URL setup, M3U parsing, catalog browsing, and HLS playback.

## Start here

1. Read `docs/product-requirements.md` and treat the MVP boundary as authoritative.
2. Read `docs/architecture.md` before choosing source folders or adding dependencies.
3. Verify the webOS CLI and target-TV workflow using current LG documentation.
4. Scaffold Phase 1 before implementing provider-specific behavior.

## Implementation constraints

- Use Flutter/Dart with the official `flutter-webos` SDK. Keep domain services independent from Flutter widgets and platform adapters.
- Keep playlist parsing, catalog normalization, search, persistence, and playback behind small service interfaces.
- Use fixture playlists for development and tests; never commit a real credential-bearing provider URL.
- Keep all flows usable with a TV remote and visible focus.
- Keep UI layout choices replaceable.
- Do not add EPG, Xtream Codes, accounts, or series support in the MVP.

## First coding tasks

1. Create the webOS manifest and minimal launchable app.
2. Add a setup screen and shared focusable button/input styles.
3. Add application state and navigation transitions for Setup, Home, Catalog, Details, Player, and Settings.
4. Add a fixture-backed catalog screen to validate remote navigation before networking.
5. Add playlist URL persistence and M3U parsing.
6. Add a real HLS playback path and hardware test.

## Required tests

- Parser tests: standard entries, groups, logos, missing metadata, malformed records, empty playlist.
- State tests: first launch, successful load, failed load, replace playlist, remove playlist.
- Search tests: case-insensitive title/group matching and no results.
- Navigation tests: directional focus, Back behavior, and focus restoration after rendering.
- Hardware smoke test: install, launch, enter URL, browse, play, exit, relaunch.

## Do not infer silently

If a provider-specific playlist format, webOS API, media behavior, or minimum TV version is required, record the assumption and validate it against current primary documentation or hardware before making it a core dependency.

## Handoff output expected from the first implementation

- Working source scaffold.
- A documented local build/package/install command.
- Fixture playlist(s) without secrets.
- Tests for parser and core state transitions.
- Updated documentation for any changed decisions.
- A short list of hardware-specific limitations discovered during testing.
