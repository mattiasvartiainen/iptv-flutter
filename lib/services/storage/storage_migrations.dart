import 'package:sqflite_common/sqlite_api.dart';

import 'storage_contracts.dart';

class InitialSchemaV1Migration implements StorageMigration {
  const InitialSchemaV1Migration();

  @override
  int get version => 1;

  @override
  String get name => 'initial_schema_v1';

  @override
  Future<void> up(DatabaseExecutor db) async {
    for (final statement in _statements) {
      await db.execute(statement);
    }
  }
}

class PlaylistImportMetricsV2Migration implements StorageMigration {
  const PlaylistImportMetricsV2Migration();

  @override
  int get version => 2;

  @override
  String get name => 'playlist_import_metrics_v2';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      table: 'playlists',
      column: 'last_import_staged_rows',
      definition: 'INTEGER',
    );
    await _addColumnIfMissing(
      db,
      table: 'playlists',
      column: 'last_import_staged_duration_ms',
      definition: 'INTEGER',
    );
  }
}

class PlaylistScopedIdentityV3Migration implements StorageMigration {
  const PlaylistScopedIdentityV3Migration();

  @override
  int get version => 3;

  @override
  String get name => 'playlist_scoped_identity_v3';

  @override
  Future<void> up(DatabaseExecutor db) async {
    // The old shared key may contain only the last URL that was saved, so it
    // is not safe to remap existing rows without user-provided URLs. New
    // imports write the correct per-playlist key; existing playlists must be
    // re-imported to repair their secret-storage references.
  }
}

class MediaItemXuiIdV4Migration implements StorageMigration {
  const MediaItemXuiIdV4Migration();

  @override
  int get version => 4;

  @override
  String get name => 'media_item_xui_id_v4';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      table: 'media_items',
      column: 'xui_id',
      definition: 'TEXT',
    );
  }
}

/// Adds the structures required for paginated browsing and batched imports:
/// query-shaped indexes, an import staging table, and a search-index queue so
/// FTS can be updated incrementally instead of rebuilt per playlist.
class PaginatedCatalogV5Migration implements StorageMigration {
  const PaginatedCatalogV5Migration();

  @override
  int get version => 5;

  @override
  String get name => 'paginated_catalog_v5';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await _addColumnIfMissing(
      db,
      table: 'playlists',
      column: 'search_index_dirty',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    for (final statement in _v5Statements) {
      await db.execute(statement);
    }
  }
}

Future<void> _addColumnIfMissing(
  DatabaseExecutor db, {
  required String table,
  required String column,
  required String definition,
}) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  final exists = rows.any((row) => row['name'] == column);
  if (exists) return;
  await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
}

const List<String> _statements = <String>[
  '''
CREATE TABLE IF NOT EXISTS schema_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
  '''
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL
)
''',
  '''
