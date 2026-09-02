 
• I need a final concise yet thorough overview, including an overall verdict. The MVP is okay, but it’s not ready for
  huge playlists. I should quantify the complexity: fetching and joining creates a whole string that uses O(B) memory;
  using text.split generates a list of all lines, plus raw strings. I’ll also need to parse a list of ContentItem with
  each metadata mapping and SHA256. Additionally, I'll retain the metadata map for each item in the entire catalog while
  ensuring main isolating blocking.

  Analyzing app structure and security issues

  I'm reviewing the InheritedNotifier, which rebuilds the entire app when there's a notification. The
  _rebuildSeriesCollections duplicates references, creating memory structures for all VOD episodes. I also need to
  import the database with a transaction, parsing the list and mapping existing IDs for batch upserts. There are
  concerns with FTS requiring a full delete and insert on each refresh. Additionally, there are missing queries for the
  UI. Security is a big issue since plaintext credentials are stored in the database stream URL, which could be risky.

  Reviewing potential issues and optimizations

  I see that there might not be a cancellation or generation guard for concurrent refreshes. The refreshingPlaylistId UI
  might prevent issues card by card, but save/refresh could race. I also realize the loadPlaylist function doesn't have
  a no-op lock. Additionally, the parser's classification heuristic is using repeated regex for metadata parsing, which
  could be optimized. Playback handoff is good, as the item object is already in memory, so no database lookup is
  needed. I found that test failures are due to the Flutter SDK environment, not the code itself. I'll need to refer to
  exact paths and line references.

────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

