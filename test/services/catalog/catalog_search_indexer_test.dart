import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_importer.dart';
import 'package:iptv_flutter/services/catalog/catalog_search_indexer.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';

import '../../support/catalog_http_test_server.dart';
import '../../support/database_adapter.dart';

const String _playlist = '''#EXTM3U
#EXTINF:-1 group-title="News",Alpha News
https://stream.test/alpha.m3u8
#EXTINF:-1 group-title="News",Beta News
https://stream.test/beta.m3u8
#EXTINF:-1 group-title="Movies",Gamma Movie
https://stream.test/gamma.mp4
''';

void main() {
  late SqfliteDatabaseAdapter adapter;

  setUp(() async {
    adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_indexer_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final server = await CatalogHttpTestServer.start(
      responses: {'/playlist.m3u': _playlist},
    );
    addTearDown(server.close);
    await CatalogImporter(databaseAdapter: adapter).importCold(
      playlistId: 'indexed',
      playlistUrl: server.url('/playlist.m3u'),
    );
  });

  Future<List<Map<String, Object?>>> search(String term) async =>
      (await adapter.database).rawQuery(
        'SELECT rowid FROM items_fts WHERE items_fts MATCH ?',
        [term],
      );

  test('drains the queue in bounded batches and reports status', () async {
    final indexer = SqliteCatalogSearchIndexer(
      databaseAdapter: adapter,
      autoStartWorker: false,
    );

    final queued = await indexer.status('indexed');
    expect(queued.totalItems, 3);
    expect(queued.indexedItems, 0);
    expect(queued.pendingItems, 3);
    expect(queued.isIndexing, isTrue);

    expect(await indexer.processQueue(playlistId: 'indexed', batchSize: 1), 3);

    final done = await indexer.status('indexed');
    expect(done.indexedItems, 3);
    expect(done.pendingItems, 0);
    expect(await search('Gamma'), hasLength(1));
  });

  test('a paused playlist is not drained until the pause ends', () async {
    final indexer = SqliteCatalogSearchIndexer(
      databaseAdapter: adapter,
      autoStartWorker: false,
    );

    final drainedWhilePaused = await indexer.whilePaused(
      'indexed',
      () => indexer.processQueue(playlistId: 'indexed'),
    );

    expect(drainedWhilePaused, 0);
    expect((await indexer.status('indexed')).pendingItems, 3);
    expect(await indexer.processQueue(playlistId: 'indexed'), 3);
  });

  test('scheduling is a no-op when the background worker is off', () async {
    final indexer = SqliteCatalogSearchIndexer(
      databaseAdapter: adapter,
      autoStartWorker: false,
    );

    indexer.scheduleIndexing('indexed');
    await indexer.resumePendingIndexing();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect((await indexer.status('indexed')).pendingItems, 3);
  });

  test('resuming pending work drains every queued playlist', () async {
    final indexer = SqliteCatalogSearchIndexer(databaseAdapter: adapter);

    await indexer.resumePendingIndexing();
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while ((await indexer.status('indexed')).pendingItems > 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect((await indexer.status('indexed')).pendingItems, 0);
    expect(await search('Alpha'), hasLength(1));
  });
}
