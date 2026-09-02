# IPTV App — UX, Information Architecture & Home Screen Implementation Specification

## 1. Purpose

This document captures the current UX/UI decisions and implementation guidance for a modern IPTV application built with Flutter.

The document is intended to be handed to an AI/software implementation agent as the product and UX baseline.

The application should feel like a polished streaming service while remaining optimized for TV remote control, large screens, large IPTV playlists, and fast access to live television.

---

# 2. Product vision

The application supports:

- Live TV
- Movies / VOD
- TV series
- Multiple M3U playlists per household
- EPG
- Catch-up
- Subtitles
- Multiple audio tracks
- Continue Watching
- Recently Watched
- Watch History, optionally disabled
- Favorites

Planned later:

- User profiles
- Xtream Codes
- Additional external metadata providers
- More content sources
- Recommendations
- Potentially richer personalization

The primary target is a single household TV experience.

Initial platform:

- LG webOS
- Flutter UI
- Platform-specific video player

Later:

- Apple TV
- Samsung TV
- Windows

The architecture must therefore avoid coupling the UX or domain model to LG/webOS-specific behavior.

---

# 3. Core UX principle

The application is not an M3U browser.

The M3U is an input/source format.

The product should behave like a streaming service.

The Home screen should answer:

> What do I want to watch right now?

It should not primarily answer:

> Which M3U category do I want to browse?

This distinction is important throughout the architecture.

---

# 4. Example M3U structure

The source playlist contains entries such as:

```text
#EXTINF:-1 xui-id="{XUI_ID}" tvg-id="" tvg-name="[NO] LEGO Masters Norge (2021) S01 E18" tvg-logo="..." group-title="Norway (Serie)",[NO] LEGO Masters Norge (2021) S01 E18
http://.../series/.../1082390.mkv

#EXTINF:-1 xui-id="{XUI_ID}" tvg-id="" tvg-name="[NO] LEGO Masters Norge (2021) S01 E19" tvg-logo="..." group-title="Norway (Serie)",[NO] LEGO Masters Norge (2021) S01 E19
http://.../series/.../607520.mkv

#EXTINF:-1 xui-id="{XUI_ID}" tvg-id="" tvg-name="Pine Gap S01 E05" tvg-logo="..." group-title="TV (Nordicsubs) (Serie)",Pine Gap S01 E05
http://.../series/.../709264.mkv

#EXTINF:-1 xui-id="{XUI_ID}" tvg-id="" tvg-name="Pine Gap S01 E06" tvg-logo="..." group-title="TV (Nordicsubs) (Serie)",Pine Gap S01 E06
http://.../series/.../709265.mkv
```

The playlist can contain around 500,000 lines.

It may contain:

- Live TV
- Movies
- Series episodes
- Provider-specific groups
- Artwork URLs
- TV identifiers
- Stream URLs

---

# 5. Important content normalization decision

Series must be first-class entities.

The following:

```text
Pine Gap S01 E05
Pine Gap S01 E06
```

must not become two unrelated pieces of content.

They should become:

```text
Series
└── Pine Gap
    └── Season 1
        ├── Episode 5
        └── Episode 6
```

Likewise:

```text
LEGO Masters Norge (2021) S01 E18
LEGO Masters Norge (2021) S01 E19
```

becomes:

```text
Series
└── LEGO Masters Norge (2021)
    └── Season 1
        ├── Episode 18
        └── Episode 19
```

The M3U parser should extract season/episode information where possible.

The UI should never need to parse `S01 E06` itself.

---

# 6. Recommended conceptual domain model

Use a normalized model similar to:

```text
Playlist
    |
    +-- Content
          |
          +-- LiveChannel
          |
          +-- Movie
          |
          +-- SeriesEpisode
                    |
                    +-- Series
                    |
                    +-- Season
```

Suggested entities:

## Playlist

```text
id
name
source_url
enabled
last_updated_at
last_update_status
```

