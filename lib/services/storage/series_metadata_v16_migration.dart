import 'package:sqflite_common/sqlite_api.dart';

import 'storage_contracts.dart';

class SeriesMetadataV16Migration implements StorageMigration {
  const SeriesMetadataV16Migration();
  @override
  int get version => 16;
  @override
  String get name => 'series_metadata_v16';
  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute(
      'CREATE INDEX idx_series_metadata_cache_series ON series_metadata_cache(series_key)',
    );
    for (final trigger in [
      'invalidate_series_metadata_episode',
      'invalidate_series_metadata_episode_insert',
      'invalidate_series_metadata_episode_update',
      'invalidate_series_metadata_title',
    ]) {
      await db.execute('DROP TRIGGER $trigger');
    }
    await db.execute('''
CREATE TRIGGER invalidate_series_metadata_episode
AFTER DELETE ON items
WHEN OLD.kind = 3 AND OLD.series_key IS NOT NULL
BEGIN
  DELETE FROM series_metadata_cache
  WHERE playlist_id = OLD.playlist_id AND series_key = OLD.series_key;
END
''');
    await db.execute('''
CREATE TRIGGER invalidate_series_metadata_episode_insert
AFTER INSERT ON items
WHEN NEW.kind = 3 AND NEW.series_key IS NOT NULL
BEGIN
  DELETE FROM series_metadata_cache
  WHERE playlist_id = NEW.playlist_id AND series_key = NEW.series_key;
END
''');
    await db.execute('''
CREATE TRIGGER invalidate_series_metadata_episode_update
AFTER UPDATE OF stream_url, series_key, kind, playlist_id ON items
WHEN NEW.stream_url != OLD.stream_url OR NEW.series_key IS NOT OLD.series_key
  OR NEW.kind != OLD.kind OR NEW.playlist_id != OLD.playlist_id
BEGIN
  DELETE FROM series_metadata_cache
  WHERE playlist_id = OLD.playlist_id AND series_key = OLD.series_key AND OLD.kind = 3;
  DELETE FROM series_metadata_cache
  WHERE playlist_id = NEW.playlist_id AND series_key = NEW.series_key AND NEW.kind = 3;
END
''');
    await db.execute('''
CREATE TRIGGER invalidate_series_metadata_title
AFTER UPDATE OF title, group_id ON series_v8
WHEN NEW.title != OLD.title OR NEW.group_id != OLD.group_id
BEGIN
  DELETE FROM series_metadata_cache
  WHERE playlist_id = NEW.playlist_id AND series_key = NEW.series_key;
END
''');
  }
}
