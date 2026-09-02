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
