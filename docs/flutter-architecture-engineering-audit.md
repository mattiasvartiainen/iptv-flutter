# Flutter Application — Architecture & Engineering Audit

You are performing a **read-only architecture, code-quality, Flutter best-practices and maintainability audit** of the existing Flutter application.

**Do not modify any files.**

The goal is to understand the existing codebase first, identify strengths and weaknesses, and produce actionable recommendations. Do not perform a rewrite or refactor during this task.

This application targets:

* Android
* Windows
* LG webOS

It is an IPTV application with a TV/10-foot user experience.

Use the available **official Flutter and Dart skills** wherever they are relevant to the analysis. In particular, use guidance from skills concerning:

* responsive/adaptive layouts
* Flutter architecture
* widget testing
* integration testing
* layout problems
* navigation
* JSON serialization
* HTTP/networking
* Dart best practices

Also apply established software engineering principles where appropriate.

---

# 1. First understand the codebase

Before making recommendations, inspect the repository and build a mental model of the application.

Identify:

* application entry points
* major features
* folder/module structure
* state-management approach
* navigation approach
* dependency injection/service location
* data layer
* repositories
* API/networking
* SQLite/local persistence
* media playback
* platform-specific code
* configuration
* error handling
* logging
* testing
* shared UI components
* design system/theme
* localization
* asset management

Trace several representative features from:

UI → state/application logic → domain → repository → data source

Identify the actual dependency direction rather than assuming that the folder structure represents the architecture.

---

# 2. Produce an architecture overview

Create a concise architecture diagram in Markdown.

Show:

* major layers
* major features
* important dependencies
* platform-specific boundaries
* data flow
* media playback flow

Identify architectural boundaries that are clear and healthy.

Also identify places where boundaries are currently leaking.

For example:

* widgets directly accessing databases
* UI directly calling HTTP APIs
* business logic inside widgets
* platform-specific APIs leaking into shared code
* repositories containing presentation concerns
* domain logic coupled to Flutter widgets

Do not recommend architecture changes simply because another architecture is fashionable.

Evaluate whether the current architecture is appropriate for this application.

---

# 3. Flutter and Dart best-practice audit

Evaluate the code against current official Flutter and Dart guidance.

Look specifically at:

## Widgets

* widget responsibilities
* widget size and complexity
* deeply nested widget trees
* build() complexity
* inappropriate work performed during build()
* unnecessary widget rebuilding
* unnecessary StatefulWidgets
* unnecessary state
* const usage
* keys where appropriate
* composition vs inheritance
* reusable components
* widget naming
* widget API design

Do not treat "large file" as automatically bad.

A large file is a problem when it contains multiple unrelated responsibilities, poor cohesion, excessive complexity, or becomes difficult to reason about.

## Dart

Check:

* null safety
* async/await usage
* Future/Stream handling
* error propagation
* exception handling
* immutability
* final/const usage
* collection manipulation
* unnecessary allocations
* unnecessary dynamic types
* type safety
* extensions
* sealed classes/enums/pattern matching where they genuinely improve the design
* unnecessary abstractions
* duplicated logic

Prefer simple idiomatic Dart over clever code.

---

# 4. Component and file structure

Evaluate whether the UI has an appropriate component structure.

Look for:

* duplicated UI
* repeated visual patterns
* components that should be shared
* widgets containing too many unrelated responsibilities
* components with excessively large public APIs
* screens that contain all their own UI implementation
* reusable components that are tightly coupled to a specific screen
* components that are difficult to test independently

Recommend splitting code when there is a meaningful responsibility boundary.

Do NOT split code purely to satisfy an arbitrary line-count rule.

Use file size as a signal, not as a rule.

For every large file you identify, explain:

1. Why it is difficult to maintain
2. What responsibilities it contains
3. How those responsibilities could be separated
4. Whether the separation should actually be performed

---

# 5. Complexity analysis

Analyze complexity where useful.

Consider:

* cyclomatic complexity
* nesting depth
* number of branches
* conditional rendering complexity
* state transitions
* number of responsibilities
* method length
* widget build complexity
* dependency count
* coupling
* cohesion

Identify particularly complex functions, widgets and classes.

Where practical, report:

* approximate cyclomatic complexity
* why the complexity exists
* whether it is accidental or inherent
* how it could be reduced

Do not mechanically refactor code simply because a metric exceeds an arbitrary threshold.

---

# 6. CRAP score and testability

Where test coverage and complexity information allow it, consider CRAP-style analysis.

Pay particular attention to:

* complex business logic with little/no test coverage
* state transitions
* data transformations
* parsing
* synchronization logic
* filtering/sorting logic
* playback state management
* repository logic
* error handling

Do not focus CRAP analysis primarily on trivial declarative UI.

A simple widget with many lines of declarative layout is not necessarily high-risk code.

Prioritize complexity combined with lack of tests.

---

# 7. Testing

Audit the current testing strategy.

Identify:

* unit tests
* widget tests
* integration tests
* golden tests
* test utilities
* mocks/fakes
* missing coverage

Determine whether important business logic can be tested without rendering widgets.

Identify high-value missing tests.

Pay particular attention to:

* navigation
* focus behavior
* state transitions
* repositories
* parsing
* database operations
* synchronization
* error handling
* media playback state
* responsive layouts

Do not recommend tests merely to increase code coverage.

Recommend tests that protect important behavior.

---

# 8. Responsive and adaptive UI

Use the official Flutter responsive/adaptive guidance.

Check for incorrect assumptions such as:

* Android == phone
* Windows == desktop layout
* orientation == screen size
* hard-coded screen dimensions
* platform checks used to choose layouts

Prefer reasoning based on:

* available window size
* constraints
* input capabilities
* interaction model
* platform capabilities

Check use of:

* LayoutBuilder
* MediaQuery.sizeOf
* constraints
* adaptive navigation
* flexible layouts
* lazy lists/grids

Identify hard-coded dimensions that are likely to cause problems.

---

# 9. TV / 10-foot UX

This application has a TV-first experience.

Audit specifically for:

* remote-control navigation
* keyboard navigation
* mouse interaction
* focus management
* focus traversal
* visible focus indicators
* predictable directional navigation
* focus restoration
* dialogs and overlays
* menus
* grids
* lists
* large touch targets
* text readability at distance
* excessive animations
* hover assumptions
* pointer-only interaction

Identify controls that appear usable with a mouse/touch screen but may fail with a remote control.

Treat TV interaction as a first-class interaction model, not as a scaled-up mobile UI.

---

# 10. Multi-platform architecture

Audit the Android, Windows and webOS boundaries.

Find:

* Platform.isAndroid
* Platform.isWindows
* kIsWeb
* conditional imports
* platform channels
* native APIs
* platform-specific plugins
* platform-specific media implementations

Determine whether platform-specific behavior is properly isolated.

Prefer capability-based abstractions where appropriate instead of scattering platform checks throughout the UI.

Identify dependencies that could cause compatibility problems across the three target platforms.

Pay particular attention to webOS compatibility.

Do not assume that a package working on Android or Windows will work on webOS.

---

# 11. Performance

Assume that the application may contain:

* thousands of live channels
* thousands of VOD items
* many images
* large EPG datasets

Audit:

* list/grid construction
* lazy loading
* image loading
* image caching
* unnecessary network calls
* database queries
* repeated database queries
* object allocation
* widget rebuilds
* expensive work on the UI isolate
* startup work
* parsing
* synchronization
* memory usage

Look for accidental O(n²) or worse operations.

Do not optimize everything.

Identify performance risks and distinguish:

* measured problems
* likely problems
* theoretical problems

---

# 12. Data architecture

Inspect the local catalog/data architecture.

Determine whether the separation between:

remote source → synchronization/import → local database → repository → application state → UI

is maintained.

Look for:

* network calls from widgets
* database access from widgets
* M3U parsing in UI code
* duplicated models
* duplicated mapping logic
* unnecessary full catalog reloads
* inefficient queries
* missing indexes
* inappropriate in-memory filtering
* persistence concerns leaking into presentation

Identify opportunities to improve data access without unnecessarily redesigning the application.

---

# 13. Media playback

Inspect media playback architecture.

Determine:

* where player instances are created
* who owns playback state
* how lifecycle is handled
* how errors are handled
* how playback state reaches the UI
* whether player implementation is coupled to screens
* whether playback survives navigation appropriately
* whether platform-specific behavior is isolated

Pay particular attention to the fact that Android, Windows and webOS may have different media capabilities and limitations.

---

# 14. State management

Identify the state-management approach currently used.

Evaluate:

* state ownership
* state lifetime
* unnecessary global state
* duplicated state
* derived state
* asynchronous state
* loading/error/empty states
* disposal/lifecycle
* rebuild scope

Look for state that belongs:

* locally to a widget
* to a feature
* to the application
* to persistent storage

Do not recommend changing state-management libraries simply because another library is popular.

---

# 15. UI design and design system

