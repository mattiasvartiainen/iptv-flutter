# Cross-Device Design Contract

**Updated:** 2026-10-16

**Applies to:** Batch 4 and subsequent UI work

Read this contract before changing interactive UI. For each touched journey, define traversal and
boundary behavior, implement it using shared Flutter controls, and add key-event and semantics
checks before reporting completion. Record native hardware checks separately from automated tests.

## 1. Authority And Scope

- Product intent comes from [Product & UX Requirements](IPTV_App_Product_UX_Requirements.md). The [architecture plan](architecture-code-improvements.md) defines delivery scope and [decisions](decisions.md) records approved behavior changes.
- Source code, tests, and platform configuration establish current behavior; this document defines required design outcomes, not proof that every screen already meets them.
- The [Kanal concept](Kanal_%20IPTV%20TV%20experience%20concept.html) is a visual reference, not executable acceptance criteria. Do not copy its fixed stage, sample data, or CSS sizes into production constraints.
- Preserve architecture, credential protection, paged browsing, and existing activation destinations. Use Material 3, Flutter standard controls, shared tokens, and existing state management.

- Keyboard, remote-control, pointer, touch, and assistive-technology interaction are part of the design contract, not optional platform enhancements.
- Every primary user journey and every essential action must be usable without a mouse or touch screen. Users must be able to navigate and operate the application using only a keyboard or a supported TV remote.
- Implement shared interaction behavior through Flutter's standard focus, keyboard, semantics, and control APIs wherever possible. Add platform-specific integration only when required by actual platform behavior.
- A widget test or a successful build does not establish that hardware input works. Validate key delivery and navigation on each supported platform independently.

## 2. Space And Input

### Space, Input, And Navigation Are Separate

Use available logical constraints for layout, injected capabilities for remote-first defaults, and current input/highlight mode for interaction feedback. Never select a layout by OS name or assume a wide window is a TV. Keyboard use alone does not imply distant viewing.

Layout, input mode, and navigation are separate concerns:

- **Layout** determines composition and geometry from available constraints.
- **Input capabilities** determine which input mechanisms the device supports.
- **Interaction mode** determines appropriate feedback, such as pointer hover or visible keyboard/remote focus.
- **Navigation** defines how users move between interactive elements and activate them.

Do not rebuild navigation geometry on every pointer or keyboard event. Changing input mode must not unexpectedly change routes, selections, playback state, persisted settings, or loaded data.

The initial width classes remain compact below 600, medium from 600 to 839, and expanded from 840 logical pixels. These are layout starting points, not device detection. Component constraints, height, text scaling, and safe areas may require a simpler composition. Retain the existing 1050-pixel catalog-sidebar threshold until the adaptive-shell package validates a replacement.

| Context | Composition | Interaction |
|---|---|---|
| Compact | Bottom destinations for Home, Live, Movies, Series; accessible Search and Settings outside the destination bar; scrolling group controls; lists or bounded grids | Touch-first on phones, with complete keyboard navigation and correct text-input behavior |
| Medium | Rail when height/width permit, otherwise compact navigation; adaptive content columns | Touch, pointer, keyboard, and available remote navigation supported together |
| Expanded | Labeled navigation rail; group sidebar when content constraints permit; organized multi-column content | Adapt density to the viewing and interaction context; support both efficient pointer use and remote/keyboard navigation |

Navigation composition was approved under D-10 and implemented by WP-4.7. Keep all routes and commands reachable in every composition. Resizing must preserve route, selection, loaded page window, scroll context, and focus where the focused item still exists. Never shrink an entire TV canvas to fit a phone.

### Input Capabilities And Defaults

