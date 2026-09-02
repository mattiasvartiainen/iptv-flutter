Yes — SQLite is a very good choice for your IPTV app across the platforms you're targeting, with one important caveat: webOS needs its own Flutter SQLite implementation, and you should hide that behind your own database/repository abstraction.

SQLite itself is extremely portable and is explicitly designed for embedded devices, TVs, Windows, Linux, etc.

Platform situation
Platform	SQLite	Flutter approach
LG webOS	✅	sqflite_webos
Windows	✅	sqflite_common_ffi
Linux	✅	sqflite_common_ffi
macOS	✅	sqflite / native
iOS / Apple TV	✅	Native SQLite / Flutter plugin
Android	✅	sqflite
Flutter Web	⚠️ Different	SQLite WASM / browser storage

There is actually a sqflite_webos implementation specifically providing SQLite support for Flutter apps on webOS.

For Windows and Linux, sqflite_common_ffi provides SQLite through FFI, and Flutter's current architecture documentation explicitly shows using the FFI implementation for those platforms.

SQLite itself is also used extensively in TVs and embedded devices.

I would absolutely use it for your application

Your architecture should look like:

                    Flutter application
                           │
                           ▼
                  ┌─────────────────┐
                  │ MediaRepository │
                  └────────┬────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │ DatabaseService │
                  └────────┬────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
          webOS                     Windows/Linux
              │                         │
       sqflite_webos              sqflite_common_ffi
              │                         │
              └────────────┬────────────┘
                           │
                           ▼
                        SQLite

Do not let your UI know which SQLite implementation is being used.

That gives you a very clean portability story.

And this solves your M3U problem

The important thing is that the M3U is not your database.

For example:

First installation
M3U URL
   ↓
Download 500k lines
   ↓
Streaming parser
   ↓
SQLite
   ↓
Home
Every subsequent application launch
SQLite
   ↓
Home

No M3U download.

That's the big win.

What about updating the playlist?

That's where the distinction matters.

Suppose the provider exposes:

https://provider.com/playlist.m3u

and it always returns 500,000 lines.

You cannot know what's changed without retrieving it.

So:

App launch
    ↓
SQLite
    ↓
Immediate Home

Then, perhaps once a week:

Background
    ↓
Download M3U
    ↓
Parse
    ↓
Compare/replace database

The user shouldn't even notice this happening.

If the provider later gives you an API for incremental changes, you can optimize it:

                    Provider
                       │
             "changes since X"
                       │
                       ▼
                 SQLite update

But you don't need that for V1.

One thing I'd change in our previous architecture

I would not make the application dependent on sqflite directly.

Instead define something like:

abstract class MediaDatabase {
  Future<List<MediaItem>> search(String query);

  Future<List<MediaItem>> getContinueWatching();

  Future<List<Channel>> getFavoriteChannels();

  Future<List<Channel>> getLiveChannels();

  Future<List<MediaItem>> getRecentlyWatched();

  Future<List<Series>> getSeries();

  Future<List<Episode>> getEpisodes(String seriesId);

  // ...
}

Then have:

MediaDatabase
      │
      ├── SQLiteMediaDatabase
      │       │
      │       └── platform SQLite implementation
      │
      └── MockMediaDatabase

Your UI doesn't care.

This also makes testing much easier.

What about Apple TV?

SQLite itself isn't the problem there.

Apple platforms have SQLite support, and SQLite's database file format is cross-platform. SQLite states that database files are portable across different architectures and operating systems.

The thing you'll need to solve separately is the Flutter plugin/platform integration for Apple TV, because Apple TV isn't necessarily covered by exactly the same Flutter plugin support as iOS.

That's actually another argument for our abstraction:

MediaRepository
       ↓
Database
       ↓
platform-specific SQLite implementation

rather than scattering sqflite calls throughout the app.

And 500,000 lines isn't a problem

I'd actually be quite comfortable with SQLite for this.

500,000 M3U lines is not 500,000 database records necessarily.

And even if you end up with hundreds of thousands of media records, SQLite is designed for exactly this sort of local indexed data. Flutter's own documentation recommends a database when an application needs to persist and query large amounts of data locally.

The key is:

Don't load the records into Dart.

Instead:

SQLite

100,000 movies
      │
      │ SELECT ... LIMIT 50
      ▼
Flutter

50 movies

And:

SQLite FTS5

"star wars"
      │
      ▼
20 results
      │
      ▼
Flutter

That will be vastly more efficient than keeping your entire catalogue in Dart collections.

One more thing: I would use SQLite + FTS5

For your app, search is going to be a major feature.

You have potentially:

Channels       thousands
Movies         tens/hundreds of thousands
Series         thousands
Episodes       hundreds of thousands

So I'd plan the database from day one with full-text search.

Something like:

media
────────────────────
id
type
title
normalized_title
logo_url
stream_url
playlist_id
...

media_fts
────────────────────
media_id
title

Then:

User types:

pine gap

       ↓

SQLite FTS5

       ↓

Pine Gap
Pine Gap S01 E01
Pine Gap S01 E02
...

No 500,000-record Dart list.

My recommendation

I'd now consider this part of the architecture decided:

Use SQLite as the local normalized media catalogue across platforms.

With:

                 M3U / future providers
                         │
                         ▼
                Streaming ingestion
                         │
                         ▼
                    Normalizer
                         │
                         ▼
                  ┌──────────────┐
                  │    SQLite    │
                  │              │
                  │ Media        │
                  │ Channels     │
                  │ Movies       │
                  │ Series       │
                  │ Seasons      │
                  │ Episodes     │
                  │ Categories   │
                  │ EPG          │
                  │ User state   │
                  │ FTS5         │
                  └──────┬───────┘
                         │
                    Repository
                         │
                         ▼
                    Flutter UI

And:

M3U is downloaded only for initial import and scheduled/manual refreshes — never as part of normal application startup.

That is a solid architecture for your use case.

can we also store settings in there?

we want to store refresh settings, how often we want to refresh

we want to be able to hide categories

we want to have personal settings, like default sub title language

Also a lot of other settings, like toggle if we should display recently watched etc

Absolutely. In fact, I would use the same SQLite database for settings as well. It gives you one local persistent store for the entire application.

The important part is to separate content data, application settings, and user/profile state logically, even though they live in the same SQLite file.

I would structure it like this
app.sqlite
│
├── Content
│   ├── playlists
│   ├── media_items
│   ├── channels
│   ├── movies
│   ├── series
│   ├── seasons
│   ├── episodes
│   ├── categories
│   └── epg_programs
│
├── User state
│   ├── favorites
│   ├── watch_history
│   └── playback_progress
│
├── Settings
│   ├── app_settings
│   ├── playlist_settings
│   ├── category_settings
│   └── profile_settings
│
└── Metadata
    ├── schema_version
    └── migrations

This is a very good fit for a TV application.

I'd distinguish 3 types of settings

This is important because not all settings belong to the same scope.

1. Application settings

Settings that apply to the whole application:

theme
language
show_recently_watched
show_continue_watching
show_favorites
animations_enabled
autoplay_next_episode

For example:

show_recently_watched = true
show_continue_watching = true
autoplay_next_episode = true
2. Playlist settings

These belong to a particular M3U playlist.

For example:

playlist_id
refresh_enabled
refresh_interval
last_refresh
next_refresh

And importantly:

hidden categories

could be associated with a playlist.

For example:

My IPTV
 ├── Sweden
 ├── Norway
 ├── Denmark
 ├── Sports
 ├── XXX             ← hidden
 └── Test Channels   ← hidden

You don't want to delete those categories from the database.

Just mark them hidden.

3. Profile/user settings

These are things such as:

preferred_subtitle_language
preferred_audio_language
autoplay
watch_history_enabled

For example:

profile_settings

profile_id
---------------
default_audio_language = "sv"
default_subtitle_language = "sv"
watch_history_enabled = true

This is particularly useful because you already want Profiles eventually.

You can therefore design for them now without actually implementing the profile UI yet.

Settings table

I would not necessarily create a different SQLite table for every setting category.

A flexible approach is:

CREATE TABLE app_settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

Then:

key                         value
------------------------------------------------
show_recently_watched       true
show_continue_watching      true
show_favorites              true
autoplay_next_episode       true
default_language            sv

This works particularly well for application-level settings.

But I would not use this generic key/value approach for everything.

For important structured data, use proper tables.

Playlist refresh settings

I'd make this a proper table:

CREATE TABLE playlist_settings (
    playlist_id          TEXT PRIMARY KEY,
    refresh_enabled      INTEGER NOT NULL DEFAULT 1,
    refresh_interval     INTEGER NOT NULL,
    last_refresh_at      TEXT,
    next_refresh_at      TEXT,
    last_refresh_status  TEXT
);

Where refresh_interval could be expressed in hours.

For example:

playlist: My IPTV
refresh: enabled
interval: 168 hours
last refresh: Sunday 03:00
next refresh: next Sunday 03:00

I'd probably support:

Never
Daily
Every 3 days
Weekly
Every 2 weeks
Manual only

rather than exposing raw hours in the UI.

Hidden categories

This deserves its own relationship table.

Something like:

CREATE TABLE hidden_categories (
    playlist_id  TEXT NOT NULL,
    category_id  TEXT NOT NULL,
    PRIMARY KEY (playlist_id, category_id)
);

Then:

Playlist
    ↓
Categories
    ↓
Hidden categories

