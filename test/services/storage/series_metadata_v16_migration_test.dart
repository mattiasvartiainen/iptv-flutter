import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/series_metadata_v15_migration.dart';
import 'package:iptv_flutter/services/storage/series_metadata_v16_migration.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../support/database_adapter.dart';

void main() {
  late SqfliteDatabaseAdapter adapter;
  late Database db;
  setUp(() async {
    adapter = createTestDatabaseAdapter(
      fileName: 'series_v16_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    db = await adapter.database;
    for (final playlist in ['p', 'q']) {
      await db.insert('playlists', {
        'id': playlist,
        'name': 'Fixture',
        'secure_storage_key': 'fixture-$playlist',
        'created_at': '2026-11-25',
        'updated_at': '2026-11-25',
      });
    }
    await db.insert('groups', {
      'id': 1,
      'playlist_id': 'p',
      'kind': 3,
      'title': 'Series',
      'sort_title': 'series',
      'ord': 0,
    });
    for (final id in [7, 8]) {
      await db.insert('series_v8', {
        'series_key': id,
        'playlist_id': id == 7 ? 'p' : 'q',
        'group_id': 1,
        'title': 'Show $id',
        'sort_title': 'show',
        'ord': id,
      });
    }
  });
  tearDown(() async {
    final path = db.path;
    await adapter.close();
    await testDatabaseFactory.deleteDatabase(path);
  });
  Future<void> cache() async {
    for (final id in [7, 8]) {
      await db.insert('series_metadata_cache', {
        'playlist_id': id == 7 ? 'p' : 'q',
        'series_key': id,
        'revision': 0,
        'locale': 'en',
        'provider_id': '$id',
        'payload': '{}',
        'fetched_at': 1,
        'accessed_at': 1,
        'byte_size': 514,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> item(int id, {int kind = 3, int? series = 7}) => db
      .insert('items', {
        'id': id,
        'playlist_id': 'p',
        'item_key': id,
        'content_hash': 1,
        'ord': id,
        'kind': kind,
        'group_id': 1,
        'title': 'Episode',
        'sort_title': 'episode',
        'stream_url': 'https://fixture.test/$id',
        'series_key': series,
      })
      .then((_) {});

  Future<void> restoreV15CacheSchema() async {
    final cached = await db.query('series_metadata_cache');
    for (final row in await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'invalidate_series_metadata_%'",
    )) {
      await db.execute('DROP TRIGGER ${row['name']}');
    }
    await db.execute('DROP TABLE series_metadata_cache');
    await const SeriesMetadataV15Migration().up(db);
    for (final row in cached) {
      await db.insert('series_metadata_cache', row);
    }
  }

  test(
    'invalidation and foreign-key lookup use indexed searches, not cache scans',
    () async {
      for (final query in [
        'DELETE FROM series_metadata_cache WHERE playlist_id = ? AND series_key = ?',
        'DELETE FROM series_metadata_cache WHERE series_key = ?',
      ]) {
        final plan = await db.rawQuery(
          'EXPLAIN QUERY PLAN $query',
          query.contains('playlist_id') ? ['p', 7] : [7],
        );
        final details = plan.map((row) => row['detail']).join(' ');
        expect(details, contains('SEARCH'));
        expect(details, isNot(contains('SCAN series_metadata_cache')));
      }
    },
  );
  test(
    'only affected series invalidate; Live/movie and ordinal-only writes preserve cache',
    () async {
      await cache();
      await item(1, kind: 1, series: null);
      await item(2, kind: 2, series: null);
      await db.update('items', {'title': 'Changed'}, where: 'id = 1');
      expect(await db.query('series_metadata_cache'), hasLength(2));
      await item(3);
      expect((await db.query('series_metadata_cache')).single['series_key'], 8);
      await cache();
      await db.update('items', {'ord': 10}, where: 'id = 3');
      await db.update('items', {
        'stream_url': 'https://fixture.test/3',
        'series_key': 7,
      }, where: 'id = 3');
      expect(await db.query('series_metadata_cache'), hasLength(2));
      await db.update('items', {
        'stream_url': 'https://fixture.test/new',
      }, where: 'id = 3');
      expect((await db.query('series_metadata_cache')).single['series_key'], 8);
      await cache();
      await db.delete('items', where: 'id = 3');
      expect((await db.query('series_metadata_cache')).single['series_key'], 8);
    },
  );
  test(
    'kind and series transitions invalidate old/new identities and all locales',
    () async {
      await item(3);
      await cache();
      await db.insert('series_metadata_cache', {
        'playlist_id': 'p',
        'series_key': 7,
        'revision': 0,
        'locale': 'sv',
        'provider_id': '7',
        'payload': '{}',
        'fetched_at': 1,
        'accessed_at': 1,
        'byte_size': 514,
      });
      await db.update('items', {'kind': 2}, where: 'id = 3');
      expect((await db.query('series_metadata_cache')).single['series_key'], 8);
      await cache();
      await db.update('items', {'kind': 3}, where: 'id = 3');
      expect((await db.query('series_metadata_cache')).single['series_key'], 8);
      await cache();
      await db.update('items', {
        'series_key': 8,
        'playlist_id': 'q',
      }, where: 'id = 3');
      expect(await db.query('series_metadata_cache'), isEmpty);
    },
  );
  test(
    'v15 upgrade preserves cache/catalog and replaces hot-path triggers',
    () async {
      await item(3);
      await cache();
      final items = await db.query('items');
      final cached = await db.query('series_metadata_cache');
      await restoreV15CacheSchema();
      await db.execute('DROP INDEX idx_items_series_membership');
      await db.delete('schema_migrations', where: 'version >= 16');
      await db.execute('PRAGMA user_version = 15');
      await adapter.close();
      db = await adapter.database;
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        17,
      );
      expect(await db.query('items'), items);
      expect(await db.query('series_metadata_cache'), cached);
      expect(
        (await db.query(
          'schema_migrations',
          where: 'version = 16',
        )).single['name'],
        const SeriesMetadataV16Migration().name,
      );
    },
  );
  test(
    'populated-cache import probe compares v15/v16 episode-write overhead',
    () async {
      await restoreV15CacheSchema();
      await db.execute('''
WITH RECURSIVE n(x) AS (SELECT 100 UNION ALL SELECT x+1 FROM n WHERE x < 3099)
INSERT INTO series_v8(series_key, playlist_id, group_id, title, sort_title, ord)
SELECT x, 'q', 1, 'Cached show', 'cached show', x FROM n
''');
      await db.execute('''
INSERT INTO series_metadata_cache
SELECT 'q', series_key, 0, 'en', '99', '{}', 1, 1, 514
FROM series_v8 WHERE series_key >= 100
''');
      Future<int> measure() async {
        final timer = Stopwatch()..start();
        await db.transaction(
          (txn) => txn.execute('''
WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x < 30000)
INSERT INTO items(id, playlist_id, item_key, content_hash, ord, kind, group_id,
  title, sort_title, stream_url, series_key)
SELECT x, 'p', x, 1, x, 3, 1, 'Episode', 'episode', 'https://fixture.test/' || x, 7
FROM n
'''),
        );
        timer.stop();
        expect(
          (await db.rawQuery('SELECT COUNT(*) AS n FROM items')).single['n'],
          30000,
        );
        expect(await db.query('series_metadata_cache'), hasLength(3000));
        return timer.elapsedMilliseconds;
      }

      final before = await measure();
      await const SeriesMetadataV16Migration().up(db);
      await db.delete('items');
      final after = await measure();
      debugPrint(
        '30,000 episode writes with 3,000 unrelated cached shows: '
        'v15=${before}ms; v16=${after}ms (SQLite fixture; not whole-import timing)',
      );
    },
  );
}
