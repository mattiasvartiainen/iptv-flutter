# IPTV App — Product & UX Requirements

## 1. Purpose

This document is the detailed product and UX source of truth for the IPTV application.

It is intended to be given to a UX/UI designer or design agent such as Claude Design before implementation.

The document describes:
- product vision
- UX principles
- user behavior and usage modes
- information architecture
- Home
- Live TV
- TV Guide / EPG
- Movies
- Series
- Sports
- Search
- Playback and continuity
- Personalization
- Playlists and IPTV sources
- Import and refresh behavior
- Cross-device behavior
- TV/D-pad interaction
- metadata enrichment
- errors and empty states
- design constraints
- success criteria

It intentionally does **not** prescribe every visual detail. Where several UX solutions are possible, the designer should use these requirements as constraints and use UX expertise to choose the best interaction model.

---

# 2. Product vision

This should be more than a raw IPTV player.

The application is a **personal TV gateway** between messy IPTV sources and the user's actual viewing intent.

Conceptually:

```text
IPTV source
    ↓
Import / normalize
    ↓
Local catalog
    ↓
Metadata enrichment
    ↓
Personal context
    ↓
Device-appropriate UI
    ↓
Find something worth watching
    ↓
Play
```

The IPTV playlist is raw inventory, not the product information architecture.

The application should progressively transform poor IPTV data into something understandable and useful.

The experience should combine:

- the visual richness of a modern streaming service
- the clarity and information density of a modern TV guide
- the directness of a good IPTV player

It should **not** simply copy Netflix or another streaming service.

---

# 3. Central UX principle

> **Make it easy for the user to find and select content they probably want to watch, without taking the choice away from them.**

The app should help the user make a good decision.

It should not make the decision for them.

Good:

> "GAIS today 19:00"

Bad:

> Automatically opening the GAIS match.

Good:

> Showing movies similar to things the user watches.

Bad:

> Automatically playing a recommendation.

---

# 4. Main user modes

The application must support four fundamental modes of use.

## 4.1 Habit

> "I normally watch this."

Examples:
- favorite channels
- frequently watched channels
- recently watched content
- continuing a series
- returning to a recently viewed movie

## 4.2 Intent

> "I know what I want."

Examples:
- a specific channel
- a specific movie
- a specific series
- GAIS
- a specific sports match

## 4.3 Discovery

> "I want to find something good."

Examples:
- highly rated movies
- new movies
- recommendations
- genres
- popular content
- sports worth watching

## 4.4 Continuity

> "I want to continue where I left off."

Examples:
- resume a movie
- continue a series
- start the next episode
- return to a recently watched channel

These modes should coexist naturally rather than becoming four separate products.

---

# 5. Core product principles

## 5.1 Help, don't take control

Personalization should reduce friction but remain predictable.

The user must always feel in control.

## 5.2 Home is a launchpad

Home should help the user decide what to do quickly.

It should not become an endless content feed.

## 5.3 Progressive personalization

The application should become more useful over time.

Initially:

```text
Playlist → usable catalog
```

Over time:

```text
Catalog
  + metadata
  + viewing history
  + favorites
  + interests
  + behavioral patterns
  = better prioritization
```

## 5.4 Playlist structure is not application structure

M3U/Xtream groups are useful filters.

They must not dictate the application's entire navigation.

## 5.5 Enrichment is optional

Basic IPTV functionality must work without external metadata.

If enrichment fails:
- content remains playable
- browsing still works
- search still works
- titles remain visible
- the UI degrades gracefully

## 5.6 Search is not automatically personalization

Searching for something does not mean the user wants it permanently remembered.

There should be a distinction between:
- recent searches
- explicit saved interests

---

# 6. Target platforms

The first target is LG webOS TV.

Future targets:
- Windows
- Linux
- Android
- Apple TV
- Samsung / additional TV platforms

The product should share the same conceptual model across platforms.

---

# 7. Cross-device philosophy

The application is a full client on each device.

A phone is **not merely a remote control**.

The same core content model should exist across devices.

Potentially shared:
- favorites
- watched state
- playback progress
- interests
- preferences

Cross-device synchronization/handoff is desirable later but is **not a v1 priority**.

## TV

