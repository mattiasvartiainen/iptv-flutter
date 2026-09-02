# IPTV webOS Documentation

This directory contains the product and engineering decisions needed to start implementation of the LG webOS IPTV player.

## Read in this order

1. [`product-requirements.md`](product-requirements.md) — goals, scope, user stories, and acceptance criteria.
2. [`architecture.md`](architecture.md) — proposed app boundaries, data model, playback abstraction, and UI principles.
3. [`implementation-plan.md`](implementation-plan.md) — sequenced work packages for the first implementation.
4. [`research.md`](research.md) — webOS delivery constraints and reusable IPTV UI patterns.
5. [`decisions.md`](decisions.md) — verified platform facts and the open decisions to resolve before/while building.
6. [`agent-handoff.md`](agent-handoff.md) — concrete instructions for the next coding agent.

## Current product decisions

- Target **webOS 26 "Re:New" or newer only** (confirmed). Older webOS versions are unsupported by the `flutter-webos` toolchain and are out of scope.
- Development host must be **Ubuntu 22.04 / 24.04 / 26.04**. On Windows, use WSL2 or a Docker DevContainer.
- Use a Flutter/Dart application built with the official `flutter-webos` SDK.
- Accept an M3U/M3U8 playlist URL; credentials are contained in the URL.
- Support Live TV and Movies/VOD in the first product slice.
- Prioritize common HLS streams; broaden playback support later.
- Optimize for the TV remote, visible focus, and ten-foot viewing distance.
- Store playlists and settings locally on the TV.
- Keep the UI shell component-based so layouts can be changed without rewriting domain logic.
- First milestone: install → add playlist → browse channels → play a stream.

## Documentation rule

When implementation changes a product decision, update the relevant document in the same change. Keep this directory decision-oriented; do not turn it into a duplicate of source-code comments.
