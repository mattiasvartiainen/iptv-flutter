import 'package:sqflite_common/sqlite_api.dart';

import 'storage_contracts.dart';

class SeriesMetadataV15Migration implements StorageMigration {
  const SeriesMetadataV15Migration();
  @override
  int get version => 15;
  @override
  String get name => 'series_metadata_v15';
  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE series_metadata_cache (
  playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  series_key INTEGER NOT NULL REFERENCES series_v8(series_key) ON DELETE CASCADE,
  revision INTEGER NOT NULL,
  locale TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  payload TEXT NOT NULL,
  fetched_at INTEGER NOT NULL,
  accessed_at INTEGER NOT NULL,
  byte_size INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, series_key, revision, locale)
)
''');
    await db.execute('''
CREATE TRIGGER invalidate_series_metadata_source
AFTER UPDATE OF source_revision, source_api_enabled, source_verification ON playlists
WHEN NEW.source_revision != OLD.source_revision
  OR NEW.source_api_enabled IS NOT 1 OR NEW.source_verification IS NOT 'verified'
BEGIN DELETE FROM series_metadata_cache WHERE playlist_id = NEW.id; END
''');
    await db.execute('''
CREATE TRIGGER invalidate_series_metadata_episode
AFTER DELETE ON items
BEGIN DELETE FROM series_metadata_cache WHERE series_key = OLD.series_key; END
''');
    await db.execute('''
CREATE TRIGGER invalidate_series_metadata_episode_insert
AFTER INSERT ON items
BEGIN DELETE FROM series_metadata_cache WHERE series_key = NEW.series_key; END
''');
    await db.execute('''
CREATE TRIGGER invalidate_series_metadata_title
AFTER UPDATE OF title, group_id ON series_v8
WHEN NEW.title != OLD.title OR NEW.group_id != OLD.group_id
BEGIN DELETE FROM series_metadata_cache WHERE series_key = NEW.series_key; END
''');
    await db.execute('''
CREATE TRIGGER invalidate_series_metadata_episode_update
AFTER UPDATE OF stream_url, series_key ON items
WHEN NEW.stream_url != OLD.stream_url OR NEW.series_key IS NOT OLD.series_key
BEGIN DELETE FROM series_metadata_cache
WHERE series_key IN (OLD.series_key, NEW.series_key); END
''');
  }
}