Optimize for:
- large screen
- viewing distance
- D-pad
- visible focus
- rich simultaneous information
- horizontal browsing

## Phone

Optimize for:
- touch
- compact layouts
- vertical browsing
- efficient search
- less information shown simultaneously

The information architecture should remain recognizable while presentation adapts.

---

# 8. Visual direction

The visual direction should combine:

### Modern streaming service

- rich artwork
- posters
- backdrops
- strong hierarchy
- confident typography
- modern dark-first presentation

### Modern TV guide

Especially for Live TV:
- information density
- clear times
- current/upcoming programs
- channel identity
- efficient scanning

Use Netflix-like **visual confidence**, but do not copy Netflix's interaction model.

---

# 9. Design system

The design system should be themeable from the beginning.

Even if only one theme ships:
- colors should be tokens
- typography should be centralized
- spacing should be consistent
- components should be reusable
- focus states should be systematic

Dark-first is the natural default for TV.

---

# 10. Navigation

Persistent navigation is preferred.

Core concepts:

- Home
- Live TV
- Movies
- Series
- Search

Sports may become a dedicated area if exploration shows that it deserves one.

Navigation should remain stable rather than being completely rearranged by personalization.

---

# 11. Home

Home is the first screen after startup.

## 11.1 No autoplay

The application must **not** automatically start playback on startup.

The user should see useful choices first.

## 11.2 Compact Home

Do not make the Home screen a giant cinematic hero.

The user should quickly see useful content.

## 11.3 First major section

The first prominent section should be:

> **Recently Watched**

It should be divided by content type.

For example:

```text
Recently Watched

Live TV
[channels...]

Movies
[movies...]

Series
[series...]
```

Do not create one noisy mixed row of channels, posters, and episodes.

Empty groups should be hidden.

Within a group, items should generally be ordered by recency.

---

# 12. Home modules

Potential modules include:

- Recently Watched
- Your Channels
- What's On Now
- Sports Today
- Followed Interests
- Continue Watching
- New Movies
- New to Your Library
- Recommendations
- Most Watched

Home should remain compact.

A few useful modules are better than an enormous personalized feed.

---

# 13. Dashboard concept

The Home experience can proactively surface useful information.

Example:

```text
GAIS
Today · 19:00

Continue Watching
The Last of Us · S02E04

New to Your Library
3 highly rated movies
```

This should feel like personal TV information, not advertising.

---

# 14. Personalization

There are three main personalization sources.

## Explicit

User deliberately chooses:
- favorites
- saved interests
- hidden content
- preferences

## Behavioral

The application observes:
- recently watched content
- frequently watched channels
- movies watched
- series watched
- searches
- interaction patterns

## Contextual

Examples:
- sports happening today
- newly added movies
- content available in the current playlist

---

# 15. Attention should decay

The application should not assume that a historical behavior remains equally important forever.

Example:

A channel watched frequently for three months but not watched for two weeks should gradually become less prominent.

A newer habit can overtake an old one.

A setting may eventually allow behavioral promotion to be disabled.

The exact ranking algorithm is an implementation detail.

---

# 16. Favorites vs frequently watched

These must remain conceptually distinct.

### Favorites

Explicit:

> "I want this to be one of my preferred channels."

### Frequently watched

Learned:

> "The user tends to watch this."

Both may contribute to:

> **Your Channels**

But they should not be presented as if they are the same thing.

---

# 17. IPTV playlists

Multiple playlists are **separate content universes**.

Do not merge them.

Example:

```text
Playlist A
  Movies
  Series
  Live TV

Playlist B
  Movies
  Series
  Live TV
```

The user selects one playlist.

Only that playlist's content is shown.

---

# 18. Playlist-specific state

Each playlist has independent:

- catalog
- favorites
- recent items
- watch progress
- browsing context
- learned preferences/personalization
- refresh state

If the same movie exists in two playlists, they are separate application items.

They have separate:
- progress
- favorites
- availability
- recent state

---

# 19. Active playlist

There is always exactly one active playlist.

The application remembers the last active playlist.

Startup opens the last-used playlist.

Playlist switching happens through **Settings**, not the main navigation.

Selecting another playlist switches immediately.

---

# 20. Playlist management

Users can:

- add playlists
- edit playlists
- rename playlists
- remove playlists
- change source configuration
- refresh playlists
- reset/re-import playlists

Playlist names are:
- required
- unique

Validate uniqueness when the user submits.

Do not constantly validate while typing.

---

# 21. Playlist identity

A playlist has a stable local identity.

Changing:
- URL
- source type
- credentials
- other source details

does not create a new playlist.

Existing playlist-specific state remains attached to it.

A changed source is applied to the catalog only after an explicit import/refresh.

---

# 22. Supported source types

First version should support:

- M3U URL
- local M3U file
- Xtream Codes

The source architecture should be extensible.

All sources should eventually produce the same internal playlist/catalog model.

---

# 23. Adding a playlist

The add flow should be:

```text
Add playlist
    ↓
Choose source type
    ↓
Enter source information
    ↓
Enter / edit playlist name
    ↓
Import immediately
    ↓
Show progress
    ↓
Show completion summary
    ↓
Continue
```

The first playlist added becomes active automatically.

Later playlists are imported immediately but do not replace the current active playlist.

---

# 24. Playlist naming

Try to derive a useful name from the source.

Possible sources:
- M3U filename
- provider/server name
- source information

Always provide an editable name field.

If no useful name can be derived:
- leave it empty
- require the user to enter one

---

# 25. Source configuration and validation

Users can edit:
- name
- source type
- URL/server
- credentials
- refresh settings
- other source-specific information

Saving does **not** automatically import.

The user explicitly chooses Import/Refresh.

The application should allow saving incomplete or currently invalid configuration.

Do not nag about invalid configuration until the user tries to import.

---

# 26. Credentials

Credentials must:
- be stored securely
- be masked in normal UI
- never be exposed in errors
- never be exposed in verbose output

There is no separate "Test connection" action.

Import/refresh itself validates the source.

---

# 27. Playlist status

The playlist list in Settings should show useful information:

- active state
- last successful import
- refresh interval
- whether refresh is due
- current status
- error state when relevant

Only the current import state is required.

A complete historical import log is not required.

---

# 28. Refresh

Both manual and automatic refresh are supported.

Automatic refresh is configured per playlist.

Only the **active playlist** is automatically refreshed.

Other playlists are not refreshed in the background.

---

# 29. Refresh intervals

Supported presets:

- Daily
- Every 3 days
- Weekly
- Monthly
- Never

Also provide:

> Refresh now

---

# 30. Automatic refresh behavior

Automatic refresh occurs during startup.

It must never interrupt active use.

If an update becomes due while the user is using the application:

> Show a small non-blocking indicator.

Examples:

- Update available
- Refresh needed

The user can continue watching.

---

# 31. Startup refresh

If the active playlist needs refreshing at startup:

> Wait for the refresh to finish before entering the main application.

Show a clear import/refresh progress screen.

---

# 32. Switching to an overdue playlist

When switching to another playlist:
1. check whether refresh is due
2. refresh immediately if required
3. allow cancellation

If the user cancels:
- the playlist remains overdue
- it should be offered again next time it becomes active

---

# 33. Import progress

Import is a blocking workflow.

Normal UI should show meaningful stages, for example:

```text
Downloading playlist
Processing channels
Processing movies
Processing series
Updating catalog
Finalizing
```

The exact implementation stages can differ.

---

# 34. Verbose output

Provide a global setting:

> **Verbose output**

Normal mode should show user-friendly information.

Verbose mode can show:
- download details
- parsing counts
- processing counts
- metadata operations
- timings
- technical errors

Verbose mode is global.

Sensitive credentials must still never be exposed.

---

# 35. Successful import

After a successful import, show a short summary and an explicit:

> Continue

Useful information:
- total content
- added content
- removed content
- warnings/errors
- last updated time

Do not prioritize internal enrichment statistics.

For example:

> "312 movies matched with metadata"

is not particularly useful to the user.

Prefer:

> "12 new movies added"

---

# 36. Normal refresh failure

A normal refresh must preserve the last known good catalog.

If refresh fails:

```text
Refresh failed
    ↓
Show understandable error
    ↓
Keep previous catalog
    ↓
Allow user to continue
```

Never leave the user with a partially replaced catalog after a failed normal refresh.

---

# 37. Initial import failure