## LiveChannel

```text
id
playlist_id
title
tvg_id
tvg_name
logo_url
group_id
stream_url
```

## Movie

```text
id
playlist_id
title
logo_url
group_id
stream_url
```

## Series

```text
id
playlist_id
title
artwork_url
```

## Season

```text
id
series_id
season_number
```

## SeriesEpisode

```text
id
series_id
season_id
episode_number
title
artwork_url
stream_url
```

The exact schema may differ, but the separation of Series / Season / Episode should remain.

---

# 7. User state must be separate from playlist content

Do not store user-specific state directly in playlist content records.

Conceptually:

```text
User / Profile
    |
    +-- Favorites
    |
    +-- WatchHistory
    |
    +-- ContinueWatching
    |
    +-- PlaybackPosition
    |
    +-- Preferences
```

This becomes important when profiles are added later.

Suggested playback state:

```text
content_id
profile_id / user_id
position
duration
last_watched_at
completed
```

For a series episode, the playback state references the episode.

---

# 8. Information architecture

Primary navigation:

```text
HOME
LIVE TV
MOVIES
SERIES
SEARCH
```

Settings is secondary.

Do not make Favorites a primary top-level navigation item.

Favorites are a property of content and should be accessible in relevant contexts.

Recommended high-level architecture:

```text
Home
│
├── Continue Watching
├── Live TV
├── Favorites
└── Recently Watched

Live TV
│
├── All Channels
├── Categories
├── Favorites
├── EPG
└── Catch-up

Movies
│
├── All
├── Categories
├── Favorites
└── Movie Details

Series
│
├── All
├── Categories
├── Favorites
├── Series Details
│   └── Seasons
│       └── Episodes
│
Search
│
├── Channels
├── Movies
├── Series
└── Episodes

Settings
│
├── Playlists
├── Playback
├── Subtitles
├── Audio
├── EPG
├── History
└── Application
```

Profiles and Xtream Codes are future features.

---

# 9. Home screen philosophy

The Home screen should be content-first.

Initial dynamic sections:

1. Continue Watching
2. Live TV
3. Favorites
4. Recently Watched

However, sections should only appear when they contain useful content.

Do not render empty sections.

For example, a new user may see:

```text
HOME

Live TV
Movies
Series
```

A user with viewing history may see:

```text
HOME

Continue Watching
Live TV
Favorites
Recently Watched
```

---

# 10. Do not use a giant hero initially

Although Netflix-style hero banners are attractive, the current source data does not reliably provide:

- Descriptions
- Ratings
- Popularity
- Actors
- Genres
- Release metadata
- Background artwork

Therefore the first Home implementation should not depend on a large hero area.

A content-first Home screen is faster and more useful.

A hero can be introduced later when a metadata system exists.

---

# 11. Home screen 1920×1080 target

Primary design target:

```text
1920 × 1080
16:9
```

Recommended safe area:

```text
Left/right: approximately 90 px
Top: approximately 60 px
Bottom: approximately 60 px
```

Critical UI should not be placed directly against the physical screen edge.

The design must also scale gracefully to other TV resolutions.

---

# 12. Header

Recommended header height:

```text
~88 px
```

Horizontal padding:

```text
~90 px
```

Structure:

```text
[LOGO]   HOME   LIVE TV   MOVIES   SERIES   SEARCH                    [⚙]
```

Navigation spacing:

```text
Logo → navigation: ~50–60 px
Navigation item gap: ~32–40 px
```

HOME is active on initial launch.

The active item should have a subtle but clear indicator.

Do not make the header unnecessarily tall.

---

# 13. Home screen composition

Conceptual composition:

```text
┌──────────────────────────────────────────────────────────────────────┐
│ LOGO   HOME   LIVE TV   MOVIES   SERIES   SEARCH                 ⚙  │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│ Continue Watching                                      See all →     │
│                                                                      │
│ [card]    [card]    [card]    [card]    [card]                      │
│                                                                      │
│ Live TV                                                See all →     │
│                                                                      │
│ [channel] [channel] [channel] [channel] [channel] [channel]         │
│                                                                      │
│ Favorites                                              See all →     │
│                                                                      │
│ [card]    [card]    [card]    [card]                                │
│                                                                      │
│ Recently Watched                                      See all →      │
│                                                                      │
│ [card]    [card]    [card]    [card]                                │
└──────────────────────────────────────────────────────────────────────┘
```

The whole Home page scrolls vertically.

Each content row scrolls horizontally.

---

# 14. Continue Watching

Continue Watching is the highest-priority personalized section.

Card dimensions:

```text
Width: ~300 px
Height: ~169 px
Aspect ratio: 16:9
Gap: ~32 px
```

Approximately five cards should be visible depending on viewport and safe area.

Example:

```text
Continue Watching

┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│               │  │               │  │               │
│   PINE GAP    │  │ LEGO MASTERS  │  │  THIS IS US   │
│               │  │               │  │               │
└───────────────┘  └───────────────┘  └───────────────┘
 S01 E06           S01 E19           S05 E14
 ━━━━━━━━━━━       ━━━━━━━           ━━━━━━━━
```

Show:

- Artwork
- Title
- Season / episode for series
- Playback progress
- Optionally remaining time

Selecting a Continue Watching item should resume playback immediately.

Desired interaction:

```text
Home
→ Continue Watching
→ OK
→ Resume playback
```

Avoid:

```text
Home
→ Series
→ Series details
→ Season
→ Episode
→ Resume
```

---

# 15. Continue Watching semantics

Continue Watching means unfinished content.

Example:

```text
Pine Gap
S01 E06
42% watched
```

When playback reaches completion:

- Remove the item from Continue Watching
- Keep it in Recently Watched

Future enhancement:

- Automatically suggest/play next episode
- "Play next"
- Season progress

---

# 16. Live TV Home row

Live TV is the second important Home section.

Use compact landscape cards.

Approximate:

```text
Width: ~220 px
Height: ~124 px
Aspect ratio: 16:9
Gap: ~24–28 px
```

Example:

```text
Live TV

┌────────────────────┐  ┌────────────────────┐
│                    │  │                    │
│       SVT1         │  │        TV4         │
│                    │  │                    │
└────────────────────┘  └────────────────────┘
SVT1 HD                 TV4
Rapport                 Nyheterna
```

Where EPG data exists, display the currently playing program.

The Home Live TV row should not simply show the first channels in the playlist.

Recommended ordering:

1. Favorite channels
2. Recently watched channels
3. Frequently watched channels
4. Remaining channels

The Home query should only retrieve a small number of channels.

---

# 17. Favorites

Favorites should appear on Home only when there are favorites.

Potential presentation:

```text
Favorites

Channels
[ SVT1 ] [ TV4 ] [ NRK1 ]

Movies & Series
[ Pine Gap ] [ Star Wars ] [ ... ]
```

Favorites should be available elsewhere as appropriate.

---

# 18. Recently Watched

Recently Watched is different from Continue Watching.

Continue Watching:

> I have not finished this.

Recently Watched:

> I watched this recently.

Recently Watched can include:

- Completed movies
- Completed episodes
- Channels
- Partially watched content

It should provide fast access back to recently consumed content.

Watch History should be optionally disableable in settings.

---

# 19. Dynamic Home behavior

Do not render empty rows.

New user:

```text
HOME

Live TV
Movies
Series
```

After watching:

```text
HOME

Continue Watching
Live TV
Favorites
Recently Watched
```

The Home screen should adapt naturally to the user's state.

---

# 20. Horizontal scrolling

Each content row is horizontally scrollable.

The whole Home screen is vertically scrollable.

Remote behavior:

```text
← / →   Move within row
↑ / ↓   Move between rows
OK      Select
BACK    Navigate back
```

