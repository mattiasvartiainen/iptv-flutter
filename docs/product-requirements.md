# Product Requirements

## 1. Product goal

Provide a simple, reliable IPTV player for recent LG TVs. A user should be able to install the app, add an M3U/M3U8 URL, browse the imported catalog, and play a Live TV stream with only the TV remote.

## 2. MVP boundary

### In scope

- Installable and launchable webOS application.
- First-run setup screen for adding a playlist URL.
- Local persistence of playlist URLs, settings, and the last selected context.
- M3U/M3U8 URL fetching and parsing.
- Classification into Live TV and Movies/VOD using playlist metadata and safe fallbacks.
- Category/group browsing.
- Search across imported content.
- Content details view with play action.
- Common HLS playback through a dedicated player abstraction.
- Loading, empty, error, retry, and invalid-playlist states.
- Remote-control navigation with a clearly visible focus indicator.
- Developer-mode packaging/install workflow for LG TVs.

### Out of scope for MVP

- Xtream Codes API.
- Local playlist file import.
- EPG, catch-up, DVR, recording, or timeshift.
- Series/seasons/episodes.
- Subtitles, multiple audio tracks, and advanced playback controls.
- User accounts, backend services, cloud sync, analytics, or payments.
- Broad codec support beyond what the target webOS media stack supports reliably.
- Automatic playlist discovery or provider recommendations.

## 3. Primary user stories

### Installation and startup

- As a user, I want to install the packaged app on my LG TV so I can use it without another device.
- As a user, I want the app to open in a usable state after installation.
- As a user, I want clear setup guidance when no playlist has been configured.
- As a user, I want returning to the app from Home/Recents to restore a sensible screen and focus position.

### Playlist setup

- As a user, I want to enter an M3U/M3U8 URL using the TV remote.
- As a user, I want the URL to be validated before it replaces my current playlist.
- As a user, I want playlist loading progress and a useful error if the URL cannot be fetched or parsed.
- As a user, I want a successfully loaded playlist to remain available after restarting the app.

### Browsing and search

- As a user, I want separate entry points for Live TV and Movies/VOD.
- As a user, I want to browse groups/categories from my playlist.
- As a user, I want to search by title across the available content type.
- As a user, I want empty categories and no-result searches to explain what happened.

### Playback

- As a user, I want to start a stream from a focused item with one clear action.
- As a user, I want a loading state while the stream starts.
- As a user, I want playback errors to offer retry and return-to-browse actions.
- As a user, I want to exit playback with the remote and return to the previous browsing context.

## 4. Navigation model

The MVP should use a small, predictable state model:

1. `Setup` — no usable playlist is configured.
2. `Home` — Live TV, Movies/VOD, Search, Settings.
3. `Catalog` — groups and content cards/list rows.
4. `Details` — metadata and play action.
5. `Player` — HLS playback, basic controls, error/retry.
6. `Settings` — playlist management and app preferences.

Back navigation must be deterministic: Player → Details/Catalog → Home; Setup has no hidden dead end.

## 5. Functional requirements

### Playlist

- Accept a URL string and trim surrounding whitespace.
- Support standard M3U/M3U8 text playlists over supported network protocols.
- Preserve relevant `#EXTINF` attributes, including title, group/category, logo, and media URL.
- Handle missing or malformed metadata without crashing; use deterministic fallback values.
- Do not log or display playlist credentials unnecessarily.
- Replace the active catalog only after a complete fetch and parse succeeds.

### App lifecycle

- Handle the webOS foreground launch event and any launch parameters without assuming a clean process start.
- Handle relaunch separately from first launch so returning to the app does not refetch or reset state unnecessarily.
- Handle visibility changes by pausing or releasing nonessential work when hidden and restoring UI/player state when visible.
- Do not add an in-app close button; follow the platform close behavior.
- Define the Back behavior for every screen and preserve the platform path for leaving the app from the root screen.

### Catalog

- Normalize each item to one internal content model.
- Use group metadata first for grouping.
- Provide a stable fallback group such as `Uncategorized`.
- Distinguish Live TV from Movies/VOD using explicit metadata where available and documented heuristics otherwise.
- Keep the parser independent of the UI so alternate layouts can reuse the same catalog.

### Search

- Search title and useful secondary fields such as group and channel name.
- Normalize case and whitespace for matching.
- Update results without refetching the playlist.
- Keep search usable with the remote keyboard/input method.

### Playback

- Route stream startup through a playback service/interface, not directly from catalog components.
- Start with HLS URLs and the native webOS media capability available to the app.
- Expose playback states: idle, loading, playing, paused if supported, ended, and error.
- Never make an unhandled media error a dead end; provide retry and navigation actions.

## 6. Non-functional requirements

- Remote-first: every interactive control is reachable without a pointer.
- Focus is always visible and never lost after a view update.
- UI remains legible from typical viewing distance.
- Avoid blocking the UI while fetching or parsing large playlists.
- Use bounded rendering or pagination/virtualization if catalogs are large.
- Keep credentials out of analytics, debug output, and user-facing errors.
- Use modular Dart services and Flutter widgets with clear boundaries so UI experiments do not change parsing or playback behavior.
- Treat launch, relaunch, visibility, and termination as platform-driven lifecycle events.
- Avoid assuming a termination callback exists; persist important state before transitions that can hide or suspend the app.

## 7. MVP acceptance criteria

- A developer can package and install the app on a target LG TV using the documented workflow.
- First launch shows setup when no valid local playlist exists.
- A valid M3U/M3U8 URL can be entered with the remote and saved locally.
- The app fetches and parses the playlist without freezing the main UI for normal playlists.
- Live TV and Movies/VOD are discoverable from the home screen when present.
- A user can move focus through groups/items, open details, and return using the remote.
- Search returns matching catalog items and handles no matches.
- A supported HLS stream starts in the player, or an actionable error is shown.
- Restarting the app restores the saved playlist and settings.
- Hiding and restoring the app does not lose the current navigation context or leave playback resources running unnecessarily.
- Invalid URL, network failure, empty playlist, parse failure, and playback failure have explicit states.

## 8. Open decisions for later

- Whether to use a custom on-screen keyboard or the platform keyboard behavior.
- Detailed Live/VOD classification heuristics for provider-specific playlists.
- Catalog limits and performance strategy for very large playlists.
- Future EPG and Xtream Codes requirements.

> Resolved: minimum webOS version is **26 "Re:New"**. The test-TV matrix is a single confirmed webOS 26+ model for the MVP. Remaining engineering decisions are tracked in [`decisions.md`](decisions.md).