If a playlist has never successfully imported:

> Show an empty/setup state.

Provide an obvious:

> Import now

action.

---

# 38. Reset / re-import

Reset is a destructive clean slate.

It removes:
- current catalog
- favorites
- watch progress
- recently watched
- other playlist-specific state

Then immediately starts a fresh import.

Confirmation should be simple:

```text
Cancel    Reset
```

Do not require typing the playlist name.

---

# 39. Reset failure

If the fresh import after reset fails:

> Leave the playlist empty.

Do **not** restore the old catalog.

This intentionally differs from normal refresh failure.

---

# 40. Removed source content

The IPTV source is authoritative.

If content is removed from the source during a successful refresh:

> Remove it from the catalog.

---

# 41. Changed metadata

If existing content remains but its metadata changes:

> Accept the newest metadata.

---

# 42. Duplicate entries

Do not automatically deduplicate playlist entries.

If the source contains duplicates:

> Show them as supplied.

---

# 43. Live TV

Live TV is fundamentally channel-first.

Common intents:

> "I know which channel I want."

or:

> "I want to find something specific."

The UX should support both.

---

# 44. Live TV landing

A large-screen Live TV landing can be a dashboard while remaining channel-focused.

Potential sections:

- Your Channels
- Recently Watched
- What's On Now
- Sports Today
- Continue Watching
- Groups / All Channels
- TV Guide

---

# 45. Live TV on phone

Prioritize:

1. Your Channels
2. Browse/search
3. Guide

Do not overload the small screen.

---

# 46. Live TV groups

Playlist groups are useful filters.

Examples:
- Sweden
- Norway
- Sports
- News
- Kids

Groups should be treated as narrowing mechanisms.

The user must still be able to browse all available live TV.

---

# 47. Live TV browsing modes

Support:

- channel list/grid
- groups/categories
- TV Guide
- What's On Now
- all live TV
- filtered live TV

---

# 48. Channel presentation

Preferred presentation:

> Grid of large channel cards/logos.

Logos are an enhancement, not a dependency.

If a logo is missing:
- show the channel name clearly
- use the same card treatment
- do not make it look broken

---

# 49. Current program

A channel card should show current program information when available.

Example:

```text
[Channel logo]

SVT1
Aktuellt
19:30–20:00
```

---

# 50. Selecting a channel

Selecting a channel:

> Start playback immediately.

Do not require a channel detail page first.

---

# 51. Switching channels while watching

While watching, provide an overlay/grid for selecting another channel.

First version:

```text
Player
  ↓
Open channel overlay
  ↓
Choose channel
  ↓
Start playback immediately
```

Future enhancement may include:
- previous/next channel
- groups
- current program
- mini-EPG

---

# 52. TV Guide / EPG

Provide one proper TV Guide view.

It should show:
- channels
- current programs
- upcoming programs
- times

The TV Guide is important but is not necessarily the primary viewing mode.

---

# 53. EPG interactions

Selecting a currently playing program:

> Start that channel immediately.

Selecting a future program:

> Show program information.

Reminders are **not required in the current version**.

---

# 54. Channel favorites

Allow explicit channel favorites.

Keep these separate from frequently watched behavior.

---

# 55. Hidden content

Users should be able to hide:
- playlists
- groups
- channels

Hidden content should normally disappear from:
- browsing
- normal search
- recommendations
- discovery

Hidden content must remain recoverable through Settings.

---

# 56. Movies

Primary goal:

> **Find a good movie.**

Typical intent:
- new/recent movie
- high IMDb rating
- good community/forum reception
- exact movie search

---

# 57. Movie discovery

Support:
- search
- genres
- ratings
- recommendations
- new movies
- new to your library
- playlist groups
- popular/trending content when available

---

# 58. Movie enrichment

Initial playlist data may be poor.

Progressively enrich:

```text
Playlist
    ↓
Identify movie
    ↓
Compare with previous catalog
    ↓
Detect newly added movie
    ↓
Match external metadata
    ↓
Add metadata
    ↓
Improve discovery
```

---

# 59. Movie metadata

Useful external metadata:
- title
- rating
- release year
- genres
- runtime
- cast
- director
- artwork
- plot
- popularity/trending information