- Treat touch, pointer, keyboard, D-pad, TV remote, text input, and assistive technology as potentially overlapping capabilities. Do not assume each device has exactly one input mechanism.
- Use injected capabilities and actual input events to select appropriate defaults. Do not use operating-system identity alone to infer input capabilities.
- Phones and tablets should remain touch-first where appropriate. Showing or editing text must support the normal platform keyboard and text-editing conventions. Connecting a keyboard must not break touch interaction or require switching the entire application into a different layout.
- Android phones and tablets default to touch and the platform text keyboard. Android TV is remote-first; external keyboards, switches, and accessibility services remain supported on either form factor. Do not disable key navigation based on Android identity.
- Desktop applications must support complete keyboard operation, including Tab and Shift+Tab traversal, activation, dismissal, and text editing.
- TV and other remote-first environments must support directional navigation, activation, and Back using the available remote controls. Pointer support must not be a prerequisite for using the application.
- Mouse and pointer interaction must remain efficient. Keyboard focus must not interfere with ordinary pointer use, and pointer hover must not be required to reveal an essential action.
- Assistive technologies must be able to discover controls, understand their purpose and state, and operate them through supported accessibility actions.

## 3. Keyboard, Remote, And Focus Navigation

### Navigation Is A Defined Interaction Model

Every interactive screen must have a deliberate navigation model. Relying on the incidental order of widgets in the widget tree, layout geometry, or pointer interaction is insufficient.

Use Flutter's standard focus and keyboard mechanisms as the foundation. Define explicit traversal policies or directional focus relationships where the default behavior does not provide predictable results.

#### Keyboard traversal

- Every interactive control must be reachable through a logical Tab order. Shift+Tab must traverse the same sequence in reverse.
- Traversal should follow the visual and semantic reading order: primary navigation, page-level actions, main content, secondary actions, and supporting controls as appropriate.
- Use stable, predictable traversal. Avoid unexpected jumps between distant sections, hidden controls, unrelated navigation regions, or off-screen content.
- Group related controls into meaningful traversal regions. Use explicit traversal order when layout or responsive reordering makes the default order ambiguous.
- Avoid positive, manually assigned Tab indices as a general solution. Prefer Flutter's focus traversal policies, ordered traversal groups, and appropriate focus nodes.
- Tab moves focus; Enter, Space, or the control's standard activation gesture activates it where appropriate. Do not make focus movement itself execute commands.
- Native text editing behavior must remain intact. Do not intercept navigation keys in a way that breaks cursor movement, selection, editing, or normal text-field shortcuts.
- Every actionable control must be reachable without using a mouse to focus it first.

#### Shared shell boundaries

- Activating a left-menu destination retains focus on that destination after the route transition, including Home with empty content. Do not transfer focus to a tile, See all action, or Search field just because the destination was activated. Right explicitly enters content; Tab follows normal traversal. Direct/programmatic screen entry and Back restoration retain their own initial-focus rules.
- Treat a non-modal page as one Tab cycle. Nested content scopes must let Tab and Shift+Tab escape to their parent scope; do not accept Flutter's default closed loop for an ordinary content pane. In the current SDK, configure `FocusScopeNode.traversalEdgeBehavior` as `TraversalEdgeBehavior.parentScope` for that pane.
- Expanded/rail order is navigation destinations, page actions, then content groups in reading order. Compact order is page actions, content, then bottom destinations. Shift+Tab reverses the same sequence. Wrap only at the whole-page boundary, not inside a sidebar, carousel, or ordinary content pane.
- Rail Up/Down moves among destinations; Right enters remembered content, falling back to an available control. Content Left moves to a meaningful sidebar neighbor or rail at the left edge. Compact bottom destinations use Left/Right within the bar and Up to re-enter content. Do not activate routes merely to move focus.
- Nested content must also permit directional traversal into adjacent regions. Use `FocusScopeNode.directionalTraversalEdgeBehavior` where needed; verify all four directions instead of adding global arrow-key handlers.
- Within a grid, Left/Right follows columns and Up/Down follows rows; within a horizontal strip, Left/Right follows items and Up/Down changes meaningful sections. At the outer page boundary, stop rather than wrapping to an unrelated distant control. Explicitly test ambiguous geometry and adapt local policies when defaults fail.
- Opening a dialog starts a separate modal cycle; dismissal restores its invoker. Native text fields retain caret movement, selection, input methods, and platform keyboard dismissal. Pointer hover must not move keyboard focus or execute a command.

#### Directional navigation for TVs and D-pads

