import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/catalog_search_indexer.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';

import '../../support/catalog_http_test_server.dart';
import '../../support/catalog_services.dart';
import '../../support/database_adapter.dart';

const String _playlist = '''#EXTM3U
#EXTINF:-1 group-title="News",Alpha News
https://stream.test/alpha.m3u8
#EXTINF:-1 group-title="News",Beta News
https://stream.test/beta.m3u8
''';

void main() {
  late SqfliteDatabaseAdapter adapter;
  late CatalogHttpTestServer server;

  setUp(() async {
    adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_sync_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    server = await CatalogHttpTestServer.start(
      responses: {'/playlist.m3u': _playlist, '/empty.m3u': '#EXTM3U\n'},
    );
    addTearDown(server.close);
  });

  test('cacheOnly returns the cached count without fetching', () async {
    final indexer = _RecordingSearchIndexer();
    final sync = createCatalogSyncService(adapter, searchIndexer: indexer);

    final result = await sync.load(
      playlistId: 'cache-only',
      playlistUrl: server.url('/playlist.m3u'),
      policy: CatalogLoadPolicy.cacheOnly,
    );

    expect(result.playlistId, 'cache-only');
    expect(result.itemCount, 0);
    expect(server.requestCount, 0);
    expect(indexer.events, isEmpty);
  });

  test('imports while indexing is paused, then schedules indexing', () async {
    final indexer = _RecordingSearchIndexer(
      onPaused: () => 'requests=${server.requestCount}',
    );
    final sync = createCatalogSyncService(adapter, searchIndexer: indexer);

    final result = await sync.load(
      playlistId: 'paused-import',
      playlistUrl: server.url('/playlist.m3u'),
      policy: CatalogLoadPolicy.networkOnly,
    );

    expect(result.itemCount, 2);
    expect(indexer.events, [
      'pause:paused-import',
      'release:paused-import:requests=1',
      'schedule:paused-import',
    ]);
  });

  test('a failed import releases the pause without scheduling', () async {
    final indexer = _RecordingSearchIndexer();
    final sync = createCatalogSyncService(adapter, searchIndexer: indexer);

    await expectLater(
      sync.load(
        playlistId: 'failed-import',
        playlistUrl: server.url('/empty.m3u'),
        policy: CatalogLoadPolicy.networkOnly,
      ),
      throwsA(isA<Exception>()),
    );

    expect(indexer.events, ['pause:failed-import', 'release:failed-import:']);
  });

  test('cacheFirst reuses a cached catalog with no refresh due', () async {
    final indexer = _RecordingSearchIndexer();
    final sync = createCatalogSyncService(adapter, searchIndexer: indexer);
    await sync.load(
      playlistId: 'cache-first',
      playlistUrl: server.url('/playlist.m3u'),
      policy: CatalogLoadPolicy.networkOnly,
    );
    final db = await adapter.database;
    await db.insert('playlists', {
      'id': 'cache-first',
      'name': 'Cache first',
      'secure_storage_key': 'cache-first',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await db.insert('playlist_settings', {
      'playlist_id': 'cache-first',
      'refresh_enabled': 1,
      'refresh_mode': 'weekly',
      'refresh_interval_hours': 168,
      'next_refresh_at': DateTime.now()
          .toUtc()
          .add(const Duration(days: 1))
          .toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    indexer.events.clear();

    final result = await sync.load(
      playlistId: 'cache-first',
      playlistUrl: server.url('/playlist.m3u'),
    );

    expect(result.itemCount, 2);
    expect(server.requestCount, 1);
    expect(indexer.events, isEmpty);
  });
}

class _RecordingSearchIndexer implements CatalogSearchIndexer {
  _RecordingSearchIndexer({this.onPaused});

  final String Function()? onPaused;
  final List<String> events = [];

  @override
  Future<T> whilePaused<T>(
    String playlistId,
    Future<T> Function() action,
  ) async {
    events.add('pause:$playlistId');
    try {
      return await action();
    } finally {
      events.add('release:$playlistId:${onPaused?.call() ?? ''}');
    }
  }

  @override
  void scheduleIndexing(String playlistId) =>
      events.add('schedule:$playlistId');

  @override
  Future<void> resumePendingIndexing() async {}

  @override
  Future<int> processQueue({String? playlistId, int batchSize = 0}) async => 0;

  @override
  Future<CatalogSearchIndexStatus> status(String playlistId) async =>
      const CatalogSearchIndexStatus(
        totalItems: 0,
        indexedItems: 0,
        pendingItems: 0,
      );
}
