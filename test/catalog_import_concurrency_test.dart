import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';

import 'support/catalog_http_test_server.dart';
import 'support/catalog_services.dart';
import 'support/database_adapter.dart';

const String _oneLiveChannel = '''#EXTM3U
#EXTINF:-1 group-title="News",Alpha News
https://stream.test/alpha.m3u8
''';

void main() {
  late SqfliteDatabaseAdapter adapter;

  setUp(() {
    adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_concurrency_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() => adapter.close());

  test('two concurrent load() calls for the same playlist share one import '
      'instead of racing a second transaction', () async {
    final responseGate = Completer<void>();
    final server = await CatalogHttpTestServer.start(
      responses: {'/playlist.m3u': _oneLiveChannel},
      beforeResponse: responseGate.future,
    );
    addTearDown(server.close);
    final sync = createCatalogSyncService(adapter);

    final first = sync.load(
      playlistId: 'concurrent-playlist',
      playlistUrl: server.url('/playlist.m3u'),
      policy: CatalogLoadPolicy.networkOnly,
    );
    await server.firstRequest.future;
    final second = sync.load(
      playlistId: 'concurrent-playlist',
      playlistUrl: server.url('/playlist.m3u'),
      policy: CatalogLoadPolicy.networkOnly,
    );
    responseGate.complete();

    final results = await Future.wait([first, second]);

    expect(server.requestCount, 1);
    expect(results[0].itemCount, 1);
    expect(results[1].itemCount, 1);
    expect(results[0].playlistId, results[1].playlistId);
  });

  test('a load() after the first completes starts a fresh import', () async {
    final server = await CatalogHttpTestServer.start(
      responses: {'/playlist.m3u': _oneLiveChannel},
    );
    addTearDown(server.close);
    final sync = createCatalogSyncService(adapter);

    await sync.load(
      playlistId: 'concurrent-playlist',
      playlistUrl: server.url('/playlist.m3u'),
    );
    await sync.load(
      playlistId: 'concurrent-playlist',
      playlistUrl: server.url('/playlist.m3u'),
      policy: CatalogLoadPolicy.networkOnly,
    );

    expect(server.requestCount, 2);
  });
}