- Define an intentional Left, Right, Up, and Down navigation relationship for interactive elements on remote-first screens.
- Navigation must follow a predictable spatial and semantic relationship. A control should normally move focus to its nearest meaningful neighbor in the requested direction, not an arbitrary widget elsewhere on the page.
- Explicitly handle ambiguous layouts, including grids, sidebars, horizontal carousels, nested navigation regions, toolbars, dialogs, and player controls.
- At the boundaries of a navigation region, define the expected behavior. Focus may move to an adjacent region, stay within a contained region, or follow an established application navigation rule. It must not disappear or jump unpredictably.
- Repeated directional input must move focus reliably without requiring pointer movement.
- Focus must remain visible and must not be confused with selection, hover, playback state, or the currently active route.
- Pressing OK, Enter, or the platform-equivalent activation button invokes the focused control's existing command exactly once.
- Pressing Back or Escape follows the existing dismissal and navigation rules. It must not unexpectedly exit the application or trigger unrelated actions.
- When a focused item becomes unavailable, restore focus to the nearest appropriate remaining item or the region's primary action.

#### Responsive navigation

- Navigation must remain usable when the layout changes from compact to medium or expanded, and when a desktop window is resized.
- Recompute directional relationships when layout geometry changes, but do not rebuild the entire navigation model for every input event.
- Preserve focus identity when the same logical control remains available after a resize or composition change.
- If a focused control disappears because the layout changes, move focus to a predictable equivalent or nearby control.
- A responsive change must not silently reset the route, selected content, scroll position, loaded page window, or playback state.

### Focus Lifecycle And Activation

- Set initial focus once when a screen or meaningful content region becomes ready. Do not repeatedly request focus during ordinary rebuilds.
- Initial focus should follow the screen's purpose: for example, the primary action, the current navigation destination, or the first available content item. Do not place focus on decorative elements or hidden controls.
- Restore the previous focused item when returning from a detail screen or dismissing a transient UI, when that item still exists.
- If the previous item no longer exists, choose the nearest remaining item or an appropriate primary action.
- Moving focus must never start playback, persist a selection, navigate to another route, or execute a destructive action.
- Activation invokes the existing command exactly once. Avoid duplicate handling through both parent and child keyboard listeners.
- Dialogs, menus, and other modal regions must manage focus deliberately. When opened, focus moves into the active region; traversal must respect its boundaries where appropriate; when dismissed, focus returns to the invoking control if it still exists.
- Disabled, hidden, covered-route, and non-interactive elements must not become accidental keyboard or remote destinations. Off-screen items in a scrollable region may receive focus only when they can be revealed predictably.
- Reveal focused controls within the visible scroll viewport, accounting for safe areas and the text keyboard. Focus changes must not cause unrelated scrolling, layout shifts, catalog resets, or unbounded eager loading; normal paged continuation remains allowed.

### Input Event Handling And Platform Integration

- Use Flutter's `Focus`, `FocusNode`, `FocusScope`, `FocusTraversalGroup`, `FocusTraversalOrder`, `Shortcuts`, `Actions`, and standard controls where appropriate. Do not create a parallel focus framework without a demonstrated platform limitation.
- Handle keys at the narrowest appropriate scope. Avoid global handlers that consume events intended for text fields, system navigation, or other controls.
- Consume a keyboard event only when the application has intentionally handled it. Otherwise, allow normal Flutter event propagation and default behavior.
- Map platform-specific remote keys to the intended actions through a documented, testable layer. Do not assume that all remotes send identical key codes or that all platforms deliver events through identical APIs.
- For LG webOS, verify that the Flutter engine receives directional and activation key events when the Magic Remote switches from pointer mode to directional navigation. Do not assume that browser-specific JavaScript APIs or webOS system UI events are directly available in Dart.
- If the platform does not deliver the expected events, investigate the engine, runtime, application configuration, and key mapping before rewriting the application's navigation UI.
- Treat Back, Escape, Select/OK, Enter, Space, and directional keys as distinct actions unless the platform contract explicitly defines equivalent behavior.
- Avoid hard-coding physical key codes when Flutter's logical key abstractions or a tested platform adapter can express the intended action more reliably.