A subtle right-side fade/overflow indicator can communicate that more items exist.

Do not render thousands of cards.

Use lazy/virtualized rendering.

---

# 21. Focus behavior

Focus is critical for TV.

Normal card:

```text
┌───────────────┐
│               │
│    artwork    │
│               │
└───────────────┘
```

Focused card:

```text
╔═══════════════╗
║               ║
║    artwork    ║
║               ║
╚═══════════════╝
```

Recommended focus behavior:

```text
Scale normal: 1.00
Scale focused: approximately 1.04–1.07
Animation: approximately 120–180 ms
```

Focused item should have:

- High-contrast outline
- Subtle glow/shadow
- Slight scale-up
- Strong enough visual contrast to be obvious from several meters away

Do not overuse animation.

Responsiveness is more important.

---

# 22. Focus navigation requirements

Directional navigation must be deliberately designed.

Requirements:

- Left/right moves within a row
- Up/down moves between rows
- Focus should remain predictable
- Returning to a screen should restore useful previous focus
- Returning from Player should restore the relevant Home/Live TV focus

Example:

```text
Home
→ Live TV
→ Player
→ BACK
→ previous Live TV item focused
```

Do not build an enormous focus tree for all 500,000 playlist items.

Only visible/materialized UI should need active widgets/focus nodes.

---

# 23. Typography

Initial 1080p reference values:

```text
Navigation:       22–24 px
Section title:    28–32 px
Card title:       20–22 px
Secondary text:   16–18 px
Body/help text:   18–20 px
Future hero title: 40–56 px
```

Use a highly readable font.

Avoid thin weights.

Recommended:

```text
Primary: medium/semibold
Secondary: regular
Focused: semibold/bold
```

These are starting values and should be validated on actual TV hardware.

---

# 24. Visual style

Target:

- Dark cinematic background
- Off-white primary text
- Muted secondary text
- One restrained accent color
- Moderate corner radius
- Subtle shadows
- High-quality artwork
- Strong focus state
- Generous whitespace
- Minimal clutter

The design can take inspiration from Netflix, Disney+, Max, Hulu and other established streaming services in terms of interaction patterns.

Do not copy any one service's visual identity.

Create an original design language.

---

# 25. Animation

Use short, purposeful animations.

Recommended:

```text
Focus:       120–180 ms
Page/row:    150–250 ms
```

Avoid:

- Long transitions
- Large parallax effects
- Constant motion
- Heavy visual effects
- Animations that interfere with remote navigation

---

# 26. Artwork handling

Do not download every image when importing the M3U.

Store the artwork URL.

Load images lazily when needed.

Use:

- Image cache
- Local caching
- Placeholders
- Error fallback
- Appropriate requested image dimensions

The application should not assume all `tvg-logo` URLs contain suitable artwork.

Some provider logos may be:
- Channel logos
- Posters
- Episode images
- Invalid/broken
- Very large images

The UI should handle all cases.

---

# 27. M3U import architecture

The M3U can be approximately 500,000 lines.

Never do:

```text
Download complete file
→ parse entire file into huge Dart list
→ build UI from list
```

Instead use:

```text
M3U URL
   ↓
Streaming download
   ↓
Streaming parser
   ↓
Normalizer
   ↓
SQLite
   ↓
Indexed repository queries
   ↓
Small UI result sets
```

The import process should be memory-conscious.

---

# 28. SQLite recommendation

SQLite is a good fit for the local normalized content database.

Recommended to keep:

1. Original downloaded M3U cache
2. Normalized SQLite database

The original M3U cache can be useful for:

- Reprocessing
- Debugging
- Comparing versions
- Recovery

The UI should never parse the original M3U at runtime.

The UI should operate on normalized database queries.

---

# 29. Playlist updates

Users should be able to manually trigger:

```text
Update playlist
```

There should also be optional scheduled updates, initially perhaps weekly.

