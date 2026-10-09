# Cross-Device Design Contract

Updated: 2026-10-07. Applies to Batch 4 and subsequent UI work.

## Authority And Scope

- Product intent comes from [Product & UX Requirements](IPTV_App_Product_UX_Requirements.md).
- This document defines shared presentation, accessibility, and responsive implementation rules. The [architecture plan](architecture-code-improvements.md) defines delivery scope; [decisions](decisions.md) records approved behavior changes.
- The [Kanal concept](Kanal_%20IPTV%20TV%20experience%20concept.html) is a visual/interaction reference, not executable acceptance criteria. Its fixed 1280x720 stage, sample data, CSS sizes, and simulated interactions must not be copied as production constraints.
- Existing architecture, security, paging, and behavior-preservation rules still apply. A concept feature or a recommendation is not approval to change behavior. Resolve conflicting requirements explicitly before implementation.
- Use Material 3 and Flutter's standard controls as the implementation foundation, with app-owned semantic tokens and shared components. Do not introduce a separate design framework or state-management package.

## Space And Input Are Separate

Use available logical constraints for layout, injected capabilities for remote-first defaults, and current input/highlight mode for interaction feedback. Never select a layout by OS name or assume a wide window is a TV. Keyboard use alone does not imply distant viewing. Do not rebuild navigation geometry on every pointer/keyboard event.

Initial width classes are compact below 600, medium from 600 to 839, and expanded from 840 logical pixels. These are layout starting points, not device detection. Component constraints, height, text scaling, and safe areas may require a simpler composition. Retain the existing 1050-pixel catalog-sidebar threshold until the adaptive-shell package validates a replacement.

| Context | Composition | Interaction |
|---------|-------------|-------------|
| Compact | Bottom destinations for Home, Live, Movies, Series; accessible Search and Settings outside the destination bar; scrolling group controls; lists or bounded grids | Touch targets, safe-area and keyboard-inset handling; still fully usable with keyboard/remote |
| Medium | Rail when height/width permit, otherwise compact navigation; adaptive content columns | Touch, pointer, and keyboard supported together |
| Expanded | Labeled navigation rail; group sidebar when content constraints permit; organized multi-column content | Remote-first readable density or efficient pointer density, independently of width |

Navigation composition was approved under D-10 and implemented by WP-4.7. Keep all routes and commands reachable in every composition. Resizing must preserve route, selection, loaded page window, scroll context, and focus where the focused item still exists. Never shrink an entire TV canvas to fit a phone.

## Tokens And Theme

- Centralize semantic background/surface/on-surface, accent/on-accent, muted text, focus, error, warning, live, and watched roles. Components read roles, not palette literals. Focus and selection are distinct roles.
- Centralize discrete typography scales, page insets, section/grid gaps, control padding, tile aspect ratios/extents, radii, focus width, and motion duration. Use layout variants rather than viewport-proportional font sizes.
- Remote-first body text starts at 18 logical pixels and must be checked at actual viewing distance. Compact body text starts at 16. Respect Flutter text scaling; allow wrapping and growing controls rather than clipping essential labels. Compact panels use compact headings, not hero-sized type.
- Use shared radius tokens; retain current geometry during mechanical extraction. New repeated item cards normally use radii no larger than 8 unless the approved design explicitly requires otherwise. Do not turn page sections into nested cards.
- D-9 controls adoption of the concept palette and a light variant. Until resolved, WP-4.1 extracts the current dark palette without redesigning it. Theme selection/persistence is separate product work.

## Controls, Focus, And Motion

- Interactive touch targets are at least 48x48 logical pixels; remote-first targets start at 56x56. Keep hit areas distinct even when the icon is smaller. Validate these logical baselines against native TV render scale rather than treating the concept's CSS pixels as physical pixels.
- Traditional focus uses a clearly visible high-contrast ring; selected/current uses accent treatment and a semantic selected state. A control can be focused and selected simultaneously. Do not rely on color alone.
- Aim for text contrast of at least 4.5:1, or 3:1 for qualifying large text, and 3:1 for meaningful control boundaries/focus indicators against adjacent colors. Measure actual token combinations, including light-theme variants if approved.
- Use familiar icons for tools, labeled destinations, tooltips for unfamiliar icon commands, switches for binary settings, and menus/segmented controls for option sets. Supply accessible labels, roles, selected/disabled states, and logical reading order.
- Focus movement never starts playback or changes persisted selection. Activation invokes the existing command exactly once. Hover can expose lightweight information but cannot be the only way to reach it.
- Initial focus is set once after data arrives, not on every rebuild. Restore the previous item on Back; fall back to the nearest remaining item or primary action. First available content is the baseline until history-backed initial-focus behavior is separately delivered.
- Back first dismisses the topmost modal or locally handled transient UI, then pops one route. Root exit policy is unchanged. Player overlay handling is scoped to WP-4.5; leaving the player still stops playback until D-7 and its follow-up implementation are complete.
- Small focus emphasis must not resize grid tracks, clip content, cover neighbors, or move hit targets. Honor reduced motion; a ring must remain sufficient without animation. Avoid continuous decorative animations.

## Content And States

- Use available artwork with stable aspect ratios, bounded image decoding/cache policy, and an accessible fallback for missing/failed images. Do not fabricate posters, ratings, progress, guide data, or recommendations.
- Hide unavailable optional metadata rather than displaying false zero values. Essential titles remain readable, with wrapping or deliberate bounded truncation and an accessible full label.
- Loading, empty, error/retry, buffering, disabled, selected, focused, and refresh-failed-with-cache states must be distinguishable. Preserve cached content when existing behavior does; do not replace it with a blank loading screen.
- Show user-safe errors, never raw exceptions or credential-bearing URLs. Keep catalog data paged; richer UI is not permission to load whole playlists.
- Do not add instructional or diagnostic copy from the HTML concept to production screens. Diagnostics remain opt-in and redacted.

## Verification Matrix

Each touched UI package adds scoped tests immediately; WP-4.6 expands coverage rather than postponing it.

- Compact portrait: 360x800 and 390x844, touch and keyboard, safe areas, keyboard open, text scaling at 1.0 and 2.0.
- Compact landscape/short window: 800x360; medium: 800x1000; expanded desktop: 1440x900, including resizing across breakpoints.
- Remote-first: 1280x720 and 1920x1080 logical test viewports, D-pad/Select/Enter/Back, visible focus and restoration. These tests do not certify native device scaling.
- Test text/controls for overflow, stable tile geometry, missing artwork, loading/empty/error states, reduced motion, semantics, target sizes, and focus distinct from selection.
- Capture representative screenshots or goldens for layout/visual review. Use widget tests for Flutter rendering; browser checks of the HTML prototype do not validate the app.
- Record manual Android phone, Android TV, Windows, and LG webOS checks separately, including actual viewport/scale, key mapping, distant readability, and Back. Hardware checks can remain pending but must not be reported as verified.

## Deferred Concept Features

The following require separately scoped product work and are not implied by Batch 4: mini player and Android system picture-in-picture; EPG/now-next and live preview; quality-variant folding; rating enrichment/sorting; history-backed Home/resume/favorites; next-episode autoplay; sports/recommendations; voice/suggestions/recent searches; subtitle/audio preference UI; theme selection and branding changes.

Preserve the current All-group default until D-8 is resolved and a behavioral package implements the change. Preserve current activation destinations; the concept's one-press playback examples are not authorization to bypass Details/Resume flows.