## 4. Controls, Focus, And Motion

- Target WCAG 2.2 AA interaction principles where applicable to native Flutter: keyboard access, no keyboard traps, meaningful order, visible and unobscured focus, accessible names/states, and status announcements. This is a design target, not a compliance certification.
- Measure actual text contrast at 4.5:1 or 3:1 for qualifying large text, and meaningful control boundaries/focus indicators at 3:1 against adjacent surfaces. Do not rely only on color, motion, pointer precision, or timing.
- Use familiar tool icons, labeled destinations, tooltips for unfamiliar icon commands, switches for binary settings, and menus or segmented controls for option sets.
- Back dismisses the topmost modal or local transient UI before popping one route; preserve root exit and player stop-on-exit behavior.

- Focus is a shared, first-class semantic design token with a high-contrast visual treatment. Focus and selection remain separate states and may coexist.
- Every interactive control must expose a visible focus indicator when reached through keyboard or remote navigation. Pointer hover must not be the only visible interaction feedback.
- The focus indicator must remain visible against adjacent surfaces and content, meet the contract's contrast requirements, and avoid relying on color alone.
- Focus emphasis must not resize grid tracks, clip content, cover neighboring controls, or move hit targets. Prefer an outline, border, or non-layout-changing visual treatment.
- Focus visibility must not depend on animation. Reduced-motion settings must preserve an equally clear static focus indicator.
- A control must have an accessible name, appropriate role, and relevant state. Custom controls must expose semantics and activation behavior equivalent to standard Flutter controls.
- Decorative elements, headings, and non-actionable containers must not enter normal Tab or D-pad traversal unless they serve a deliberate, documented accessibility purpose.
- Use native or standard Flutter controls whenever they provide the required interaction and accessibility behavior. Custom controls must reproduce keyboard, focus, activation, disabled-state, and semantics behavior explicitly.
- Touch target requirements remain unchanged: at least 48×48 logical pixels, with remote-first targets starting at 56×56. Validate targets against the actual platform rendering scale.

### Tokens And Theme

- Centralize semantic surface, text, accent, focus, error, warning, live, and watched roles; components use tokens rather than new palette literals. Keep focus and selection separate.
- Centralize discrete typography, insets, gaps, padding, tile dimensions, radii, focus width, and motion. Remote-first body text starts at 18 logical pixels, compact at 16. Respect text scaling with wrapping and growing controls, not viewport-proportional fonts.
- Keep stable item geometry, bounded headings, and shared radius tokens. New repeated cards normally use radii no larger than 8; do not turn page sections into nested cards.
- D-9 controls palette/light-theme adoption. New theme selection, branding, or fonts require separately scoped work.

## 5. Content And States

- Use available artwork with stable aspect ratios, bounded image decoding/cache policy, and accessible fallbacks. Never fabricate metadata, artwork, ratings, or viewing progress.
- Hide unavailable optional metadata; preserve readable essential titles and accessible full labels. Distinguish loading, empty, error/retry, buffering, disabled, selected, focused, and failed-refresh-with-cache states.
- Preserve cached content and paged queries. Default errors are friendly; the approved verbose playlist diagnostic exception remains opt-in and redacted as recorded in [decisions](decisions.md).
- Every screen must have a usable focus path to its essential actions, including loading, empty, error, retry, and content-unavailable states.
- A focusable control must provide understandable feedback when activated, including for asynchronous actions.
- Loading or refreshing content must not steal focus repeatedly or cause focus to jump unexpectedly as items arrive.
- When paged content loads more items, preserve the current focus and provide a predictable continuation path.
- When a focused item is removed, filtered out, or replaced, restore focus to an appropriate remaining item rather than leaving focus stranded.
- Focus must not move behind a modal or to an obscured control while a modal interaction is active.
- Error messages and status changes should be exposed appropriately to assistive technologies without unexpectedly stealing keyboard focus.
- Do not add diagnostic or instructional copy to production screens merely to explain remote navigation. Use automated tests and opt-in, redacted diagnostics instead.

## 6. Verification Matrix