Updates should happen in the background when the platform permits it.

Requirements:

- Do not block Home
- Do not interrupt playback
- Do not expose partially imported content
- Keep previous working database if update fails

Recommended update pipeline:

```text
Download
   ↓
Parse
   ↓
Normalize
   ↓
Write staging database
   ↓
Validate
   ↓
Commit/swap
```

If an update fails:

```text
Keep previous working database
Report update failure
Retry later
```

Future optimization:

- Incremental updates
- Stable content identifiers
- Hash comparison
- Insert/update/delete only changed records

---

# 30. Home database queries

Home must never query the entire playlist.

Example conceptual queries:

```text
Continue Watching → LIMIT 10
Live TV           → LIMIT 10
Favorites         → LIMIT 10
Recently Watched  → LIMIT 10
```

Use proper indexes.

The Home screen should retrieve only what it needs.

Potential indexes should support:

- playlist_id
- content type
- series_id
- season_id
- favorites
- last_watched_at
- playback state
- title/search fields
- category/group

Exact indexing should be determined after schema design and profiling.

---

# 31. Home Flutter architecture

Suggested conceptual widget tree:

```text
HomeScreen
├── AppHeader
│   ├── Logo
│   ├── PrimaryNavigation
│   └── SettingsButton
│
└── HomeScrollView
    ├── ContinueWatchingSection
    │   └── ContentCarousel
    │
    ├── LiveTvSection
    │   └── ChannelCarousel
    │
    ├── FavoritesSection
    │   └── ContentCarousel
    │
    └── RecentlyWatchedSection
        └── ContentCarousel
```

Rows should be data-driven.

Conceptual model:

```text
HomeSection
- title
- sectionType
- items
- cardType
- onSeeAll
```

This makes rows easy to add/remove dynamically.

---

# 32. Initial populated Home state

If the user has watch history:

```text
HOME

Continue Watching

[Pine Gap S01 E06]
[LEGO Masters S01 E19]
[This Is Us S05 E14]

Live TV

[SVT1]
[TV4]
[NRK1]
[TV2]

Favorites

[SVT1]
[Pine Gap]
[Star Wars]

Recently Watched

[TV4]
[LEGO Masters]
[Star Wars]
```

Continue Watching should automatically move to the top once it contains content.

---

# 33. Initial empty/new-user state

Assume:

- At least one playlist exists
- No favorites
- No watch history
- No Continue Watching

The Home screen should begin with:

```text
HOME

Live TV

[channel] [channel] [channel] [channel] [channel]

Movies

[poster] [poster] [poster] [poster] [poster]

Series

[poster] [poster] [poster] [poster] [poster]
```

No empty Favorites section.

No empty Continue Watching section.

No empty Recently Watched section.

Initial focus should be the first Live TV channel.

Desired first-time path:

```text
Launch
→ Home
→ first Live TV channel
→ OK
→ Player
```

This minimizes time-to-content.

---

# 34. Search considerations

Search is important because playlists may contain tens or hundreds of thousands of items.

Search must operate against normalized/indexed data.

Search should cover:

- Channels
- Movies
- Series
- Episodes

Do not scan the complete M3U during search.

Search results should be paginated/lazy.

TV search should be designed around remote input.

Future enhancement:
- Keyboard/input optimization per platform
- Search history
- Fuzzy matching
- Normalized title matching

---

# 35. Categories

Raw provider groups such as:

```text
Norway (Serie)
Denmark (Serie)
TV (Nordicsubs) (Serie)
Movies (Nordicsubs) (VOD)
```

should not become the application's fundamental information architecture.

Store provider/source group information.

Then derive application-level concepts such as:

```text
content_type
country
category
language
```

where reliable.

The UI should expose useful categories rather than forcing the user to understand provider-specific naming.

---

# 36. Series details

Series navigation should eventually look like:

```text
Series
    ↓
Pine Gap
    ↓
Season 1
    ↓
Episode list
```

Example:

```text
Pine Gap

Season 1

[Episode 1] [Episode 2] [Episode 3] [Episode 4]
```

The application should be able to identify:

- Series title
- Season number
- Episode number
- Episode title
- Artwork
- Stream URL

Future enhancements:
- Episode descriptions
- Cast
- Genres
- Release year
- Background artwork

These can come from external metadata providers later.

---

# 37. Player integration

The Home UI should treat the Player as a separate platform abstraction.

Conceptually:

```text
Flutter UI
    ↓
Playback service
    ↓
Platform player
```

The UI should not be coupled directly to a specific LG player implementation.

Player requirements eventually include:

- Live playback
- VOD
- Pause/play
- Seeking
- Channel switching
- EPG
- Catch-up
- Subtitles
- Multiple audio tracks
- Playback position
- Resume
- Next episode

The exact player architecture is a separate implementation task.

---

# 38. State restoration

The application should restore sensible state.

Examples:

```text
Home → Live TV → Player → Back
```

should restore:

- Home scroll position
- Focused item
- Selected row

Likewise:

```text
Series → Series details → Episode → Player → Back
```

should restore:

- Series
- Season
- Episode focus

This makes TV navigation feel natural.

---

# 39. Loading behavior

The Home shell should render quickly.

Do not block the entire Home screen on slow operations.

Preferred:

```text
Render shell
↓
Load small database queries
↓
Render sections
↓
Lazy load artwork
```

Use placeholders/skeletons if useful.

Avoid a full-screen spinner for normal Home loading.

---

# 40. Error handling

Broken artwork:

```text
Show placeholder
Keep content usable
```

Broken stream:

```text
Player handles playback error
Home remains usable
```

Playlist update failure:

```text
Keep previous database
Display non-blocking error/status
```

Database corruption/recovery should preserve the last known working playlist when possible.

---

# 41. Multiple playlists

Users can have multiple M3U playlists.

The UI should not force users to understand which source an item came from during normal browsing.

However, source/playlist information should be available where useful, particularly in settings and diagnostics.

The normalized content model should retain:

```text
playlist_id
```

so source ownership remains clear.

Potential future behavior:

- Combined Home
- Combined Live TV
- Combined Movies
- Combined Series
- Optional source filtering

Do not make source selection mandatory for ordinary playback.

---

# 42. Future profiles

Profiles are a second-phase feature.

The current architecture should nevertheless keep user-specific state separate.

Future:

```text
Household
├── Profile A
│   ├── Favorites
│   ├── History
│   └── Continue Watching
│
└── Profile B
    ├── Favorites
    ├── History
    └── Continue Watching
```

Do not build profile-specific UI into V1 unnecessarily.

---

# 43. Future Xtream Codes

Xtream Codes is a second-phase source provider.

The application architecture should allow:

```text
M3U provider
Xtream provider
Future providers
        ↓
Normalized domain model
        ↓
SQLite
        ↓
Same UI
```

This is another reason not to make M3U fields the application's permanent domain model.

---

# 44. Implementation priorities

Recommended implementation order:

## Phase 1 — Data foundation

1. M3U streaming downloader
2. Streaming parser
3. Content type detection
4. Series/season/episode normalization
5. SQLite schema
6. Indexes
7. Repository/query layer
8. Playlist staging/update mechanism

## Phase 2 — Core navigation

1. App shell
2. Header
3. Focus system
4. Home
5. Live TV
6. Movies
7. Series
8. Search

## Phase 3 — Playback state

1. Player abstraction
2. Playback position
3. Continue Watching
4. Recently Watched
5. Favorites

## Phase 4 — TV features

1. EPG
2. Catch-up
3. Audio tracks
4. Subtitles

## Phase 5 — polish

1. Image caching
2. Loading states
3. Error states
4. Focus animations
5. Accessibility/readability
6. Performance profiling on real TV hardware