Only attach metadata when the match is sufficiently confident.

Prefer missing information over confidently incorrect information.

---

# 60. New to your library

Differences between imports can identify newly added movies.

This should be exposed as a useful discovery concept:

> **New to Your Library**

It is more useful than presenting raw import statistics.

---

# 61. Movie detail

Selecting a movie opens a detail view.

It can contain:
- artwork
- title
- year
- rating
- genres
- description
- runtime
- cast
- Play
- trailer
- similar movies
- watched state
- playback progress

---

# 62. Movie selection behavior

Selecting a movie does **not** immediately start playback.

Open the movie detail.

The user then chooses:

> Play

If progress exists:

> Resume / Start from beginning

---

# 63. Series

Primary goal:

> **Make continuation extremely easy.**

Series UX prioritizes continuity over discovery.

---

# 64. Series state

Remember:
- exact episode
- playback position
- watched/unwatched state
- next episode

---

# 65. Series detail

Series detail should resemble a modern streaming service.

Possible structure:

```text
Series artwork
Title / metadata

Continue Watching
Next Episode

Seasons
  Season 1
    Episode 1
    Episode 2
    ...
```

Important information:
- artwork
- series information
- seasons
- episodes
- watched state
- progress
- episode information

---

# 66. Series selection

Selecting a series does not immediately play.

The user chooses a season/episode.

Selecting an episode starts playback.

---

# 67. Sports

The user follows:
- GAIS
- Frölunda

Sports should be proactively surfaced where useful.

Example:

```text
GAIS
Today · 19:00
```

The goal is to reduce the need to search manually.

---

# 68. Sports data

IPTV sports entries can be messy.

For example:

```text
14:50 Azerbajdzjan ‧ Litauen Viaplay SE 4/10 NXTSE
```

The app should eventually enrich raw sports information using:
- static/pre-baked metadata
- external metadata
- local matching
- user-added information where appropriate

The design must still work when enrichment is unavailable.

---

# 69. Low-cost enrichment

Hosting costs should remain low.

Static/pre-baked metadata is attractive where it can provide useful enrichment without requiring an expensive always-online backend.

---

# 70. Search

Search is mandatory.

On TV:

> Minimize text entry.

Important features:
- recent searches
- suggestions
- voice input
- predictive results where feasible
- filters/scopes

---

# 71. Search examples

Typical searches:

- GAIS
- The Last of Us
- Champions League
- a channel
- a movie
- a series

Search should feel like guided navigation rather than a form.

---

# 72. Search result presentation

Adapt richness to the result.

Large result set:

> Compact results.

Specific result:

> Enough information to identify it.

Broad discovery:

> Richer comparison.

Focused item:

> Full detail experience.

---

# 73. TV focus vs selection

Moving focus over an item can reveal lightweight information.

Selecting the item can open the richer experience.

This is important for D-pad scanning.

---

# 74. Saved interests

Search history should not automatically become permanent personalization.

A future concept may be:

> Saved Searches / Interests

It should be flexible enough to represent complex interests, not only individual entities.

The exact model/name remains a design exploration area.

---

# 75. Playback

Playback is part of the content model.

The application remembers playback state.

---

# 76. Playback priority

The priority order is:

1. Resume exact position
2. Subtitles
3. Next episode

---

# 77. Resume behavior

When content has progress:

> Ask whether to Resume or Start from beginning.

Never silently resume.

Example:

```text
The Last of Us

Resume from 32:14
Start from beginning
```

---

# 78. Subtitle behavior

Remember the user's latest subtitle choice.

Use it as the default next time where appropriate.

Still allow changing subtitles for each movie/episode.

The preference should evolve naturally from use.

---

# 79. Next episode

When an episode finishes:

> Automatically start the next episode.

The user has already established viewing intent by watching the series.

---

# 80. No inactivity detection

Do not automatically stop playback because the application thinks the user has fallen asleep.

---

# 81. Playback position

The latest saved playback position is the source of truth.

Do not attempt to infer whether the user was actively watching.

---

# 82. Recently Watched

Recently Watched is broader than a traditional Continue Watching list.

It may include:
- live channels
- movies
- series
- other meaningful recent interactions

However, keep content types grouped to avoid noise.

---