If the provider changes the playlist and adds 500 new categories, you haven't lost the user's preferences.

One subtle issue with categories

Your M3U has things like:

Norway (Serie)
TV (Nordicsubs) (Serie)
Movies (Nordicsubs) (VOD)
Denmark (Serie)

I'd store the original provider group:

group_title

but eventually normalize it into application categories.

For example:

Provider group:
"TV (Nordicsubs) (Serie)"

Application:
type = series
country = Nordic
category = TV

Then the user's "hide category" setting should preferably operate on your application category, not the raw M3U string.

That will make the UI much more stable when different providers use different naming conventions.

Profile settings

Even if Profiles are V2, I'd make the database capable of:

CREATE TABLE profiles (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL
);

and:

CREATE TABLE profile_settings (
    profile_id TEXT PRIMARY KEY,
    subtitle_language TEXT,
    audio_language TEXT,
    watch_history_enabled INTEGER NOT NULL DEFAULT 1,
    autoplay_enabled INTEGER NOT NULL DEFAULT 1
);

Then your current application can simply have an implicit:

Default profile

Later you can add:

Who's watching?

Mattias
Anna
Kids
Guest

without redesigning your storage architecture.

Watch history

This is another case where SQLite is ideal.

CREATE TABLE watch_history (
    id TEXT PRIMARY KEY,
    profile_id TEXT,
    media_id TEXT NOT NULL,
    watched_at TEXT NOT NULL,
    completed INTEGER NOT NULL DEFAULT 0
);

And:

CREATE TABLE playback_progress (
    profile_id TEXT,
    media_id TEXT,
    position_ms INTEGER NOT NULL,
    duration_ms INTEGER,
    updated_at TEXT NOT NULL,
    PRIMARY KEY (profile_id, media_id)
);

Then Continue Watching is just a query.

The really nice thing about this architecture

Your entire application can effectively be restored from:

app.sqlite

For example, user launches the application tomorrow:

SQLite
 │
 ├── playlists
 │
 ├── settings
 │
 ├── hidden categories
 │
 ├── favorites
 │
 ├── history
 │
 ├── playback positions
 │
 └── media catalogue

Everything is already there.

The app can render Home immediately.

Meanwhile:

                    Background
                       │
                       ▼
                 Should refresh?
                    /       \
                  No         Yes
                  │           │
                  │       Download M3U
                  │           │
                  │       Update SQLite
                  │           │
                  └─────┬─────┘
                        ▼
                       UI
One thing I'd add: schema migrations

Because this application will evolve, SQLite should have a schema version:

schema_version = 1

Then later:

V1 → V2
V2 → V3
V3 → V4

For example, when you eventually add:

profiles

you can migrate an existing installation without destroying:

playlists
favorites
history
settings
cached content

This is particularly important for a TV application where users don't expect an update to reset everything.

I'd therefore revise our architecture to this
                         APP
                          │
                          ▼
                    ┌───────────┐
                    │  SQLite   │
                    │           │
                    ├───────────┤
                    │ CONTENT   │
                    │           │
                    │ playlists │
                    │ media     │
                    │ channels  │
                    │ movies    │
                    │ series    │
                    │ episodes  │
                    │ categories│
                    │ EPG       │
                    ├───────────┤
                    │ USER      │
                    │           │
                    │ favorites │
                    │ history   │
                    │ progress  │
                    ├───────────┤
                    │ SETTINGS  │
                    │           │
                    │ app       │
                    │ playlist  │
                    │ category  │
                    │ profile   │
                    └───────────┘

And above that:

Flutter UI
     │
     ├── ContentRepository
     ├── PlaybackRepository
     ├── SettingsRepository
     ├── PlaylistRepository
     └── EpgRepository
              │
              ▼
           SQLite

I strongly recommend this approach.

It gives you a single, portable local database while keeping the application architecture clean enough that when you eventually add Xtream Codes, profiles, richer metadata, etc., you don't have to rethink the storage layer.

## Canonical schema v1

The executable schema for v1 is defined in:

- docs/schema_v1.sql

This SQL file is the source of truth for:

- Content model tables (playlists, categories, media_items, series, seasons, episodes, epg_programs)
- User state tables (favorites, watch_history, playback_progress)
- Settings tables (app_settings, playlist_settings, profile_settings, hidden_categories)
- Metadata and migration tracking (schema_meta, schema_migrations)
- Query indexes and FTS5 search table

Implementation notes for v1:

- Keep credential-bearing playlist URLs in secure storage and reference them by secure_storage_key in the playlists table.
- Use playlist-scoped refresh configuration in playlist_settings.
- Keep hidden categories as data (hidden_categories), not destructive deletes.
- Populate search index in batch after successful import into media_items.
- Treat schema_v1.sql as migration version 1 (initial_schema_v1).