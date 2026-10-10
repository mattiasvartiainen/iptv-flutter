import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_hash.dart';
import 'package:iptv_flutter/services/catalog/catalog_importer.dart';
import 'package:iptv_flutter/services/catalog/user_library_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';

import '../../support/catalog_http_test_server.dart';
import '../../support/database_adapter.dart';

const String _alphaUrl = 'https://stream.test/alpha.m3u8';
const String _betaUrl = 'https://stream.test/beta.m3u8';

const String _playlist =
    '''#EXTM3U
#EXTINF:-1 group-title="News",Alpha News
$_alphaUrl
#EXTINF:-1 group-title="News",Beta News
$_betaUrl
''';

void main() {
  late SqfliteDatabaseAdapter adapter;
  late CatalogHttpTestServer server;
  late CatalogImporter importer;
  late SqliteUserLibraryRepository library;
  final alphaKey = hash64(_alphaUrl);
  final betaKey = hash64(_betaUrl);

  setUp(() async {
    adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_user_library_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    server = await CatalogHttpTestServer.start(
      responses: {
        '/playlist.m3u': _playlist,
        '/without-alpha.m3u':
            '#EXTM3U\n#EXTINF:-1 group-title="News",Beta News\n$_betaUrl\n',
      },
    );
    addTearDown(server.close);
    importer = CatalogImporter(databaseAdapter: adapter);
    await importer.importPlaylist(
      playlistId: 'library',
      playlistUrl: server.url('/playlist.m3u'),
    );
    library = SqliteUserLibraryRepository(databaseAdapter: adapter);
  });

  test('favorites are idempotent, per profile, and removable', () async {
    await library.setFavorite(
      playlistId: 'library',
      itemKey: alphaKey,
      favorite: true,
    );
    await library.setFavorite(
      playlistId: 'library',
      itemKey: alphaKey,
      favorite: true,
    );

    expect(
      (await library.favoriteItems(playlistId: 'library')).map((i) => i.title),
      ['Alpha News'],
    );
    expect(
      await library.favoriteItems(playlistId: 'library', profileId: 'other'),
      isEmpty,
    );

    await library.setFavorite(
      playlistId: 'library',
      itemKey: alphaKey,
      favorite: false,
    );
    expect(await library.favoriteItems(playlistId: 'library'), isEmpty);
  });

  test('playback progress is replaced per item', () async {
    expect(
      await library.playbackProgress(playlistId: 'library', itemKey: alphaKey),
      isNull,
    );

    await library.savePlaybackProgress(
      playlistId: 'library',
      itemKey: alphaKey,
      positionMs: 1000,
      durationMs: 9000,
    );
    await library.savePlaybackProgress(
      playlistId: 'library',
      itemKey: alphaKey,
      positionMs: 4000,
    );

    final progress = await library.playbackProgress(
      playlistId: 'library',
      itemKey: alphaKey,
    );
    expect(progress?.itemKey, alphaKey);
    expect(progress?.positionMs, 4000);
    expect(progress?.durationMs, isNull);
  });

  test('recently watched lists each item once, newest first', () async {
    await library.recordWatchHistory(
      playlistId: 'library',
      itemKey: alphaKey,
      completed: false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await library.recordWatchHistory(
      playlistId: 'library',
      itemKey: betaKey,
      completed: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await library.recordWatchHistory(
      playlistId: 'library',
      itemKey: alphaKey,
      completed: true,
      positionMs: 500,
    );

    expect(
      (await library.recentlyWatchedItems(
        playlistId: 'library',
      )).map((item) => item.title),
      ['Alpha News', 'Beta News'],
    );
  });

  test('user rows are keyed by item and survive the item leaving the '
      'catalog', () async {
    await library.setFavorite(
      playlistId: 'library',
      itemKey: alphaKey,
      favorite: true,
    );

    await importer.importPlaylist(
      playlistId: 'library',
      playlistUrl: server.url('/without-alpha.m3u'),
    );
    expect(await library.favoriteItems(playlistId: 'library'), isEmpty);

    await importer.importPlaylist(
      playlistId: 'library',
      playlistUrl: server.url('/playlist.m3u'),
    );
    expect(
      (await library.favoriteItems(playlistId: 'library')).map((i) => i.title),
      ['Alpha News'],
    );
  });
}
