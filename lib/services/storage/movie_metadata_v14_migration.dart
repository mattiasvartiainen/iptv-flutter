import 'package:sqflite_common/sqlite_api.dart';

import 'storage_contracts.dart';

class MovieMetadataV14Migration implements StorageMigration {
  const MovieMetadataV14Migration();
  @override
  int get version => 14;
  @override
  String get name => 'movie_metadata_v14';
  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE movie_provider_bindings (
  playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  revision INTEGER NOT NULL,
  provider TEXT NOT NULL,
  provider_id TEXT NOT NULL,
  evidence TEXT NOT NULL CHECK (evidence = 'verifiedDetail'),
  PRIMARY KEY (playlist_id, item_id, revision, provider)
)
''');
    await db.execute('''
CREATE TABLE movie_metadata_cache (
  playlist_id TEXT NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
  revision INTEGER NOT NULL,
  locale TEXT NOT NULL,
  payload TEXT,
  failure TEXT,
  fetched_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  accessed_at INTEGER NOT NULL,
  byte_size INTEGER NOT NULL,
  PRIMARY KEY (playlist_id, item_id, revision, locale)
)
''');
    await db.execute(
      'CREATE INDEX idx_movie_metadata_cache_lru ON movie_metadata_cache(accessed_at)',
    );
    await db.execute('''
CREATE TRIGGER invalidate_movie_metadata_source
AFTER UPDATE OF source_revision, source_api_enabled, source_verification ON playlists
WHEN NEW.source_revision != OLD.source_revision
  OR NEW.source_api_enabled IS NOT 1
  OR NEW.source_verification IS NOT 'verified'
BEGIN
  DELETE FROM movie_provider_bindings WHERE playlist_id = NEW.id;
  DELETE FROM movie_metadata_cache WHERE playlist_id = NEW.id;
END
''');
  }
}
