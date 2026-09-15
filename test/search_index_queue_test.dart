import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';

const String _twoLiveChannels = '''#EXTM3U
#EXTINF:-1 group-title="News",Alpha News
https://stream.test/alpha.m3u8
#EXTINF:-1 group-title="News",Beta News
https://stream.test/beta.m3u8
''';

void main() {
  late SqfliteDatabaseAdapter adapter;

  Future<String> firstPlaylistId() async {
    final db = await adapter.database;
    final rows = await db.query('playlists', columns: ['id']);
    return rows.single['id']! as String;
  }

  Future<int> queueLength(String playlistId) async {
    final db = await adapter.database;
    final rows = await db.query(
      'search_index_queue',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    return rows.length;
  }

  Future<bool> isDirty(String playlistId) async {
    final db = await adapter.database;
    final rows = await db.query(
      'playlists',
      columns: ['search_index_dirty'],
      where: 'id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    return (rows.single['search_index_dirty'] as int) == 1;
  }

  Future<List<String>> ftsTitlesFor(String playlistId) async {
    final db = await adapter.database;
    final rows = await db.rawQuery(
      '''
SELECT f.title AS title FROM media_items_fts f
JOIN media_items m ON m.id = f.media_item_id
WHERE m.playlist_id = ?
ORDER BY f.title
''',
      [playlistId],
    );
    return rows.map((row) => row['title'] as String).toList();
  }

  setUp(() {
    adapter = SqfliteDatabaseAdapter(
      fileName:
          'iptv_test_search_index_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() => adapter.close());

  test(
    'a successful import queues upserts and marks the playlist dirty',
    () async {
      final repo = SqliteCatalogRepository(
        source: const FakePlaylistSource(_twoLiveChannels),
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
        autoStartSearchIndexWorker: false,
      );

      await repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
      final playlistId = await firstPlaylistId();

      expect(await queueLength(playlistId), 2);
      expect(await isDirty(playlistId), isTrue);

      final db = await adapter.database;
      final queued = await db.query(
        'search_index_queue',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      // A first import knows nothing is indexed yet, so it queues plain
      // inserts and the worker skips the removal half of a reindex.
      expect(queued.every((row) => row['operation'] == 'insert'), isTrue);
    },
  );

  test(
    'processSearchIndexQueue drains queued upserts into FTS and clears the dirty flag',
    () async {
      final repo = SqliteCatalogRepository(
        source: const FakePlaylistSource(_twoLiveChannels),
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
        autoStartSearchIndexWorker: false,
      );

      await repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
      final playlistId = await firstPlaylistId();

      final processed = await repo.processSearchIndexQueue(
        playlistId: playlistId,
      );

      expect(processed, 2);
      expect(await queueLength(playlistId), 0);
      expect(await isDirty(playlistId), isFalse);
      expect(await ftsTitlesFor(playlistId), ['Alpha News', 'Beta News']);
    },
  );

  test(
    'a renamed item queues an upsert that overwrites the stale FTS row',
    () async {
      final repo = SqliteCatalogRepository(
        source: const FakePlaylistSource(_twoLiveChannels),
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
        autoStartSearchIndexWorker: false,
      );

      await repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
      final playlistId = await firstPlaylistId();
      await repo.processSearchIndexQueue(playlistId: playlistId);

      final renamed = const FakePlaylistSource('''#EXTM3U
#EXTINF:-1 group-title="News",Alpha News Updated
https://stream.test/alpha.m3u8
#EXTINF:-1 group-title="News",Beta News
https://stream.test/beta.m3u8
''');
      final repo2 = SqliteCatalogRepository(
        source: renamed,
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
        autoStartSearchIndexWorker: false,
      );
      await repo2.load(
        playlistUrl: 'https://provider.test/playlist.m3u',
        playlistId: playlistId,
        policy: CatalogLoadPolicy.networkOnly,
      );

      expect(await isDirty(playlistId), isTrue);
      await repo2.processSearchIndexQueue(playlistId: playlistId);

      expect(await ftsTitlesFor(playlistId), [
        'Alpha News Updated',
        'Beta News',
      ]);
    },
  );

  test('a removed item queues a delete that clears its FTS row', () async {
    final repo = SqliteCatalogRepository(
      source: const FakePlaylistSource(_twoLiveChannels),
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
      autoStartSearchIndexWorker: false,
    );

    await repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
    final playlistId = await firstPlaylistId();
    await repo.processSearchIndexQueue(playlistId: playlistId);
    expect(await ftsTitlesFor(playlistId), hasLength(2));

    final oneItem = const FakePlaylistSource('''#EXTM3U
#EXTINF:-1 group-title="News",Beta News
https://stream.test/beta.m3u8
''');
    final repo2 = SqliteCatalogRepository(
      source: oneItem,
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
      autoStartSearchIndexWorker: false,
    );
    await repo2.load(
      playlistUrl: 'https://provider.test/playlist.m3u',
      playlistId: playlistId,
      policy: CatalogLoadPolicy.networkOnly,
    );

    final db = await adapter.database;
    final queuedOps = await db.query(
      'search_index_queue',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    expect(queuedOps.any((row) => row['operation'] == 'delete'), isTrue);

    await repo2.processSearchIndexQueue(playlistId: playlistId);
    expect(await ftsTitlesFor(playlistId), ['Beta News']);
  });

  test(
    'draining honors a small batch size and still empties the queue',
    () async {
      final manyItems = StringBuffer('#EXTM3U\n');
      for (var i = 0; i < 7; i++) {
        manyItems.writeln('#EXTINF:-1 group-title="News",Channel $i');
        manyItems.writeln('https://stream.test/channel-$i.m3u8');
      }
      final repo = SqliteCatalogRepository(
        source: FakePlaylistSource(manyItems.toString()),
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
        autoStartSearchIndexWorker: false,
      );

      await repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
      final playlistId = await firstPlaylistId();

      final processed = await repo.processSearchIndexQueue(
        playlistId: playlistId,
        batchSize: 2,
      );

      expect(processed, 7);
      expect(await queueLength(playlistId), 0);
      expect(await ftsTitlesFor(playlistId), hasLength(7));
    },
  );

  test('draining an already-empty queue is a safe no-op', () async {
    final repo = SqliteCatalogRepository(
      source: const FakePlaylistSource(_twoLiveChannels),
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
      autoStartSearchIndexWorker: false,
    );

    await repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
    final playlistId = await firstPlaylistId();
    await repo.processSearchIndexQueue(playlistId: playlistId);

    final second = await repo.processSearchIndexQueue(playlistId: playlistId);
    expect(second, 0);
  });

  test('the background worker started by load() eventually drains the queue '
      'without an explicit call', () async {
    final repo = SqliteCatalogRepository(
      source: const FakePlaylistSource(_twoLiveChannels),
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
    );

    await repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
    final playlistId = await firstPlaylistId();

    var dirty = true;
    for (var attempt = 0; attempt < 50 && dirty; attempt++) {
      await Future<void>.delayed(Duration.zero);
      dirty = await isDirty(playlistId);
    }

    expect(dirty, isFalse);
    expect(await ftsTitlesFor(playlistId), hasLength(2));
  });
}