Evaluate consistency of the UI.

Look for repeated:

* spacing
* padding
* typography
* colors
* border radius
* icons
* buttons
* cards
* dialogs
* focus indicators
* loading indicators
* empty states
* error states

Determine whether these should become reusable design-system components or theme values.

Avoid creating abstractions for components that only occur once unless they have a clear conceptual responsibility.

---

# 16. Code smells

Look for:

* duplicated code
* dead code
* commented-out code
* magic numbers
* magic strings
* giant switch statements
* boolean parameter abuse
* excessive nullable values
* primitive obsession
* inappropriate inheritance
* god classes
* god widgets
* feature envy
* hidden dependencies
* global mutable state
* excessive service locator usage
* unnecessary abstractions
* premature abstractions
* leaky abstractions

For each significant smell, explain the concrete maintenance problem it causes.

---

# 17. Dependencies

Inspect `pubspec.yaml` and dependency usage.

For each significant dependency determine:

* what it is used for
* whether it is actually needed
* whether usage is appropriately isolated
* whether it creates platform constraints
* whether it is used directly throughout the application or hidden behind an abstraction

Pay particular attention to packages that may not support all target platforms.

Do not recommend replacing a dependency without a concrete reason.

---

# 18. Accessibility

Audit:

* semantic labels
* contrast
* text scaling
* keyboard navigation
* focus visibility
* touch target sizes
* screen reader considerations

Consider the differences between mobile accessibility and TV/remote accessibility.

---

# 19. Logging and error handling

Inspect:

* logging strategy
* swallowed exceptions
* generic catch blocks
* user-facing errors
* retry behavior
* network failures
* database failures
* playback failures

Identify places where failures could silently produce incorrect behavior.

---

# 20. Code quality metrics

Where useful, estimate or calculate:

* cyclomatic complexity
* CRAP score
* code duplication
* large methods
* large classes/widgets
* dependency coupling
* test coverage
* suspiciously complex build() methods

Do not create arbitrary quality scores for the entire project.

Metrics should support reasoning rather than replace it.

---

# 21. Prioritization

Every significant finding must have:

**Severity**

* Critical
* High
* Medium
* Low

**Confidence**

* High
* Medium
* Low

**Category**

* Architecture
* Flutter
* Dart
* UI
* TV UX
* Performance
* Testing
* Platform
* Data
* Media
* Maintainability
* Accessibility
* Security

For each finding include:

```text
Location:
Problem:
Why it matters:
Evidence:
Recommendation:
Estimated effort:
Risk of changing it:
```

---

# 22. Do not over-engineer

This is an important constraint.

Do not recommend:

* abstractions without a demonstrated need
* additional layers simply because they are considered "clean architecture"
* new frameworks without a concrete problem
* replacing working libraries without a reason
* splitting every widget into tiny files
* design patterns for their own sake
* premature optimization

Prefer the simplest design that maintains clear responsibilities and good testability.

Existing code that is simple and works well should be recognized as such.

---

# 23. Final report

Produce the following report:

## Executive summary

Brief description of the current state.

## Architecture

Current architecture and dependency flow.

## What's already good

Identify good existing practices and decisions.

## Critical/high-priority findings

The most important issues.

## Maintainability findings

Complexity, cohesion, coupling, duplication, large responsibilities, etc.

## Flutter/Dart findings

Flutter and Dart-specific issues.

## UI/design findings

Components, consistency, responsive design, accessibility.

## TV findings

Focus, remote navigation and 10-foot UX.

## Platform findings

Android, Windows and webOS.

## Performance findings

Measured vs likely risks.

## Testing findings

Current testing quality and high-value missing tests.

## Metrics

Provide useful metrics where they can be calculated reliably.

Do not invent measurements.

## Recommended improvements

Separate into:

### Quick wins

Changes that are small and low risk.

### Medium-sized improvements

Changes worth planning.

### Architectural improvements

Changes requiring deliberate design.

## Recommended project guidelines

Finally, propose an `AGENTS.md` structure containing the project-specific rules that an AI coding agent should follow in future work.

These guidelines should focus on knowledge that a general Flutter/Dart coding agent would not automatically know about this particular application.

---

# Most important instruction

This is an **audit, not a rewrite**.

Do not modify files.

Do not optimize for the number of findings.

Do not invent problems.

Prefer 10 well-supported findings over 50 speculative ones.

When something is already well designed, explicitly say so.

When recommending a change, explain the concrete problem it solves.

Preserve existing working architecture unless there is a demonstrated reason to change it.