## Phase 6 — future

1. Xtream Codes
2. External metadata
3. Profiles
4. Recommendations
5. Additional platforms

---

# 45. Performance acceptance criteria

The implementation should satisfy:

- Importing a very large M3U does not cause excessive memory usage.
- UI remains responsive while import/update is running.
- Home never loads the full content database.
- Carousels use lazy rendering.
- Images are lazy loaded and cached.
- Search is database/index based.
- Playlist updates do not interrupt playback.
- Failed updates do not destroy the previous working database.
- Returning from Player restores useful focus.
- Remote navigation feels immediate.
- The application is usable on real LG webOS hardware, not only desktop Flutter.

---

# 46. Home screen acceptance criteria

The Home screen is successful when:

1. It looks like a premium TV streaming application.
2. It is optimized for 10-foot viewing.
3. Live TV can be started immediately.
4. Continue Watching resumes content directly.
5. Empty sections are hidden.
6. Horizontal rows scroll smoothly.
7. Up/down focus movement is predictable.
8. Focus is clearly visible from several meters away.
9. Home queries retrieve only small result sets.
10. Artwork is lazy loaded.
11. The Home screen remains responsive during playlist updates.
12. Returning from Player restores focus and scroll state.
13. Series are represented as Series → Season → Episode.
14. The design does not depend on raw M3U group names.
15. The UI can later consume Xtream Codes or other sources without redesigning the Home experience.

---

# 47. Recommended first implementation artifact

Before implementing the complete application, create these Flutter components:

```text
AppShell
AppHeader
FocusContainer
HomeScreen
HomeSection
ContentCarousel
ContentCard
ChannelCard
ProgressIndicator
```

Then build a static/mock repository containing approximately:

- 5 Continue Watching items
- 6 Live TV channels
- 5 Favorites
- 5 Recently Watched

Use that to validate:

- 1920×1080 layout
- Focus behavior
- Remote navigation
- Vertical/horizontal scrolling
- Typography
- Card sizing
- Loading states

Only after the interaction model feels correct should the real SQLite repository be connected.

---

# 48. Design rule for the implementation agent

Do not optimize the implementation around the current sample M3U alone.

Build the product around these abstractions:

```text
SOURCE
  ↓
NORMALIZED CONTENT
  ↓
LOCAL DATABASE
  ↓
REPOSITORY
  ↓
VIEW MODEL
  ↓
TV UI
  ↓
PLAYER
```

The source can change.

The content provider can change.

The metadata source can change.

The player can change.

The Home UX should remain stable.

---

# 49. Current design decision summary

### We have decided

- Flutter UI
- LG webOS as initial target
- 1920×1080 10-foot design target
- Remote-first navigation
- Dark streaming-service visual style
- Original design inspired by established streaming UX patterns
- Primary navigation: Home / Live TV / Movies / Series / Search
- Settings as secondary navigation
- Content-first Home
- No giant hero initially
- Continue Watching first when populated
- Live TV prioritized for quick access
- Favorites and Recently Watched are dynamic Home sections
- Empty sections hidden
- Horizontal content rows
- Vertical Home scrolling
- Strong focus states
- 16:9 landscape cards for initial Home design
- Lazy rendering
- Lazy image loading
- SQLite normalized content database
- Original M3U retained as cache
- Streaming M3U parser
- Background playlist updates
- Staged database update/swap
- Previous database preserved if update fails
- Series/Season/Episode normalization
- User state separate from playlist data
- EPG and catch-up planned
- Subtitles and multiple audio tracks planned
- Multiple playlists supported
- Xtream Codes planned later
- Profiles planned later
- External metadata planned later

### The most important architectural rule

**The M3U is a source, not the application's domain model.**

The UI should operate on normalized, indexed local data.

### The most important UX rule

**The user should be able to go from launching the application to watching Live TV with as few remote-control actions as possible.**