CREATE TABLE IF NOT EXISTS profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  is_default INTEGER NOT NULL DEFAULT 0 CHECK (is_default IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
  '''
CREATE TABLE IF NOT EXISTS profile_settings (
  profile_id TEXT PRIMARY KEY,
  subtitle_language TEXT,
  audio_language TEXT,
  watch_history_enabled INTEGER NOT NULL DEFAULT 1 CHECK (watch_history_enabled IN (0, 1)),
  autoplay_enabled INTEGER NOT NULL DEFAULT 1 CHECK (autoplay_enabled IN (0, 1)),
  updated_at TEXT NOT NULL,
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE
)
''',
  '''
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''',
  '''
CREATE TABLE IF NOT EXISTS playlists (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  secure_storage_key TEXT NOT NULL,
  source_url_redacted TEXT,
  enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_import_started_at TEXT,
  last_import_completed_at TEXT,
  last_import_staged_rows INTEGER,
  last_import_staged_duration_ms INTEGER,
  last_import_status TEXT NOT NULL DEFAULT 'never' CHECK (
    last_import_status IN ('never', 'running', 'success', 'failed')
  ),
  last_import_error TEXT
)
''',
  '''
CREATE TABLE IF NOT EXISTS playlist_settings (
  playlist_id TEXT PRIMARY KEY,
  refresh_enabled INTEGER NOT NULL DEFAULT 1 CHECK (refresh_enabled IN (0, 1)),
  refresh_mode TEXT NOT NULL DEFAULT 'weekly' CHECK (
    refresh_mode IN ('manual', 'daily', 'every_3_days', 'weekly', 'every_2_weeks')
  ),
  refresh_interval_hours INTEGER NOT NULL DEFAULT 168 CHECK (refresh_interval_hours >= 0),
  last_refresh_at TEXT,
  next_refresh_at TEXT,
  last_refresh_status TEXT CHECK (
    last_refresh_status IS NULL OR last_refresh_status IN ('success', 'failed', 'skipped')
  ),
  updated_at TEXT NOT NULL,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
)
''',
  '''
CREATE TABLE IF NOT EXISTS categories (
  id TEXT PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  provider_group_title TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  content_kind TEXT NOT NULL DEFAULT 'unknown' CHECK (
    content_kind IN ('live', 'movie', 'series', 'mixed', 'unknown')
  ),
  country_code TEXT,
  language_code TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (playlist_id, provider_group_title),
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
)
''',
  '''
CREATE TABLE IF NOT EXISTS media_items (
  id TEXT PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  content_type TEXT NOT NULL CHECK (
    content_type IN ('live', 'movie', 'episode', 'unknown')
  ),
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  description TEXT,
  artwork_url TEXT,
  logo_url TEXT,
  stream_url TEXT NOT NULL,
  category_id TEXT,
  group_title TEXT,
  tvg_id TEXT,
  tvg_name TEXT,
  tvg_chno TEXT,
  xui_id TEXT,
  source_index INTEGER NOT NULL DEFAULT 0,
  provider_item_hash TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
  UNIQUE (playlist_id, stream_url, title)
)
''',
  '''
CREATE TABLE IF NOT EXISTS series (
  id TEXT PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  artwork_url TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (playlist_id, title),
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
)
''',
  '''
CREATE TABLE IF NOT EXISTS seasons (
  id TEXT PRIMARY KEY,
  series_id TEXT NOT NULL,
  season_number INTEGER NOT NULL CHECK (season_number > 0),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (series_id, season_number),
  FOREIGN KEY (series_id) REFERENCES series(id) ON DELETE CASCADE
)
''',
  '''
CREATE TABLE IF NOT EXISTS episodes (
  id TEXT PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  series_id TEXT NOT NULL,
  season_id TEXT NOT NULL,
  media_item_id TEXT NOT NULL UNIQUE,
  episode_number INTEGER NOT NULL CHECK (episode_number > 0),
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  artwork_url TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
  FOREIGN KEY (series_id) REFERENCES series(id) ON DELETE CASCADE,
  FOREIGN KEY (season_id) REFERENCES seasons(id) ON DELETE CASCADE,
  FOREIGN KEY (media_item_id) REFERENCES media_items(id) ON DELETE CASCADE,
  UNIQUE (season_id, episode_number)
)
''',
  '''
CREATE TABLE IF NOT EXISTS favorites (
  profile_id TEXT NOT NULL,
  media_item_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY (profile_id, media_item_id),
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE,
  FOREIGN KEY (media_item_id) REFERENCES media_items(id) ON DELETE CASCADE
)
''',
  '''
CREATE TABLE IF NOT EXISTS watch_history (
  id TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL,
  media_item_id TEXT NOT NULL,
  watched_at TEXT NOT NULL,
  completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
  position_ms INTEGER,
  duration_ms INTEGER,
  created_at TEXT NOT NULL,
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE,
  FOREIGN KEY (media_item_id) REFERENCES media_items(id) ON DELETE CASCADE,
  CHECK (position_ms IS NULL OR position_ms >= 0),
  CHECK (duration_ms IS NULL OR duration_ms >= 0)
)
''',
  '''
CREATE TABLE IF NOT EXISTS playback_progress (
  profile_id TEXT NOT NULL,
  media_item_id TEXT NOT NULL,
  position_ms INTEGER NOT NULL CHECK (position_ms >= 0),
  duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
  updated_at TEXT NOT NULL,
  last_started_at TEXT,
  PRIMARY KEY (profile_id, media_item_id),
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE,
  FOREIGN KEY (media_item_id) REFERENCES media_items(id) ON DELETE CASCADE
)
''',
  '''
CREATE TABLE IF NOT EXISTS hidden_categories (
  playlist_id TEXT NOT NULL,
  category_id TEXT NOT NULL,
  profile_id TEXT,
  created_at TEXT NOT NULL,
  PRIMARY KEY (playlist_id, category_id, profile_id),
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE,
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE
)
''',
  '''
CREATE VIRTUAL TABLE IF NOT EXISTS media_items_fts USING fts5(
  media_item_id UNINDEXED,
  title,
  sort_title,
  group_title,
  tokenize = 'unicode61 remove_diacritics 2'
)
''',
  'CREATE INDEX IF NOT EXISTS idx_playlists_enabled ON playlists(enabled)',
  'CREATE INDEX IF NOT EXISTS idx_playlist_settings_next_refresh ON playlist_settings(next_refresh_at)',
  'CREATE INDEX IF NOT EXISTS idx_categories_playlist_kind ON categories(playlist_id, content_kind)',
  'CREATE INDEX IF NOT EXISTS idx_media_playlist_type ON media_items(playlist_id, content_type)',
  'CREATE INDEX IF NOT EXISTS idx_media_playlist_sort ON media_items(playlist_id, sort_title)',
  'CREATE INDEX IF NOT EXISTS idx_series_playlist_sort ON series(playlist_id, sort_title)',
  'CREATE INDEX IF NOT EXISTS idx_seasons_series_number ON seasons(series_id, season_number)',
  'CREATE INDEX IF NOT EXISTS idx_episodes_series_season ON episodes(series_id, season_id)',
  'CREATE INDEX IF NOT EXISTS idx_watch_history_profile_time ON watch_history(profile_id, watched_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_playback_progress_updated ON playback_progress(profile_id, updated_at DESC)',
];

