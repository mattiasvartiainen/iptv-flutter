import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_hash.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_coordinator.dart';
import 'package:iptv_flutter/services/catalog/catalog_importer.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';

import 'support/database_adapter.dart';

const String _playlist = '''#EXTM3U
#EXTINF:-1 group-title="News",Alpha News
https://stream.test/alpha.m3u8
#EXTINF:-1 group-title="Movies",The Example Movie
https://stream.test/movie.mp4
#EXTINF:-1 type="series" group-title="Drama",Example Show S01E01
https://provider.test/series/user/pass/episode-1.mkv
#EXTINF:-1 type="series" group-title="Drama",Example Show S01E02
https://provider.test/series/user/pass/episode-2.mkv
''';

void main() {
  late SqfliteDatabaseAdapter adapter;

  setUp(() {
    adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_catalog_import_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() => adapter.close());

  test('cold import persists catalog and queues searchable rows', () async {
    final server = await _serve(_playlist);
    addTearDown(() => server.close(force: true));
    final progress = <CatalogImportProgress>[];
    final importer = CatalogImporter(databaseAdapter: adapter);

    final result = await importer.importCold(
      playlistId: 'v9-playlist',
      playlistUrl: 'http://127.0.0.1:${server.port}/playlist.m3u',
      onProgress: progress.add,
    );

    final db = await adapter.database;
    final items = await db.query('items', orderBy: 'ord');
    final groups = await db.query('groups', orderBy: 'ord');
    final series = await db.query('series_v8');
    final sessions = await db.query('import_sessions');
    final timings =
        jsonDecode(sessions.single['stage_timings']! as String)
            as Map<String, Object?>;

    expect(result.itemCount, 4);
    expect(result.groupCount, 3);
    expect(result.rejectedCount, 0);
    expect(items.map((row) => row['ord']), [0, 1, 2, 3]);
    expect(groups.map((row) => row['title']), ['News', 'Movies', 'Drama']);
    expect(groups.map((row) => row['item_count']), [1, 1, 2]);
    expect(series.single['title'], 'Example Show');
    expect(series.single['season_count'], 1);
    expect(series.single['episode_count'], 2);
    expect(sessions.single['state'], 'done');
    expect(sessions.single['items_new'], 4);
    expect(timings['total'], isA<int>());
    expect(await db.query('items_fts_queue'), hasLength(4));
    expect(
      await db.rawQuery(
        "SELECT rowid FROM items_fts WHERE items_fts MATCH 'Alpha'",
      ),
      isEmpty,
    );
    await _drainCatalogSearchIndex(adapter, 'v9-playlist');
    expect(
      await db.rawQuery(
        "SELECT rowid FROM items_fts WHERE items_fts MATCH 'Alpha'",
      ),
      hasLength(1),
    );
    expect(
      progress.where((event) => event.phase == CatalogImportPhase.importing),
      isNotEmpty,
    );
    expect(
      progress
          .where((event) => event.phase != CatalogImportPhase.starting)
          .every((event) => event.importSessionId == sessions.single['id']),
      isTrue,
    );
  });

  test('repository cold imports and refreshes through v9', () async {
    final server = await _serve(_playlist);
    addTearDown(() => server.close(force: true));
    final repository = SqliteCatalogRepository(
      databaseAdapter: adapter,
      autoStartSearchIndexWorker: false,
    );

    final result = await repository.load(
      playlistId: 'opt-in-playlist',
      playlistUrl: 'http://127.0.0.1:${server.port}/playlist.m3u',
      policy: CatalogLoadPolicy.networkOnly,
    );
    final db = await adapter.database;
    final originalIds = (await db.query(
      'items',
      orderBy: 'ord',
    )).map((row) => row['id']).toList();
    final refreshed = await repository.load(
      playlistId: 'opt-in-playlist',
      playlistUrl: 'http://127.0.0.1:${server.port}/playlist.m3u',
      policy: CatalogLoadPolicy.networkOnly,
    );

    expect(result.itemCount, 4);
    expect(refreshed.itemCount, 4);
    expect(await db.query('items'), hasLength(4));
    expect(
      (await db.query('items', orderBy: 'ord')).map((row) => row['id']),
      originalIds,
    );
    final sessions = await db.query('import_sessions', orderBy: 'id');
    expect(sessions.map((row) => row['tier']), ['cold_import', 'row_diff']);
    expect(sessions.last['items_new'], 0);
    expect(sessions.last['items_changed'], 0);
  });

  test(
    'v9 search indexing resumes queued work and reports its progress',
    () async {
      final server = await _serve(_playlist);
      addTearDown(() => server.close(force: true));
      await CatalogImporter(databaseAdapter: adapter).importCold(
        playlistId: 'resume-search',
        playlistUrl: 'http://127.0.0.1:${server.port}/playlist.m3u',
      );
      final repository = SqliteCatalogRepository(
        databaseAdapter: adapter,
        autoStartSearchIndexWorker: true,
      );

      final queued = await repository.searchIndexStatus('resume-search');
      expect(queued.totalItems, 4);
      expect(queued.indexedItems, 0);
      expect(queued.pendingItems, 4);

      await repository.resumeSearchIndexing();
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      var status = queued;
      while (status.pendingItems > 0 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        status = await repository.searchIndexStatus('resume-search');
      }

      expect(status.pendingItems, 0);
      expect(status.indexedItems, 4);
      expect(
        await (await adapter.database).rawQuery(
          "SELECT rowid FROM items_fts WHERE items_fts MATCH 'Alpha'",
        ),
        hasLength(1),
      );
    },
  );

  test('flat catalog queries and playback lookup read the v9 schema', () async {
    final server = await _serve(_playlist);
    addTearDown(() => server.close(force: true));
    final repository = SqliteCatalogRepository(databaseAdapter: adapter);
    final loaded = await repository.load(
      playlistId: 'query-v9',
      playlistName: 'v9 fixture',
      playlistUrl: 'http://127.0.0.1:${server.port}/playlist.m3u',
      policy: CatalogLoadPolicy.networkOnly,
    );

    final live = await repository.queryItems(
      CatalogQuery(
        playlistId: loaded.playlistId!,
        kinds: const [CatalogItemKind.live],
        group: 'News',
      ),
    );
    expect(live.total, 1);
    expect(live.items.single.title, 'Alpha News');
    expect(live.items.single.id, matches(RegExp(r'^\d+$')));

    final liveGroups = await repository.queryGroups(
      loaded.playlistId!,
      kind: CatalogGroupKind.live,
    );
    expect(liveGroups.map((group) => group.title), ['News']);
    expect(liveGroups.single.itemCount, 1);
    final groupPage = await repository.itemsInGroup(
      loaded.playlistId!,
      liveGroups.single.id,
      limit: 1,
    );
    expect(groupPage.total, 1);
    expect(groupPage.items.single.title, 'Alpha News');

    final preview = await repository.homePreview(
      loaded.playlistId!,
      kind: CatalogItemKind.movie,
    );
    expect(preview.single.title, 'The Example Movie');

    final search = await repository.queryItems(
      CatalogQuery(playlistId: loaded.playlistId!, searchTerm: 'Alpha'),
    );
    expect(search.items.map((item) => item.title), ['Alpha News']);

    final seriesPage = await repository.querySeries(loaded.playlistId!);
    expect(seriesPage.total, 1);
    final seasons = await repository.seasons(seriesPage.items.single.id);
    expect(seasons.map((season) => season.seasonNumber), [1]);
    final episodes = await repository.episodes(seasons.single.id);
    expect(episodes.total, 2);
    expect(episodes.items.map((item) => item.kind), [
      CatalogItemKind.episode,
      CatalogItemKind.episode,
    ]);
    final seriesGroups = await repository.queryGroups(
      loaded.playlistId!,
      kind: CatalogGroupKind.series,
    );
    expect(seriesGroups.single.title, 'Drama');
    expect(seriesGroups.single.itemCount, 2);
    expect(
      (await repository.seriesInGroup(
        loaded.playlistId!,
        seriesGroups.single.id,
      )).total,
      1,
    );

    final settings = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
    );
    await settings.setGroupHidden(
      playlistId: loaded.playlistId!,
      kind: CatalogGroupKind.live,
      groupTitle: 'News',
      hidden: true,
    );
    expect(
      await repository.queryGroups(
        loaded.playlistId!,
        kind: CatalogGroupKind.live,
      ),
      isEmpty,
    );
    expect(
      (await repository.queryItems(
        CatalogQuery(playlistId: loaded.playlistId!, searchTerm: 'Alpha'),
      )).items,
      isEmpty,
    );
    expect(
      await repository.itemsInGroup(loaded.playlistId!, liveGroups.single.id),
      isEmpty,
    );

    final selected = await repository.itemById(live.items.single.id);
    expect(selected?.streamUrl, 'https://stream.test/alpha.m3u8');
    expect(selected?.metadata['tvg-id'], isNull);

    final alphaKey = hash64('https://stream.test/alpha.m3u8');
    await repository.setV9Favorite(
      playlistId: loaded.playlistId!,
      itemKey: alphaKey,
      favorite: true,
    );
    await repository.saveV9PlaybackProgress(
      playlistId: loaded.playlistId!,
      itemKey: alphaKey,
      positionMs: 2500,
      durationMs: 9000,
    );
    await repository.recordV9WatchHistory(
      playlistId: loaded.playlistId!,
      itemKey: alphaKey,
      completed: false,
      positionMs: 2500,
      durationMs: 9000,
    );

    final refreshedServer = await _serve(
      _playlist.replaceFirst('Alpha News', 'Alpha HD'),
    );
    try {
      await repository.load(
        playlistId: loaded.playlistId!,
        playlistName: 'v9 fixture',
        playlistUrl: 'http://127.0.0.1:${refreshedServer.port}/changed.m3u',
        policy: CatalogLoadPolicy.networkOnly,
      );
    } finally {
      await refreshedServer.close(force: true);
    }
    expect(
      (await repository.v9FavoriteItems(
        playlistId: loaded.playlistId!,
      )).single.title,
      'Alpha HD',
    );
    expect(
      (await repository.v9RecentlyWatchedItems(
        playlistId: loaded.playlistId!,
      )).single.title,
      'Alpha HD',
    );
    expect(
      (await repository.v9PlaybackProgress(
        playlistId: loaded.playlistId!,
        itemKey: alphaKey,
      ))?.positionMs,
      2500,
    );
  });

  test(
    'failed second batch removes partial cold catalog and FTS rows',
    () async {
      final content = StringBuffer('#EXTM3U\n');
      for (var index = 0; index < 1001; index++) {
        content
          ..writeln('#EXTINF:-1 group-title="News",Channel $index')
          ..writeln('https://stream.test/$index.m3u8');
      }
      final server = await _serve(content.toString());
      addTearDown(() => server.close(force: true));
      final db = await adapter.database;
      await db.execute('''
CREATE TRIGGER fail_second_import_batch
BEFORE INSERT ON items WHEN NEW.ord >= 1000
BEGIN SELECT RAISE(ABORT, 'injected second-batch failure'); END
''');
      final importer = CatalogImporter(databaseAdapter: adapter);

      await expectLater(
        importer.importCold(
          playlistId: 'failure-playlist',
          playlistUrl: 'http://127.0.0.1:${server.port}/playlist.m3u',
        ),
        throwsA(isA<Exception>()),
      );

      expect(
        await db.query(
          'items',
          where: 'playlist_id = ?',
          whereArgs: ['failure-playlist'],
        ),
        isEmpty,
      );
      expect(
        await db.query(
          'groups',
          where: 'playlist_id = ?',
          whereArgs: ['failure-playlist'],
        ),
        isEmpty,
      );
      expect(await db.rawQuery('SELECT rowid FROM items_fts'), isEmpty);
      final sessions = await db.query(
        'import_sessions',
        where: 'playlist_id = ?',
        whereArgs: ['failure-playlist'],
      );
      expect(sessions.single['state'], 'failed');
      expect(sessions.single['items_new'], 1000);
    },
  );

  test(
    'startup recovery clears rows from interrupted catalog imports',
    () async {
      final db = await adapter.database;
      await db.insert('groups', {
        'playlist_id': 'interrupted-playlist',
        'kind': 1,
        'title': 'News',
        'sort_title': 'news',
        'ord': 0,
      });
      final group = (await db.query('groups')).single;
      await db.insert('items', {
        'playlist_id': 'interrupted-playlist',
        'item_key': 10,
        'content_hash': 20,
        'ord': 0,
        'kind': 1,
        'group_id': group['id'],
        'title': 'Orphaned item',
        'sort_title': 'orphaned item',
        'stream_url': 'https://stream.test/orphaned.m3u8',
      });
      final item = (await db.query('items')).single;
      await db.insert('items_fts_queue', {
        'item_id': item['id'],
        'playlist_id': 'interrupted-playlist',
        'operation': 'upsert',
        'old_title': null,
        'priority': 1,
        'queued_at': DateTime.now().millisecondsSinceEpoch,
      });
      final sessionId = await db.insert('import_sessions', {
        'playlist_id': 'interrupted-playlist',
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'state': 'reconciling',
        'tier': 'cold_import',
      });
      await db.insert('import_rows', {
        'import_id': sessionId,
        'item_key': 11,
        'content_hash': 21,
        'ord': 1,
        'kind': 1,
        'group_kind': 1,
        'group_title': 'News',
        'title': 'Staged',
        'sort_title': 'staged',
        'stream_url': 'https://stream.test/staged.m3u8',
      });

      final repository = SqliteCatalogRepository(databaseAdapter: adapter);
      await repository.recoverAbandonedImports();

      expect(await db.query('items'), isEmpty);
      expect(await db.query('groups'), isEmpty);
      expect(await db.query('series_v8'), isEmpty);
      expect(await db.query('import_rows'), isEmpty);
      expect(await db.query('items_fts_queue'), isEmpty);
      expect(
        await db.rawQuery(
          "SELECT rowid FROM items_fts WHERE items_fts MATCH 'Orphaned'",
        ),
        isEmpty,
      );
      expect((await db.query('import_sessions')).single['state'], 'aborted');
    },
  );

  test(
    'legacy recovery does not delete catalog rows from the v9 path',
    () async {
      final db = await adapter.database;
      await db.insert('groups', {
        'playlist_id': 'preserved-playlist',
        'kind': 1,
        'title': 'News',
        'sort_title': 'news',
        'ord': 0,
      });
      final group = (await db.query('groups')).single;
      await db.insert('items', {
        'playlist_id': 'preserved-playlist',
        'item_key': 12,
        'content_hash': 22,
        'ord': 0,
        'kind': 1,
        'group_id': group['id'],
        'title': 'Kept item',
        'sort_title': 'kept item',
        'stream_url': 'https://stream.test/kept.m3u8',
      });
      await db.insert('import_sessions', {
        'playlist_id': 'preserved-playlist',
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'state': 'running',
        'tier': 'legacy_import',
      });

      final repository = SqliteCatalogRepository(databaseAdapter: adapter);
      await repository.recoverAbandonedImports();

      expect(await db.query('items'), hasLength(1));
      expect((await db.query('import_sessions')).single['state'], 'aborted');
    },
  );

  test(
    'startup recovery clears warm scratch data but preserves catalog rows',
    () async {
      final db = await adapter.database;
      await db.insert('groups', {
        'playlist_id': 'warm-interrupted',
        'kind': 1,
        'title': 'News',
        'sort_title': 'news',
        'ord': 0,
      });
      final group = (await db.query('groups')).single;
      await db.insert('items', {
        'playlist_id': 'warm-interrupted',
        'item_key': 31,
        'content_hash': 41,
        'ord': 0,
        'kind': 1,
        'group_id': group['id'],
        'title': 'Still live',
        'sort_title': 'still live',
        'stream_url': 'https://stream.test/still-live.m3u8',
      });
      final sessionId = await db.insert('import_sessions', {
        'playlist_id': 'warm-interrupted',
        'started_at': DateTime.now().millisecondsSinceEpoch,
        'state': 'running',
        'tier': 'row_diff',
      });
      await db.insert('import_seen', {
        'import_id': sessionId,
        'item_key': 31,
        'new_ord': 1,
      });
      await db.insert('import_rows', {
        'import_id': sessionId,
        'item_key': 32,
        'content_hash': 42,
        'ord': 2,
        'kind': 1,
        'group_kind': 1,
        'group_title': 'News',
        'title': 'Not committed',
        'sort_title': 'not committed',
        'stream_url': 'https://stream.test/not-committed.m3u8',
      });

      final repository = SqliteCatalogRepository(databaseAdapter: adapter);
      await repository.recoverAbandonedImports();

      expect((await db.query('items')).single['title'], 'Still live');
      expect(await db.query('import_rows'), isEmpty);
      expect(await db.query('import_seen'), isEmpty);
      expect((await db.query('import_sessions')).single['state'], 'aborted');
    },
  );

  test('cold importer refuses to overwrite an existing catalog', () async {
    final db = await adapter.database;
    await db.insert('groups', {
      'playlist_id': 'already-imported',
      'kind': 1,
      'title': 'News',
      'sort_title': 'news',
      'ord': 0,
    });
    final group = (await db.query('groups')).single;
    await db.insert('items', {
      'playlist_id': 'already-imported',
      'item_key': 77,
      'content_hash': 88,
      'ord': 0,
      'kind': 1,
      'group_id': group['id'],
      'title': 'Existing item',
      'sort_title': 'existing item',
      'stream_url': 'https://stream.test/existing.m3u8',
    });

    final importer = CatalogImporter(databaseAdapter: adapter);
    await expectLater(
      importer.importCold(
        playlistId: 'already-imported',
        playlistUrl: 'not-requested-until-the-catalog-is-empty',
      ),
      throwsA(isA<StateError>()),
    );

    final rows = await db.query(
      'items',
      where: 'playlist_id = ?',
      whereArgs: ['already-imported'],
    );
    expect(rows.single['title'], 'Existing item');
    expect(await db.query('import_sessions'), isEmpty);
  });

  test(
    'warm refresh writes only changed rows and applies reorder/add/remove diff',
    () async {
      final importer = CatalogImporter(databaseAdapter: adapter);
      const first = '''#EXTM3U
#EXTINF:-1 group-title="News",Alpha
https://stream.test/a.m3u8
#EXTINF:-1 group-title="News",Beta
https://stream.test/b.m3u8
#EXTINF:-1 group-title="News",Gamma
https://stream.test/c.m3u8
#EXTINF:-1 group-title="Sports",Delta
https://stream.test/d.m3u8
''';
      const second = '''#EXTM3U
#EXTINF:-1 group-title="News",Gamma
https://stream.test/c.m3u8
#EXTINF:-1 group-title="News",Alpha HD
https://stream.test/a.m3u8
#EXTINF:-1 group-title="Sports",Echo
https://stream.test/e.m3u8
''';
      const reordered = '''#EXTM3U
#EXTINF:-1 group-title="Sports",Echo
https://stream.test/e.m3u8
#EXTINF:-1 group-title="News",Gamma
https://stream.test/c.m3u8
#EXTINF:-1 group-title="News",Alpha HD
https://stream.test/a.m3u8
''';

      await _importText(importer, 'diff-playlist', first);
      await _drainCatalogSearchIndex(adapter, 'diff-playlist');
      final db = await adapter.database;
      final before = await db.query('items', orderBy: 'ord');
      final alphaId = before.firstWhere((row) => row['title'] == 'Alpha')['id'];
      final gammaId = before.firstWhere((row) => row['title'] == 'Gamma')['id'];

      final update = await _importText(importer, 'diff-playlist', second);
      expect(
        await (await adapter.database).query(
          'items_fts_queue',
          where: 'playlist_id = ?',
          whereArgs: ['diff-playlist'],
        ),
        hasLength(4),
      );
      await _drainCatalogSearchIndex(adapter, 'diff-playlist');
      final after = await db.query('items', orderBy: 'ord');
      expect(update.newCount, 1);
      expect(update.changedCount, 1);
      expect(update.movedCount, 1);
      expect(update.removedCount, 2);
      expect(update.itemCount, 3);
      expect(after.first['title'], 'Gamma');
      expect(after.first['id'], gammaId);
      expect(
        after.firstWhere((row) => row['title'] == 'Alpha HD')['id'],
        alphaId,
      );
      expect(
        await db.rawQuery(
          "SELECT rowid FROM items_fts WHERE items_fts MATCH 'Alpha'",
        ),
        hasLength(1),
      );
      expect(
        await db.rawQuery(
          "SELECT rowid FROM items_fts WHERE items_fts MATCH 'Beta'",
        ),
        isEmpty,
      );
      final updateSession = (await db.query(
        'import_sessions',
        where: 'id = ?',
        whereArgs: [update.importSessionId],
      )).single;
      expect(updateSession['items_new'], 1);
      expect(updateSession['items_changed'], 1);
      expect(updateSession['items_moved'], 1);
      expect(updateSession['items_removed'], 2);

      final same = await _importText(importer, 'diff-playlist', second);
      expect(same.newCount, 0);
      expect(same.changedCount, 0);
      expect(same.movedCount, 0);
      expect(same.removedCount, 0);

      final moveOnly = await _importText(importer, 'diff-playlist', reordered);
      expect(moveOnly.newCount, 0);
      expect(moveOnly.changedCount, 0);
      expect(moveOnly.movedCount, 3);
      expect(moveOnly.removedCount, 0);
      expect(
        (await db.query('items', orderBy: 'ord')).map((row) => row['title']),
        ['Echo', 'Gamma', 'Alpha HD'],
      );
    },
  );

  test(
    'failed warm refresh preserves the previously imported catalog',
    () async {
      final importer = CatalogImporter(databaseAdapter: adapter);
      await _importText(importer, 'stable-playlist', _playlist);
      final before = await (await adapter.database).query(
        'items',
        where: 'playlist_id = ?',
        whereArgs: ['stable-playlist'],
        orderBy: 'ord',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      });

      await expectLater(
        importer.importPlaylist(
          playlistId: 'stable-playlist',
          playlistUrl: 'http://127.0.0.1:${server.port}/failed.m3u',
        ),
        throwsA(isA<Exception>()),
      );

      final after = await (await adapter.database).query(
        'items',
        where: 'playlist_id = ?',
        whereArgs: ['stable-playlist'],
        orderBy: 'ord',
      );
      expect(
        after.map((row) => row['item_key']),
        before.map((row) => row['item_key']),
      );
      expect(
        after.map((row) => row['title']),
        before.map((row) => row['title']),
      );
      final sessions = await (await adapter.database).query(
        'import_sessions',
        where: 'playlist_id = ?',
        whereArgs: ['stable-playlist'],
        orderBy: 'id DESC',
        limit: 1,
      );
      expect(sessions.single['state'], 'failed');
    },
  );

  test(
    'favorite and playback writes complete while warm download is in flight',
    () async {
      final importer = CatalogImporter(databaseAdapter: adapter);
      await _importText(importer, 'concurrent-playlist', _playlist);
      final responseGate = Completer<void>();
      final responseStarted = Completer<void>();
      final response = StringBuffer(
        _playlist.replaceFirst('Alpha News', 'Alpha HD'),
      );
      for (var index = 0; index < 1096; index++) {
        response
          ..writeln('#EXTINF:-1 group-title="News",Channel $index')
          ..writeln('https://stream.test/concurrent-$index.m3u8');
      }
      final responseBytes = utf8.encode(response.toString());
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType.text;
        request.response.contentLength = responseBytes.length;
        request.response.add(responseBytes);
        await request.response.flush();
        responseStarted.complete();
        await responseGate.future;
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final parseStarted = Completer<void>();
      final loading = importer.importPlaylist(
        playlistId: 'concurrent-playlist',
        playlistUrl: 'http://127.0.0.1:${server.port}/warm.m3u',
        onProgress: (progress) {
          if (progress.phase == CatalogImportPhase.parsing &&
              !parseStarted.isCompleted) {
            parseStarted.complete();
          }
        },
      );

      await responseStarted.future;
      await parseStarted.future;
      final db = await adapter.database;
      final alphaKey = hash64('https://stream.test/alpha.m3u8');
      final writeStopwatch = Stopwatch()..start();
      await adapter.transaction((txn) async {
        await txn.insert('favorites_v8', {
          'profile_id': 'default',
          'playlist_id': 'concurrent-playlist',
          'item_key': alphaKey,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        });
        await txn.insert('playback_progress_v8', {
          'profile_id': 'default',
          'playlist_id': 'concurrent-playlist',
          'item_key': alphaKey,
          'position_ms': 1200,
          'duration_ms': 5000,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        });
      });
      writeStopwatch.stop();
      responseGate.complete();
      await loading;

      expect(writeStopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(await db.query('favorites_v8'), hasLength(1));
      expect(await db.query('playback_progress_v8'), hasLength(1));
      expect(
        (await db.query(
          'items',
          where: 'item_key = ?',
          whereArgs: [alphaKey],
        )).single['title'],
        'Alpha HD',
      );
      expect(
        await db.query(
          'items',
          where: 'playlist_id = ?',
          whereArgs: ['concurrent-playlist'],
        ),
        hasLength(1100),
      );
    },
  );

  test(
    'SQL failure during warm reconciliation preserves catalog and FTS',
    () async {
      final importer = CatalogImporter(databaseAdapter: adapter);
      await _importText(importer, 'reconcile-failure', _playlist);
      await _drainCatalogSearchIndex(adapter, 'reconcile-failure');
      final db = await adapter.database;
      await db.execute('''
CREATE TRIGGER fail_warm_update
BEFORE UPDATE OF title ON items WHEN OLD.playlist_id = 'reconcile-failure'
BEGIN SELECT RAISE(ABORT, 'injected reconcile failure'); END
''');

      final changed = _playlist.replaceFirst('Alpha News', 'Alpha Changed');
      await expectLater(
        _importText(importer, 'reconcile-failure', changed),
        throwsA(isA<Exception>()),
      );

      final alpha = await db.query(
        'items',
        where: 'playlist_id = ? AND stream_url = ?',
        whereArgs: ['reconcile-failure', 'https://stream.test/alpha.m3u8'],
      );
      expect(alpha.single['title'], 'Alpha News');
      expect(
        await db.rawQuery(
          "SELECT rowid FROM items_fts WHERE items_fts MATCH 'Alpha'",
        ),
        hasLength(1),
      );
      expect(await db.query('import_rows'), isEmpty);
      expect(await db.query('import_seen'), isEmpty);
      final latest = await db.query(
        'import_sessions',
        where: 'playlist_id = ?',
        whereArgs: ['reconcile-failure'],
        orderBy: 'id DESC',
        limit: 1,
      );
      expect(latest.single['state'], 'failed');
    },
  );

  test('cancel during warm download preserves the previous catalog', () async {
    final coordinator = CatalogImportCoordinator();
    final importer = CatalogImporter(
      databaseAdapter: adapter,
      coordinator: coordinator,
    );
    await _importText(importer, 'cancel-warm', _playlist);
    final db = await adapter.database;
    final before = await db.query(
      'items',
      where: 'playlist_id = ?',
      whereArgs: ['cancel-warm'],
      orderBy: 'ord',
    );
    final headersFlushed = Completer<void>();
    final releaseResponse = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.text;
      request.response.contentLength = utf8.encode(_playlist).length;
      await request.response.flush();
      headersFlushed.complete();
      await releaseResponse.future;
      request.response.write(_playlist);
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));

    final loading = importer.importPlaylist(
      playlistId: 'cancel-warm',
      playlistUrl: 'http://127.0.0.1:${server.port}/stalled.m3u',
    );
    await headersFlushed.future;
    await coordinator.cancel('cancel-warm');
    await expectLater(loading, throwsA(isA<Exception>()));
    releaseResponse.complete();

    final after = await db.query(
      'items',
      where: 'playlist_id = ?',
      whereArgs: ['cancel-warm'],
      orderBy: 'ord',
    );
    expect(
      after.map((row) => row['item_key']),
      before.map((row) => row['item_key']),
    );
    expect(after.map((row) => row['title']), before.map((row) => row['title']));
    final latest = await db.query(
      'import_sessions',
      where: 'playlist_id = ?',
      whereArgs: ['cancel-warm'],
      orderBy: 'id DESC',
      limit: 1,
    );
    expect(latest.single['state'], 'cancelled');
    expect(await db.query('import_rows'), isEmpty);
    expect(await db.query('import_seen'), isEmpty);
  });
}

Future<CatalogImportResult> _importText(
  CatalogImporter importer,
  String playlistId,
  String content,
) async {
  final server = await _serve(content);
  try {
    return await importer.importPlaylist(
      playlistId: playlistId,
      playlistUrl: 'http://127.0.0.1:${server.port}/playlist.m3u',
    );
  } finally {
    await server.close(force: true);
  }
}

Future<int> _drainCatalogSearchIndex(
  SqfliteDatabaseAdapter adapter,
  String playlistId,
) => SqliteCatalogRepository(
  databaseAdapter: adapter,
  autoStartSearchIndexWorker: false,
).processCatalogSearchIndexQueue(playlistId: playlistId);

Future<HttpServer> _serve(String playlist) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final bytes = utf8.encode(playlist);
  server.listen((request) async {
    request.response.headers.contentType = ContentType.text;
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  });
  return server;
}