• Executive Summary

  - The current flow is functional for small/medium playlists, but it is not yet optimized for very large playlists or
    constrained webOS devices.

  - The largest issue is architectural: SQLite is present, but the application still loads the entire playlist into Dart
    memory and performs most filtering/grouping in the UI state layer.

  - For large playlists, the likely bottlenecks are:
      1. Full playlist materialization during download and parsing.
      2. Parsing on the UI isolate.
      3. Full catalog duplication in AppController.
      4. Repeated list allocations during widget rebuilds.
      5. Full database reconciliation and FTS rebuild on every refresh.

  - Playback startup itself is comparatively well isolated because the selected ContentItem is passed directly to the
    playback adapter.

  ## 1. High-Level User Flow

  Current flow:

  Add playlist
    → save playlist configuration
    → download entire M3U file
    → split and parse entire file
    → validate all items
    → reconcile all rows in SQLite
    → rebuild search index
    → return all items to AppController
    → rebuild series structures in memory
    → rebuild Home
    → user selects item
    → details screen
    → playback adapter loads stream URL

  The flow is logically correct, and it has some good properties:

  - Playlist metadata and refresh settings are persisted separately.
  - Credential-bearing playlist URLs are intended to be kept in secure storage.
  - Imports use a transaction and preserve the previous catalog if a refresh fails.
  - SQLite has indexes for playlist/type/sort queries.
  - The UI uses lazy GridView.builder and horizontal lists.
  - Playback is behind an adapter boundary.

  However, the current implementation is still effectively database-backed persistence with in-memory catalog
  architecture, not a true database-backed browsing architecture.

  ## 2. Architectural Review

  ### Current architecture

  The main layers are:

  Screens/widgets
    → AppController
      → CatalogRepository
        → M3U parser
        → SQLite repository
        → storage adapter

  This is a reasonable MVP structure. The main architectural problem is responsibility concentration in AppController.

  AppController currently owns:

  - Playlist loading and refresh.
  - Active playlist selection.
  - Full catalog storage.
  - Live/movie filtering.
  - Series detection and grouping.
  - Navigation state.
  - Playback handoff.
  - Home-section settings.

  Relevant locations:

  - lib/state/app_controller.dart:60
  - lib/state/app_controller.dart:148
  - lib/state/app_controller.dart:409
  - lib/state/app_controller.dart:758

  This means every catalog refresh produces a large object graph in the controller, and every notifyListeners() can
  cause broad parts of the application to rebuild.

  ### Main architectural concern: no query-oriented catalog API

  The repository exposes one large operation:

  Future<List<ContentItem>> load(...)

  See lib/services/catalog/catalog_repository.dart:15 and lib/services/catalog/sqlite_catalog_repository.dart:50.

  That API forces the caller to receive the entire catalog. A scalable API should instead expose operations such as:

  getHomeSections()
  getItems(type, group, offset, limit)
  getSeries(offset, limit)
  getSeasons(seriesId)
  getEpisodes(seriesId, seasonId)
  search(query, type, offset, limit)
  getItem(itemId)

  The database schema already supports this direction. It contains:

  - media_items
  - categories
  - series
  - seasons
  - episodes
  - FTS5 search
  - indexes by playlist/type/sort

  See lib/services/storage/storage_migrations.dart:194 and lib/services/storage/storage_migrations.dart:317.

  The application is therefore architecturally close to a scalable design, but the current runtime path bypasses most of
  the advantages of that schema.

  ### State granularity

  AppScope is an InheritedNotifier<AppController>:

  - lib/widgets/app_scope.dart:5

  Every controller notification can rebuild the currently mounted app subtree. The current screen switch means only one
  main screen is active, which limits the impact, but the screens still recreate derived lists such as:

  controller.liveItems
  controller.movieItems
  controller.seriesCollections

  Those getters allocate new lists:

  - lib/state/app_controller.dart:129
  - lib/state/app_controller.dart:132

  For a large catalog, this creates avoidable allocation and garbage-collection pressure during navigation and state
  changes.

  ### Recommended architectural target

  Separate the application into:

  PlaylistImportCoordinator
    → download
    → parse
    → normalize
    → transactional persistence

  CatalogQueryService
    → paginated SQLite queries
    → home previews
    → category browsing
    → series hierarchy
    → search

  CatalogViewState
    → current query/page
    → visible rows only
    → loading/error state

  PlaybackService
    → load item by ID or lightweight playback DTO

  The controller should coordinate these services, but should not own every catalog row.

  ## 3. Playlist Download and Parsing

  ### Current implementation

  HttpPlaylistSource.fetch() downloads the complete response into a single String:

  - lib/services/catalog/catalog_repository.dart:27

  The parser then does:

  final lines = text.split(RegExp(r'\r?\n'));

  - lib/services/catalog/m3u_parser.dart:6

  This creates several simultaneous representations:

  1. Network response bytes.
  2. Decoded full String.
  3. List of split lines.
  4. Parsed ContentItem objects.
  5. Attribute maps per item.
  6. Hash input and hash output strings.

  For a playlist with hundreds of thousands of entries, peak memory can become substantially larger than the source file
  size.

  ### CPU concerns

  The parser performs several expensive operations per item:

  - trim() on every line.
  - A regular expression scan for attributes.
  - URL parsing and resolution.
  - Content-type classification using another regular expression.
  - SHA-256 generation for every item.

  Relevant code:

  - lib/services/catalog/m3u_parser.dart:11
  - lib/services/catalog/m3u_parser.dart:21
  - lib/services/catalog/m3u_parser.dart:37
  - lib/services/catalog/m3u_parser.dart:55
  - lib/services/catalog/m3u_parser.dart:72

  The parser also parses attributes into a Map<String, String> and stores the map in every ContentItem:

  metadata: Map.unmodifiable(attributes)

  That is useful for flexibility, but expensive when repeated across a very large catalog. Most of those attributes are
  immediately flattened into SQLite columns later.

  ### Important issue: parsing runs synchronously on the UI isolate

  The download is asynchronous, but parsing begins directly after the response arrives:

  - lib/services/catalog/sqlite_catalog_repository.dart:81

  There is no isolate or background worker around:

  final parsed = const M3uParser().parse(...)

  For large playlists, this can block:

  - Flutter frame rendering.
  - Remote-control input.
  - Loading indicators.
  - Navigation responsiveness.

  The architecture documentation already recommends moving fetch/parse work off the UI isolate, but the implementation
  has not yet done this. See docs/architecture.md, playlist pipeline section.

  ### Recommendations

  High priority:

  1. Move parsing and normalization into a background isolate.
  2. Avoid text.split() for large playlists.
  3. Use a streaming or chunked line reader where practical.
  4. Parse only the attributes that are required by the product.
  5. Avoid retaining the full metadata map in the in-memory model.
  6. Consider using a compact import DTO instead of ContentItem.
  7. Add import cancellation and generation checks.

  A better pipeline is:

  HTTP response
    → temporary file or chunked decoder
    → isolate parser
    → bounded batches
    → SQLite batch writes
    → commit

  The parser should emit batches such as 500–2,000 records instead of returning one enormous List<ContentItem>.

  ## 4. SQLite Persistence and Refresh

  ### Positive aspects

  The persistence layer has several strong characteristics:

  - Transactional import.
  - Reconciliation of stale rows.
  - Separate playlist and playlist settings tables.
  - FTS5 search table.
  - Indexes for common catalog queries.
  - Error tracking for imports.
  - Fallback to cached data for cacheFirst.

  Relevant code:

  - lib/services/catalog/sqlite_catalog_repository.dart:120
  - lib/services/catalog/sqlite_catalog_repository.dart:153
  - lib/services/catalog/sqlite_catalog_repository.dart:202
  - lib/services/catalog/sqlite_catalog_repository.dart:307

  ### Current import cost

  The import currently performs all of the following:

  1. Download complete playlist.
  2. Parse complete playlist.
  3. Validate complete item list.
  4. Load cached rows.
  5. Load existing IDs and identity maps.
  6. Build desired categories/series/seasons/episodes.
  7. Queue all updates/inserts.
  8. Delete stale rows.
  9. Rebuild the entire FTS table.

  The reconciliation code constructs several large collections:

  - Existing item ID set.
  - Existing provider-hash map.
  - Existing signature map.
  - Desired IDs for media items.
  - Desired IDs for categories.
  - Desired IDs for series/seasons/episodes.
  - Resolved item list.

  Relevant locations:

  - lib/services/catalog/sqlite_catalog_repository.dart:417
  - lib/services/catalog/sqlite_catalog_repository.dart:501
  - lib/services/catalog/sqlite_catalog_repository.dart:749
  - lib/services/catalog/sqlite_catalog_repository.dart:780
  - lib/services/catalog/sqlite_catalog_repository.dart:717

  This is acceptable for moderate catalogs but creates high peak memory and CPU usage for very large imports.

  ### Risky fallback behavior

  If the bulk reconciliation fails, _reconcileResiliently() falls back to reconciling items individually:

  - lib/services/catalog/sqlite_catalog_repository.dart:417

  That protects import reliability, but it can turn one bad row or database issue into a very slow import because each
  item can cause another savepoint/batch operation.

  Recommended behavior:

  - Record the failing batch.
  - Retry the failing batch with smaller chunks.
  - Only fall back to per-item processing for the failing batch.
  - Avoid retrying the entire playlist item-by-item.

  ### Full FTS rebuild

  Every successful import deletes all FTS rows for the playlist and reinserts them:

  - lib/services/catalog/sqlite_catalog_repository.dart:886

  This is potentially expensive for large catalogs, especially when only a small fraction of entries changed.

  Better options:

  - Incrementally update FTS rows for changed items.
  - Use an FTS external-content table with controlled synchronization.
  - Rebuild search only after the main catalog is available.
  - Move FTS rebuild to a lower-priority background task.
  - Keep the previous FTS index available until the new one is complete.

  ### Database schema recommendations

  Existing indexes are a good starting point:

  - idx_media_playlist_type
  - idx_media_playlist_sort
  - idx_categories_playlist_kind
  - series and episode indexes

  See lib/services/storage/storage_migrations.dart:325.

  Potential additions:

  CREATE INDEX idx_media_playlist_group_sort
  ON media_items(playlist_id, group_title, sort_title);

  CREATE INDEX idx_media_playlist_source_index
  ON media_items(playlist_id, source_index);

  CREATE INDEX idx_media_playlist_provider_hash
  ON media_items(playlist_id, provider_item_hash);

  The exact indexes should be confirmed using actual query plans and representative data sizes rather than added
  blindly.

  ## 5. AppController and In-Memory Catalog

  After loading from SQLite, loadPlaylist() assigns the entire returned list to:

  catalog = List.unmodifiable(loaded);

  - lib/state/app_controller.dart:455

  It then rebuilds all series collections by scanning the entire catalog:

  _rebuildSeriesCollections();

  - lib/state/app_controller.dart:461
  - lib/state/app_controller.dart:758

  This duplicates data structures:

  - The full catalog list remains resident.
  - _seriesCollections retains references to episode items through wrapper objects.
  - _seriesEpisodeIds retains every series episode ID.
  - UI getters allocate filtered lists repeatedly.

  The following getters are particularly expensive on large catalogs:

  liveItems
  movieItems
  visibleCatalog
  groups

  Relevant locations:

  - lib/state/app_controller.dart:110
  - lib/state/app_controller.dart:129
  - lib/state/app_controller.dart:132
  - lib/state/app_controller.dart:142

  ### Recommended change

  Replace full-catalog state with query state:

  activePlaylistId
  currentSection
  currentGroup
  currentOffset
  currentPage
  visibleItems
  hasMore

  Load only the rows needed for the current screen.

  For example:

  Home:
    12 live rows
    12 movie rows
    12 series rows

  Live catalog:
    first 50 rows

  Movies:
    first 50 rows

  Episodes:
    one selected season at a time

  This is especially important for TV devices with limited memory.

  ## 6. Home Screen and Catalog Display

  ### Home screen

  The Home screen is relatively efficient visually:

  - It only displays 12 preview items per section.
  - It uses lazy horizontal lists.
  - It does not render the entire catalog at once.

  Relevant code:

  - lib/screens/home_screen.dart:10
  - lib/screens/home_screen.dart:14
  - lib/screens/home_screen.dart:102

  However, the data is already fully materialized before the Home screen is built. The _sample() method reduces widget
  count but not catalog memory:

  values.take(_rowPreviewCount).toList(...)

  Therefore, it solves rendering cost but not loading or state memory cost.

  ### Catalog screen

  The catalog uses GridView.builder, which is good for widget virtualization:

  - lib/screens/catalog_screen.dart:49

  But itemCount and the backing lists are already complete in-memory lists:

  items: controller.liveItems
  items: controller.movieItems

  - lib/screens/catalog_screen.dart:15
  - lib/screens/catalog_screen.dart:18

  The UI is lazy; the data model is not.

  ### Image behavior

  The current cards show icons rather than logos/posters, which avoids image memory and network pressure today. If
  artwork is added later, this area will become another major performance concern. Use:

  - bounded image cache sizes,
  - thumbnail URLs where available,
  - placeholder-first rendering,
  - no full-resolution artwork in list cards.

  ## 7. Selecting an Item and Starting Playback

  The playback path is comparatively good:

  Home/catalog item
    → selectedItem
    → details screen
    → playbackAdapter.load(item)

  Relevant locations:

  - lib/state/app_controller.dart:670
  - lib/state/app_controller.dart:676
  - lib/state/app_controller.dart:687

  The selected item is already in memory, so playback does not require an additional database lookup. The media adapter
  opens the stream directly:

  - lib/services/playback/desktop_media_kit_playback.dart:98

  This gives low application-side startup overhead.

  Potential improvements:

  - Pass a smaller playback DTO rather than the full ContentItem.
  - Cancel/stop an existing stream before loading another.
  - Add a load generation token so an older asynchronous load cannot overwrite a newer selection.
  - Avoid verbose per-position playback logging in production. desktop_media_kit_playback.dart:215 logs every state
    publication, which may be frequent.

  ## 8. Correctness and Data Risks

  ### Credential-bearing stream URLs in SQLite

  The documentation says credential-bearing playlist URLs should remain in secure storage. That is true for the playlist
  source URL, but individual stream URLs are stored directly in media_items.stream_url:

  - lib/services/catalog/sqlite_catalog_repository.dart:650
  - lib/services/storage/storage_migrations.dart:205

  Many IPTV stream URLs include username/password/token data in the path or query string. This means the database cache
  may contain credentials even if the original playlist URL is protected.

  Recommended options:

  - Encrypt the database.
  - Store a normalized credential reference plus non-sensitive URL components.
  - Store the original stream URL only in protected storage if required.
  - At minimum, ensure database files, diagnostics, backups, and logs are protected.

  ### Stable identity

  The parser’s initial item ID includes sourceIndex:

  - lib/services/catalog/m3u_parser.dart:37

  That means reorderings can change generated IDs. The repository has fallback identity matching using provider hash and
  signature, which mitigates this, but a better primary identity would avoid source position unless duplicate entries
  require it.

  ### Search is not implemented in the UI

  The database has FTS5, but SearchScreen currently reports that search is a later phase:

  - lib/screens/search_screen.dart:17

  This is a missed opportunity because database-backed search would be much more scalable than filtering catalog in
  Dart.

  ## 9. Priority Plan

  ### P0 — required for large playlists

  1. Move M3U parsing off the UI isolate.
  2. Stop returning the entire playlist from the repository.
  3. Add paginated/query-based catalog APIs.
  4. Keep only visible pages and selected items in controller state.
  5. Replace full FTS rebuild with incremental or deferred indexing.
  6. Add import cancellation and concurrent-refresh protection.

  ### P1 — high-value optimization

  1. Parse in bounded batches.
  2. Reduce per-item metadata retention.
  3. Use batch-level retry instead of item-by-item fallback for the whole catalog.
  4. Add query-specific indexes after measuring SQL plans.
  5. Cache home previews separately from full catalog browsing.
  6. Implement FTS-backed search.

  ### P2 — correctness and operational hardening

  1. Protect stream URLs that contain credentials.
  2. Add import progress reporting.
  3. Add import metrics:
      - download duration,
      - parse duration,
      - database duration,
      - rows accepted/rejected,
      - peak batch size,
      - FTS duration.

  4. Add large-playlist fixtures and performance tests.
  5. Add production logging levels to avoid high-frequency playback logs.

  ## 10. Recommended Target Flow

  User presses Refresh
    → mark import as running
    → download to temporary file/chunks
    → parse in background isolate
    → emit normalized batches
    → write batches into staging tables
    → reconcile changed/deleted rows transactionally
    → update categories/series/episodes
    → update search index incrementally or asynchronously
    → publish new database snapshot
    → invalidate only affected screen queries

  Then:

  Home
    → query 12 live items
    → query 12 movie items
    → query 12 series items

  Catalog
    → query page of 50–100 items

  Details
    → query one item by ID, or use already loaded row

  Playback
    → pass stream URL to adapter

  ## Final Assessment

  The current implementation has a sound MVP foundation and a reasonably designed SQLite schema. The critical
  scalability problem is not the database schema; it is that the application performs a full import into memory and then
  treats the entire catalog as controller state.

  For the target devices, the most important architectural change is:

  > Make SQLite the runtime catalog source, not just the persistence destination.

  Until parsing is moved off the UI isolate and browsing becomes paginated/query-driven, very large playlists will
  continue to create CPU spikes, UI stalls, memory pressure, and long refresh times.

  flutter test could not be completed because the configured Flutter SDK failed during engine-version detection in this
  environment. The working tree itself is clean.