const List<String> _v5Statements = <String>[
  // Import rows are streamed here in batches so reconciliation can run as set
  // operations in SQL instead of materialising the whole playlist in Dart.
  '''
CREATE TABLE IF NOT EXISTS import_staging_items (
  playlist_id TEXT NOT NULL,
  source_index INTEGER NOT NULL,
  content_type TEXT NOT NULL CHECK (
    content_type IN ('live', 'movie', 'episode', 'unknown')
  ),
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  description TEXT,
  stream_url TEXT NOT NULL,
  group_title TEXT,
  logo_url TEXT,
  artwork_url TEXT,
  tvg_id TEXT,
  tvg_name TEXT,
  tvg_chno TEXT,
  xui_id TEXT,
  provider_item_hash TEXT,
  media_signature TEXT NOT NULL,
  series_title TEXT,
  season_number INTEGER,
  episode_number INTEGER,
  PRIMARY KEY (playlist_id, source_index),
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
)
''',
  // media_item_id has no foreign key: delete entries must outlive the row.
  '''
CREATE TABLE IF NOT EXISTS search_index_queue (
  media_item_id TEXT PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  queued_at TEXT NOT NULL,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
)
''',
  'CREATE INDEX IF NOT EXISTS idx_media_playlist_group_sort ON media_items(playlist_id, group_title, sort_title)',
  'CREATE INDEX IF NOT EXISTS idx_media_playlist_type_sort ON media_items(playlist_id, content_type, sort_title)',
  'CREATE INDEX IF NOT EXISTS idx_media_playlist_source_index ON media_items(playlist_id, source_index)',
  'CREATE INDEX IF NOT EXISTS idx_media_playlist_provider_hash ON media_items(playlist_id, provider_item_hash)',
  'CREATE INDEX IF NOT EXISTS idx_episodes_season_number ON episodes(season_id, episode_number)',
  'CREATE INDEX IF NOT EXISTS idx_staging_playlist_signature ON import_staging_items(playlist_id, media_signature)',
  'CREATE INDEX IF NOT EXISTS idx_staging_playlist_hash ON import_staging_items(playlist_id, provider_item_hash)',
  'CREATE INDEX IF NOT EXISTS idx_staging_playlist_identity ON import_staging_items(playlist_id, stream_url, title)',
  'CREATE INDEX IF NOT EXISTS idx_search_index_queue_playlist ON search_index_queue(playlist_id, operation)',
];