# 83. Playlist-independent vs playlist-dependent concepts

Some concepts belong to the playlist:

- content
- favorites
- recent state
- progress
- browsing context
- personalization

Some concepts can be global:

- application theme
- verbose output setting
- device-level preferences
- global UI settings

The design should clearly distinguish these.

---

# 84. Internal content model

The UI should not consume raw M3U/Xtream objects directly.

Conceptually:

```text
Playlist
  └── Source items
        ├── Live channel
        ├── Movie
        ├── Series
        └── Episode
```

Then add:

```text
External metadata
    +
User state
    +
Behavior
    +
Context
```

---

# 85. Content identity

Content identity is playlist-specific.

Therefore:

```text
Playlist A
    Movie X

Playlist B
    Movie X
```

are different application items even if external metadata identifies them as the same real-world movie.

This ensures independent:
- progress
- favorites
- availability
- recent state

---

# 86. Enrichment layers

## Layer 1 — Raw source data

Examples:
- name
- URL
- group
- logo
- source identifiers

## Layer 2 — Local normalization

Normalize:
- content type
- names
- IDs
- groups
- obvious structure

## Layer 3 — External metadata

Potentially add:
- artwork
- rating
- year
- genre
- description
- cast
- sports information

## Layer 4 — Personal context

Add:
- watched state
- progress
- favorites
- interests
- behavioral ranking
- recency

Each layer should be optional from a robustness perspective.

---

# 87. Metadata matching

External metadata should only be applied when the match is sufficiently confident.

Incorrect enrichment is worse than missing enrichment.

---

# 88. Error philosophy

Errors should be:
- understandable
- contextual
- actionable where possible
- non-destructive

Normal users should not see stack traces.

Verbose mode may expose technical diagnostics, but must still protect secrets.

---

# 89. Empty states

Empty states should explain why they are empty.

Example:

```text
No playlists

Add your first playlist
```

or:

```text
This playlist has no imported content yet.

Import now
```

Do not show unexplained blank screens.

---

# 90. Loading states

Important operations should show useful progress.

Example:

```text
Importing playlist

Downloading...
Processing...
Updating catalog...
```

Normal browsing should not feel blocked unnecessarily.

---

# 91. Refresh state model

A playlist can conceptually be in states such as:

```text
Never imported
Imported successfully
Refresh due
Refreshing
Refresh succeeded
Refresh failed
Resetting
Empty after reset
```

The UI should communicate the relevant state without exposing unnecessary implementation details.

---

# 92. Security and privacy

Protect source credentials.

Never expose credentials in:
- normal screens
- error messages
- verbose output
- user-visible logs

Viewing history and preferences are personal application data.

---

# 93. Performance constraints

The application may contain thousands of items.

The UX must therefore work with:
- local catalog/indexes
- lazy loading
- efficient search
- cached artwork
- incremental enrichment

Do not assume that all content can be rendered or loaded simultaneously.

---

# 94. Import vs browsing

The architecture should separate remote import from normal browsing.

```text
Remote IPTV source
        ↓
      Import
        ↓
   Local catalog
        ↓
      Browse
```

The UI should browse the local catalog rather than repeatedly processing the remote playlist.

This is important for both performance and perceived responsiveness.

---

# 95. Context preservation

Preserve useful user context whenever possible.

Examples:
- last active playlist
- recent content
- series progress
- subtitle choice
- browsing context

The application should feel continuous rather than stateless.

---

# 96. TV interaction principles

The TV experience assumes:
- D-pad navigation
- clear focus
- large targets
- predictable directional movement
- minimal typing
- limited modal interruption

Focus and selection are distinct.

Users should be able to scan content without opening every item.

---

# 97. What the application should NOT do

The application should not:

- autoplay on startup
- merge playlists
- silently switch playlists
- let raw playlist groups dictate the entire UX
- require external metadata for basic playback
- turn every search into permanent personalization
- silently resume playback
- interrupt active viewing for automatic refresh
- expose credentials
- partially replace a catalog after failed normal refresh
- restore the old catalog after an intentional reset
- deduplicate source entries automatically
- overwhelm Home with endless content
- make unpredictable personalization decisions
- become a generic Netflix clone

---

# 98. Conceptual information architecture

A possible structure:

```text
Home
│
├── Recently Watched
│   ├── Live TV
│   ├── Movies
│   └── Series
│
├── Your Channels
│
├── Dashboard / What's On / Sports
│
├── Live TV
│   ├── Your Channels
│   ├── What's On Now
│   ├── Groups
│   ├── All Channels
│   └── TV Guide
│
├── Movies
│   ├── Discover
│   ├── New to Your Library
│   ├── Genres
│   ├── Search
│   └── Recommendations
│
├── Series
│   ├── Continue Watching
│   ├── Series
│   └── Search
│
└── Search
```

This is a conceptual model, not a requirement that every item becomes a permanent navigation destination.

---

# 99. Success scenarios

## Scenario 1 — Habit

User opens the app.

Recently watched channels are visible.

User selects one.

Playback starts immediately.

## Scenario 2 — Find something good

User opens Home.

They see a few relevant/high-quality movies.

They open a movie.

They inspect the details.

They select Play.

## Scenario 3 — Continue a series

User opens Home.

They see their series under Recently Watched / Continue Watching.

They select the next episode.

Playback starts at the correct position.

## Scenario 4 — Find a channel

User opens Live TV.

They see their channels or search.

They select a channel.

Playback starts immediately.

## Scenario 5 — Find a movie

User searches using voice, suggestions, or minimal typing.

They select a result.

Movie details open.

They choose Resume or Play.

## Scenario 6 — Sports

User opens Home.

They see:

```text
GAIS
Today · 19:00
```

They can quickly determine where/how to watch.

## Scenario 7 — Multiple playlists

The app starts in the last-used playlist.

User switches playlist through Settings.

The selected playlist refreshes if necessary.

Its independent content universe is shown.

## Scenario 8 — Provider failure

A scheduled refresh fails.

The user sees an understandable error.

The previous catalog remains usable.

---

# 100. Success criteria

The product succeeds if it makes these tasks feel easy:

- open the app and immediately understand what to do
- resume recently watched content quickly
- find a familiar channel with very few interactions
- find a specific movie or series despite messy IPTV naming
- discover something interesting without browsing thousands of raw entries
- understand what is currently on TV
- discover relevant sports
- switch playlists without confusion
- understand when playlist data is stale
- recover from failed imports without losing the working catalog
- navigate comfortably with a TV remote
- use the same conceptual application on phone and TV

---

# 101. Desired product feeling

The application should feel:

- fast
- calm
- useful
- personal
- visually rich
- predictable
- understandable
- respectful of user control

It should not feel:

- like a raw IPTV browser
- like a giant database
- like an advertising feed
- like an AI deciding what the user should watch
- like a complicated configuration application
- like a Netflix clone

---

# 102. Design decisions intentionally left open

The designer should explore and propose the best solutions for:

- exact Home layout
- navigation style
- card sizes
- horizontal vs vertical composition
- focus behavior
- TV Guide layout
- Live TV overlay
- search interaction
- voice search entry point
- movie discovery layout
- series continuation layout
- sports presentation
- dashboard composition
- personalization controls
- saved-interest UX
- responsive behavior
- empty/loading/error states
- animation
- transitions
- exact visual theme

These should be derived from the principles in this document.

---

# 103. Instructions to the UX/UI designer

Do **not** treat this document as a checklist of screens.

Design around the underlying user goal:

> **"I want to find something I probably want to watch, select it easily, and start watching."**

When multiple solutions are possible, prefer the solution that:

1. reduces cognitive load
2. reduces D-pad interaction
3. makes likely choices visible
4. preserves user control
5. works with poor IPTV data
6. works without external metadata
7. scales to thousands of items
8. adapts naturally between TV and phone
9. remains understandable without explanation
10. becomes more useful over time without becoming unpredictable

Do not blindly implement early UI ideas. Treat the requirements as product intent and constraints, then propose the strongest UX solution.

---

# 104. Final product definition

This application should be understood as:

> **A personal TV discovery and viewing experience built on top of IPTV sources.**

The IPTV source provides availability.

The application provides:

- organization
- search
- context
- enrichment
- continuity
- personalization
- discovery
- efficient TV interaction

The most important outcome is simple:

> **When the user opens the app, it should be easy to find something they probably want to watch.**