- Test compact portrait at 360x800 and 390x844, short/landscape at 800x360, medium at 800x1000, expanded at 1440x900, and remote-first at 1280x720 and 1920x1080 logical pixels. Include text scaling at 1.0 and 2.0, safe areas, text keyboard insets, and resizing across breakpoints.
- Include missing artwork, stable geometry, loading/empty/error states, reduced motion, semantics, target sizes, and focus distinct from selection. Capture representative Flutter screenshots or goldens for visual review; HTML prototype checks do not certify Flutter rendering.
- Record Android phone, Android TV, Windows, Linux development, and LG webOS checks independently. Include actual viewport/scale, input devices, key mapping, distant readability, and Back behavior. Unavailable hardware remains explicitly pending.

### Keyboard-only verification

- Verify that all primary journeys can be completed without a mouse or touch input.
- Test Tab, Shift+Tab, Enter, Space, Escape, and applicable shortcuts on Windows and Linux.
- Verify logical traversal order, visible focus, text-field editing, activation exactly once, modal focus containment, and focus restoration.
- Check that no keyboard trap prevents users from leaving a control or region, except where a deliberately modal interaction requires containment.
- Verify that pointer movement does not unexpectedly reset keyboard focus or alter application state.

### Remote and D-pad verification

- Test directional navigation, Select/OK, and Back on actual supported TV hardware, including LG webOS and Android TV.
- Verify that directional navigation follows meaningful spatial relationships in sidebars, grids, carousels, dialogs, toolbars, and player overlays.
- Test navigation boundaries, repeated key presses, unavailable items, dynamic content updates, and transitions between navigation regions.
- Verify that Magic Remote pointer mode and directional navigation both work, including transitions between the two interaction modes.
- Confirm that a visible focus indicator is present at all times when keyboard or remote focus is active.
- Record actual device, OS/runtime, Flutter engine/version, key mapping, viewport, and rendering scale for manual checks.

### Accessibility verification

- Test semantics, accessible names, roles, selected and disabled states, reading order, and focus visibility.
- Where available, test with platform screen readers and keyboard-accessibility tools.
- Verify text scaling, contrast, reduced motion, and focus visibility independently of pointer hover.
- Ensure that essential operations do not depend exclusively on color, motion, pointer precision, or simultaneous multi-key input.
- Include tests for controls and workflows implemented using custom widgets, not only standard Material controls.

### Automated tests

- Add widget tests for traversal order, directional focus movement, activation, modal behavior, focus restoration, and layout changes.
- Use deterministic focus relationships and assert the resulting focused control rather than relying solely on screenshots.
- Add regression tests for previously failing key mappings or navigation paths.
- Keep hardware checks separate from widget-test results. Passing Flutter widget tests does not certify that the native platform or remote delivers input correctly.

## 7. Acceptance Criteria For New UI Work

A UI change that introduces or modifies interactive controls is not complete until:

1. All essential controls can be reached and operated using the appropriate supported input methods.
2. Keyboard traversal order is logical, reversible, and free of unintended traps.
3. D-pad navigation is predictable and has explicit boundary behavior in remote-first contexts.
4. Focus is visible, distinguishable from selection, and restored appropriately after navigation or layout changes.
5. Activation does not occur merely because focus moved, and commands are not executed twice.
6. Text input, standard editing keys, and platform Back/Escape behavior remain functional.
7. Relevant automated tests are included in the touched UI package.
8. Hardware validation is recorded accurately, with untested platform behavior explicitly marked as pending.

**Guiding principle:** Design once around meaningful controls, semantics, focus, and commands; adapt layout and input handling to the capabilities of each platform. An application that can be fully operated without a pointer is generally more robust for everyone, not only people who depend on keyboard navigation or assistive technology.

## 8. Deferred Product Work

Mini-player/system picture-in-picture, EPG/live preview, quality folding, rating enrichment/sorting,
history-backed initial focus/resume/favorites, next-episode autoplay, sports/recommendations,
voice/suggestions/recent searches, subtitle/audio preferences, and branding/theme changes require
separate delivery scope. Preserve All-group defaults under D-8 and existing activation destinations;
accessibility work is not approval to bypass Details or change playback behavior.