/// Turns `import_staging_items` into the real import boundary: adds the
/// precomputed id columns a SQL set-based reconcile needs (Dart still owns
/// hashing since SQLite has no callable SHA-256/legacy-hash function), plus
/// the supporting indexes for the joins/anti-joins that replace the old
/// full-table Dart Set/Map preload. See docs/improvements-1.md "Path B".
class ImportStagingSqlReconcileV6Migration implements StorageMigration {
  const ImportStagingSqlReconcileV6Migration();

  @override
  int get version => 6;

  @override
  String get name => 'import_staging_sql_reconcile_v6';

  @override
  Future<void> up(DatabaseExecutor db) async {
    for (final column in const [
      'id',
      'category_id',
      'series_id',
      'season_id',
      'resolved_media_id',
      'episode_id',
    ]) {
      await _addColumnIfMissing(
        db,
        table: 'import_staging_items',
        column: column,
        definition: 'TEXT',
      );
    }
    for (final statement in _v6Statements) {
      await db.execute(statement);
    }
  }
}

const List<String> _v6Statements = <String>[
  // Supports the resolved_media_id COALESCE join's third (order-independent
  // is only true for the provider-hash branch; this one still needs
  // source_index) fallback branch.
  'CREATE INDEX IF NOT EXISTS idx_media_playlist_signature ON media_items(playlist_id, stream_url, title, source_index)',
  'CREATE INDEX IF NOT EXISTS idx_staging_category ON import_staging_items(playlist_id, category_id)',
  'CREATE INDEX IF NOT EXISTS idx_staging_series ON import_staging_items(playlist_id, series_id)',
  'CREATE INDEX IF NOT EXISTS idx_staging_season ON import_staging_items(playlist_id, season_id)',
  'CREATE INDEX IF NOT EXISTS idx_staging_episode_identity ON import_staging_items(playlist_id, season_id, episode_number, source_index)',
  'CREATE INDEX IF NOT EXISTS idx_staging_resolved_media ON import_staging_items(playlist_id, resolved_media_id)',
  'CREATE INDEX IF NOT EXISTS idx_staging_episode ON import_staging_items(playlist_id, episode_id)',
];

/// Import throughput work for very large playlists (500k+ items).
///
/// Every secondary index on `import_staging_items` cost one b-tree insert
/// per staged row without ever being chosen by the reconcile statements
/// (which are full-set scans/group-bys), and two `media_items` indexes were
/// redundant prefixes of wider ones. The FTS table is also rebuilt so its
/// rowid matches `media_items.rowid`: index maintenance used to delete rows
/// with `WHERE media_item_id = ?` on an UNINDEXED column, which is a full
/// scan of the FTS content table per queued row.
class ImportPerformanceV7Migration implements StorageMigration {
  const ImportPerformanceV7Migration();

  @override
  int get version => 7;

  @override
  String get name => 'import_performance_v7';

  @override
  Future<void> up(DatabaseExecutor db) async {
    for (final statement in _v7DropStatements) {
      await db.execute(statement);
    }
    // Scratch table: recreating is cheaper and simpler than ALTERing away
    // the unused media_signature column.
    await db.execute('DROP TABLE IF EXISTS import_staging_items');
    await db.execute(_importStagingItemsSchema);

    // Recreated rather than altered so it gains media_rowid and so 'insert'
    // passes the operation CHECK. Losing pending entries is harmless:
    // everything is re-queued below.
    await db.execute('DROP TABLE IF EXISTS search_index_queue');
    await db.execute(_searchIndexQueueSchema);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_search_index_queue_playlist '
      'ON search_index_queue(playlist_id, operation)',
    );

    // The FTS rowid must line up with media_items.rowid, which existing
    // rows do not, so the index is rebuilt from scratch in the background.
    await db.execute('DROP TABLE IF EXISTS media_items_fts');
    await db.execute(_mediaItemsFtsSchema);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawInsert(
      '''
INSERT INTO search_index_queue (media_item_id, playlist_id, operation, queued_at)
SELECT id, playlist_id, 'insert', ? FROM media_items
WHERE true
ON CONFLICT(media_item_id) DO UPDATE SET
  operation = excluded.operation,
  queued_at = excluded.queued_at
''',
      [now],
    );
    await db.execute('UPDATE playlists SET search_index_dirty = 1');
  }
}

