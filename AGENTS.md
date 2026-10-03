# Agent Guide

## Product
TV-first IPTV app targeting Android (phone and TV), Windows, and LG webOS. Linux desktop is for development/testing. Preserve the current architecture; do not introduce new state-management, DI, or model-generation packages without a concrete need.

## Start Here
- Before implementation, read [docs/architecture-code-improvements.md](docs/architecture-code-improvements.md) and choose one unblocked work package. Read its touched files and listed skills first.
- For Flutter or Dart work outside a listed work package, check `.agents/skills/` and read only the skill(s) relevant to the task before editing.
- Check [docs/decisions.md](docs/decisions.md) before making a choice reserved for a human. Record completed work in the plan's status table.
- Use [docs/architecture.md](docs/architecture.md) for current architecture intent and [docs/catalog-import-and-browsing-redesign.md](docs/catalog-import-and-browsing-redesign.md) plus [docs/implementation-steps-2026-09-28.md](docs/implementation-steps-2026-09-28.md) for the catalog v9 pipeline.

## Non-negotiable Rules
- Keep platform detection and platform-specific implementation selection inside `lib/platform/` (until that package exists, don't add new scattered platform checks). Shared UI chooses layouts from constraints and available input, not OS names.
- Keep UI independent of databases, HTTP clients, native media packages, and storage implementations. Depend on interfaces and inject dependencies.
- Keep catalog browsing paged through `CatalogQueryService`; never load a full production playlist into UI state.
- Add database changes as new append-only migrations; never edit an existing migration. WAL is intentionally disabled due to measured import regression.
- Every interactive TV control must be reachable and usable by remote/keyboard, with visible focus and working Back. Add key-event widget tests for navigation/focus changes.
- Never display or log credential-bearing playlist/stream URLs. Keep secrets behind `PlaylistSecretStore`.
- Preserve existing behavior unless the selected work package explicitly changes it. Avoid unrelated refactors.

## Verify
Run `flutter analyze` and `flutter test` for code changes. The baseline currently has 9 info-level analyzer findings; introduce no new findings, and don't claim the baseline is clean until WP-0.2 is complete. For webOS builds, use `tool/build-webos.sh` from the supported Linux/WSL/DevContainer environment; see the plan and repo docs for platform setup.

## Test/Toolchain Notes
- `testWidgets` uses FakeAsync: advance time with `tester.pump(duration)`; real delays/timers won't elapse on their own.
- Fire-and-forget database work must tolerate the database closing during test teardown.
- The import benchmark must be invoked with `flutter test test/benchmark/import_benchmark.dart`, not `dart run`.
- A killed native-assets test/benchmark process can leave `flutter_tester.exe`/`dart.exe` holding `build/native_assets`; see the cleanup command in [docs/architecture-code-improvements.md](docs/architecture-code-improvements.md).