class ImportSessionsV8Migration implements StorageMigration {
  const ImportSessionsV8Migration();

  @override
  int get version => 8;

  @override
  String get name => 'import_sessions_v8';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS import_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  finished_at INTEGER,
  state TEXT NOT NULL CHECK (
    state IN ('running', 'reconciling', 'done', 'unchanged', 'failed', 'cancelled', 'aborted')
  ),
  tier TEXT,
  bytes_total INTEGER,
  bytes_received INTEGER NOT NULL DEFAULT 0,
  items_parsed INTEGER NOT NULL DEFAULT 0,
  items_rejected INTEGER NOT NULL DEFAULT 0,
  items_new INTEGER,
  items_changed INTEGER,
  items_moved INTEGER,
  items_removed INTEGER,
  stage_timings TEXT NOT NULL DEFAULT '{}',
  error TEXT
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_sessions_playlist_started '
      'ON import_sessions(playlist_id, started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_sessions_state '
      'ON import_sessions(state)',
    );
  }
}

class CatalogImportV9Migration implements StorageMigration {
  const CatalogImportV9Migration();

  @override
  int get version => 9;

  @override
  String get name => 'catalog_import_v9';

  @override
  Future<void> up(DatabaseExecutor db) async {
    for (final column in const [
      ('playlists', 'source_etag', 'TEXT'),
      ('playlists', 'source_last_modified', 'TEXT'),
      ('playlists', 'source_content_hash', 'INTEGER'),
      ('playlists', 'source_content_length', 'INTEGER'),
      ('playlists', 'last_checked_at', 'INTEGER'),
      ('playlists', 'last_changed_at', 'INTEGER'),
      (
        'playlist_settings',
        'min_refresh_interval_s',
        'INTEGER NOT NULL DEFAULT 3600',
      ),
    ]) {
      await _addColumnIfMissing(
        db,
        table: column.$1,
        column: column.$2,
        definition: column.$3,
      );
    }

    await db.execute('''
CREATE TABLE IF NOT EXISTS import_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  playlist_id TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  finished_at INTEGER,
  state TEXT NOT NULL CHECK (
    state IN ('running', 'reconciling', 'done', 'unchanged', 'failed', 'cancelled', 'aborted')
  ),
  tier TEXT,
  bytes_total INTEGER,
  bytes_received INTEGER NOT NULL DEFAULT 0,
  items_parsed INTEGER NOT NULL DEFAULT 0,
  items_rejected INTEGER NOT NULL DEFAULT 0,
  items_new INTEGER,
  items_changed INTEGER,
  items_moved INTEGER,
  items_removed INTEGER,
  stage_timings TEXT NOT NULL DEFAULT '{}',
  error TEXT
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_sessions_playlist_started '
      'ON import_sessions(playlist_id, started_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_import_sessions_state '
      'ON import_sessions(state)',
    );

    for (final statement in _v9CatalogStatements) {
      await db.execute(statement);
    }
  }
}

class CatalogSearchV10Migration implements StorageMigration {
  const CatalogSearchV10Migration();

  @override
  int get version => 10;

  @override
  String get name => 'catalog_search_v10';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS items_fts_queue (
  item_id INTEGER PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
  old_title TEXT,
  priority INTEGER NOT NULL CHECK (priority IN (1, 2, 3)),
  queued_at INTEGER NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_items_fts_queue_priority '
      'ON items_fts_queue(priority, queued_at, item_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_items_fts_queue_playlist '
      'ON items_fts_queue(playlist_id, priority)',
    );
  }
}

/// Drops the v1-v7 catalog after v9 import, query, and user data are active.
class DropLegacyCatalogV11Migration implements StorageMigration {
  const DropLegacyCatalogV11Migration();

  @override
  int get version => 11;

  @override
  String get name => 'drop_legacy_catalog_v11';

  @override
  Future<void> up(DatabaseExecutor db) async {
    for (final statement in const [
      'DROP TABLE IF EXISTS media_items_fts',
      'DROP TABLE IF EXISTS import_staging_items',
      'DROP TABLE IF EXISTS search_index_queue',
      'DROP TABLE IF EXISTS episodes',
      'DROP TABLE IF EXISTS favorites',
      'DROP TABLE IF EXISTS playback_progress',
      'DROP TABLE IF EXISTS watch_history',
      'DROP TABLE IF EXISTS hidden_categories',
      'DROP TABLE IF EXISTS media_items',
      'DROP TABLE IF EXISTS seasons',
      'DROP TABLE IF EXISTS series',
      'DROP TABLE IF EXISTS categories',
    ]) {
      await db.execute(statement);
    }
  }
}

const List<String> _v9CatalogStatements = [
  '''
CREATE TABLE IF NOT EXISTS groups (
  id INTEGER PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  kind INTEGER NOT NULL CHECK (kind IN (1, 2, 3)),
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  ord INTEGER NOT NULL,
  item_count INTEGER NOT NULL DEFAULT 0 CHECK (item_count >= 0),
  UNIQUE (playlist_id, kind, title)
)
''',
  '''
CREATE TABLE IF NOT EXISTS items (
  id INTEGER PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  item_key INTEGER NOT NULL,
  content_hash INTEGER NOT NULL,
  ord INTEGER NOT NULL,
  kind INTEGER NOT NULL CHECK (kind IN (1, 2, 3)),
  group_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  stream_url TEXT NOT NULL,
  logo_url TEXT,
  tvg_id TEXT,
  tvg_name TEXT,
  tvg_chno TEXT,
  xui_id TEXT,
  series_key INTEGER,
  series_title TEXT,
  season_number INTEGER,
  episode_number INTEGER,
  UNIQUE (playlist_id, item_key),
  FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
)
''',
  'CREATE INDEX IF NOT EXISTS idx_items_group_ord ON items(group_id, ord)',
  'CREATE INDEX IF NOT EXISTS idx_items_group_sort ON items(group_id, sort_title)',
  '''
CREATE INDEX IF NOT EXISTS idx_items_series_episode
ON items(series_key, season_number, episode_number)
WHERE series_key IS NOT NULL
''',
  'CREATE INDEX IF NOT EXISTS idx_items_playlist_ord ON items(playlist_id, ord)',
  '''
CREATE TABLE IF NOT EXISTS series_v8 (
  series_key INTEGER PRIMARY KEY,
  playlist_id TEXT NOT NULL,
  group_id INTEGER NOT NULL,
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  artwork_url TEXT,
  season_count INTEGER NOT NULL DEFAULT 0,
  episode_count INTEGER NOT NULL DEFAULT 0,
  ord INTEGER NOT NULL,
  FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE
)
''',
  'CREATE INDEX IF NOT EXISTS idx_series_v8_group_sort ON series_v8(group_id, sort_title)',
  '''
CREATE TABLE IF NOT EXISTS import_rows (
  import_id INTEGER NOT NULL,
  item_key INTEGER NOT NULL,
  content_hash INTEGER NOT NULL,
  ord INTEGER NOT NULL,
  kind INTEGER NOT NULL CHECK (kind IN (1, 2, 3)),
  group_kind INTEGER NOT NULL CHECK (group_kind IN (1, 2, 3)),
  group_title TEXT NOT NULL,
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  stream_url TEXT NOT NULL,
  logo_url TEXT,
  tvg_id TEXT,
  tvg_name TEXT,
  tvg_chno TEXT,
  xui_id TEXT,
  series_key INTEGER,
  series_title TEXT,
  season_number INTEGER,
  episode_number INTEGER,
  PRIMARY KEY (import_id, item_key)
) WITHOUT ROWID
''',
  '''
CREATE TABLE IF NOT EXISTS import_seen (
  import_id INTEGER NOT NULL,
  item_key INTEGER NOT NULL,
  new_ord INTEGER,
  PRIMARY KEY (import_id, item_key)
) WITHOUT ROWID
''',
  '''
CREATE TABLE IF NOT EXISTS favorites_v8 (
  profile_id TEXT NOT NULL,
  playlist_id TEXT NOT NULL,
  item_key INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY (profile_id, playlist_id, item_key)
) WITHOUT ROWID
''',
  '''
CREATE TABLE IF NOT EXISTS playback_progress_v8 (
  profile_id TEXT NOT NULL,
  playlist_id TEXT NOT NULL,
  item_key INTEGER NOT NULL,
  position_ms INTEGER NOT NULL CHECK (position_ms >= 0),
  duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0),
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (profile_id, playlist_id, item_key)
) WITHOUT ROWID
''',
  '''
CREATE TABLE IF NOT EXISTS watch_history_v8 (
  id INTEGER PRIMARY KEY,
  profile_id TEXT NOT NULL,
  playlist_id TEXT NOT NULL,
  item_key INTEGER NOT NULL,
  watched_at INTEGER NOT NULL,
  completed INTEGER NOT NULL DEFAULT 0 CHECK (completed IN (0, 1)),
  position_ms INTEGER CHECK (position_ms IS NULL OR position_ms >= 0),
  duration_ms INTEGER CHECK (duration_ms IS NULL OR duration_ms >= 0)
)
''',
  '''
CREATE TABLE IF NOT EXISTS hidden_groups_v8 (
  profile_id TEXT NOT NULL,
  playlist_id TEXT NOT NULL,
  kind INTEGER NOT NULL CHECK (kind IN (1, 2, 3)),
  group_title TEXT NOT NULL,
  PRIMARY KEY (profile_id, playlist_id, kind, group_title)
) WITHOUT ROWID
''',
  '''
CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5(
  title,
  tokenize = 'unicode61 remove_diacritics 2',
  content = 'items',
  content_rowid = 'id'
)
''',
];

const List<String> _v7DropStatements = <String>[
  // Prefix of idx_media_playlist_type_sort.
  'DROP INDEX IF EXISTS idx_media_playlist_type',
  // Prefix covered by the UNIQUE (playlist_id, stream_url, title) index.
  'DROP INDEX IF EXISTS idx_media_playlist_signature',
  'DROP INDEX IF EXISTS idx_staging_playlist_signature',
  'DROP INDEX IF EXISTS idx_staging_playlist_hash',
  'DROP INDEX IF EXISTS idx_staging_playlist_identity',
  'DROP INDEX IF EXISTS idx_staging_category',
  'DROP INDEX IF EXISTS idx_staging_series',
  'DROP INDEX IF EXISTS idx_staging_season',
  'DROP INDEX IF EXISTS idx_staging_episode_identity',
  'DROP INDEX IF EXISTS idx_staging_resolved_media',
  'DROP INDEX IF EXISTS idx_staging_episode',
];

const String _importStagingItemsSchema = '''
CREATE TABLE IF NOT EXISTS import_staging_items (
  playlist_id TEXT NOT NULL,
  source_index INTEGER NOT NULL,
  id TEXT,
  content_type TEXT NOT NULL CHECK (
    content_type IN ('live', 'movie', 'episode', 'unknown')
  ),
  title TEXT NOT NULL,
  sort_title TEXT NOT NULL,
  description TEXT,
  stream_url TEXT NOT NULL,
  group_title TEXT,
  logo_url TEXT,
  artwork_url TEXT,
  tvg_id TEXT,
  tvg_name TEXT,
  tvg_chno TEXT,
  xui_id TEXT,
  provider_item_hash TEXT,
  category_id TEXT,
  series_title TEXT,
  series_id TEXT,
  season_number INTEGER,
  season_id TEXT,
  episode_number INTEGER,
  episode_id TEXT,
  resolved_media_id TEXT,
  PRIMARY KEY (playlist_id, source_index),
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
)
''';

const String _searchIndexQueueSchema = '''
CREATE TABLE IF NOT EXISTS search_index_queue (
  media_item_id TEXT PRIMARY KEY,
  media_rowid INTEGER,
  playlist_id TEXT NOT NULL,
  operation TEXT NOT NULL CHECK (
    operation IN ('insert', 'upsert', 'delete')
  ),
  queued_at TEXT NOT NULL,
  FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
)
''';

const String _mediaItemsFtsSchema =
    '''CREATE VIRTUAL TABLE IF NOT EXISTS media_items_fts USING fts5(
  media_item_id UNINDEXED,
  title,
  group_title,
  tokenize = 'unicode61 remove_diacritics 2'
)
''';
