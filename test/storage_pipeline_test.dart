import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/services/catalog/catalog_hash.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';
import 'package:iptv_flutter/services/storage/storage_contracts.dart';
import 'package:iptv_flutter/services/storage/storage_migrations.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'support/catalog_http_test_server.dart';
import 'support/database_adapter.dart';

void main() {
  test('contracts and migrations initialize schema v1 tables', () async {
    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_schema_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);

    final db = await adapter.database;
    final rows = await db.query(
      'schema_meta',
      where: 'key = ?',
      whereArgs: ['schema_version'],
      limit: 1,
    );

    expect(rows, hasLength(1));
    expect(rows.first['value'], '11');

    final playlistColumns = await db.rawQuery('PRAGMA table_info(playlists)');
    expect(
      playlistColumns.any((row) => row['name'] == 'last_import_staged_rows'),
      isTrue,
    );
    expect(
      playlistColumns.any(
        (row) => row['name'] == 'last_import_staged_duration_ms',
      ),
      isTrue,
    );
    expect(
      playlistColumns.any((row) => row['name'] == 'search_index_dirty'),
      isTrue,
    );

    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();
    expect(tableNames, isNot(contains('import_staging_items')));
    expect(tableNames, isNot(contains('search_index_queue')));
    expect(tableNames, isNot(contains('categories')));
    expect(tableNames, isNot(contains('series')));
    expect(tableNames, isNot(contains('seasons')));
    expect(tableNames, isNot(contains('episodes')));
    expect(tableNames, isNot(contains('media_items')));
    expect(tableNames, isNot(contains('favorites')));
    expect(tableNames, isNot(contains('playback_progress')));
    expect(tableNames, isNot(contains('watch_history')));
    expect(tableNames, isNot(contains('hidden_categories')));
    expect(tableNames, isNot(contains('media_items_fts')));
    expect(tableNames, contains('import_sessions'));
    expect(tableNames, contains('groups'));
    expect(tableNames, contains('items'));
    expect(tableNames, contains('series_v8'));
    expect(tableNames, contains('import_rows'));
    expect(tableNames, contains('import_seen'));
    expect(tableNames, contains('items_fts'));
    expect(tableNames, contains('favorites_v8'));
    expect(tableNames, contains('playback_progress_v8'));
    expect(tableNames, contains('watch_history_v8'));
    expect(tableNames, contains('hidden_groups_v8'));
    expect(tableNames, contains('items_fts_queue'));

    for (final expectedColumn in const [
      'source_etag',
      'source_last_modified',
      'source_content_hash',
      'source_content_length',
      'last_checked_at',
      'last_changed_at',
    ]) {
      expect(
        playlistColumns.any((row) => row['name'] == expectedColumn),
        isTrue,
        reason: 'playlists.$expectedColumn must be present in schema v8',
      );
    }

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final indexNames = indexes.map((row) => row['name']).toSet();
    expect(indexNames, contains('idx_import_sessions_playlist_started'));
    expect(indexNames, contains('idx_items_group_ord'));
    expect(indexNames, contains('idx_items_group_sort'));
    expect(indexNames, contains('idx_items_series_episode'));
    expect(indexNames, contains('idx_series_v8_group_sort'));
    expect(indexNames, contains('idx_items_fts_queue_priority'));

    for (final table in const [
      'favorites_v8',
      'playback_progress_v8',
      'watch_history_v8',
      'hidden_groups_v8',
    ]) {
      expect(
        await db.rawQuery('PRAGMA foreign_key_list($table)'),
        isEmpty,
        reason: '$table must not cascade with catalog rows',
      );
    }

    final settings = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['show_continue_watching'],
      limit: 1,
    );
    expect(settings, hasLength(1));

    await db.insert('groups', {
      'playlist_id': 'v8-playlist',
      'kind': 1,
      'title': 'News',
      'sort_title': 'news',
      'ord': 0,
    });
    final group = (await db.query('groups')).single;
    await db.insert('items', {
      'playlist_id': 'v8-playlist',
      'item_key': 42,
      'content_hash': 7,
      'ord': 0,
      'kind': 1,
      'group_id': group['id'],
      'title': 'Alpha News',
      'sort_title': 'alpha news',
      'stream_url': 'https://stream.test/alpha.m3u8',
    });
    final item = (await db.query('items')).single;
    await db.rawInsert("INSERT INTO items_fts(rowid, title) VALUES(?, ?)", [
      item['id'],
      item['title'],
    ]);
    expect(
      await db.rawQuery(
        "SELECT rowid FROM items_fts WHERE items_fts MATCH 'Alpha'",
      ),
      hasLength(1),
    );

    await db.insert('favorites_v8', {
      'profile_id': 'default',
      'playlist_id': 'v8-playlist',
      'item_key': 42,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
    await db.delete('groups', where: 'id = ?', whereArgs: [group['id']]);
    expect(await db.query('items'), isEmpty);
    expect(await db.query('favorites_v8'), hasLength(1));
  });

  test('an already-open database applies newly added migrations', () async {
    final migrations = <StorageMigration>[
      const InitialSchemaV1Migration(),
      const PlaylistImportMetricsV2Migration(),
      const PlaylistScopedIdentityV3Migration(),
    ];
    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_live_migration_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      migrations: migrations,
    );
    addTearDown(adapter.close);

    final db = await adapter.database;
    expect(await _readUserVersion(db), 3);
    migrations.add(const MediaItemXuiIdV4Migration());

    await adapter.initialize();

    expect(await _readUserVersion(db), 4);
    final columns = await db.rawQuery('PRAGMA table_info(media_items)');
    expect(columns.any((column) => column['name'] == 'xui_id'), isTrue);

    migrations.add(const PaginatedCatalogV5Migration());
    await adapter.initialize();

    expect(await _readUserVersion(db), 5);
    final staging = await db.rawQuery(
      'PRAGMA table_info(import_staging_items)',
    );
    expect(staging, isNotEmpty);
    final playlistColumns = await db.rawQuery('PRAGMA table_info(playlists)');
    expect(
      playlistColumns.any((column) => column['name'] == 'search_index_dirty'),
      isTrue,
    );

    migrations
      ..add(const ImportStagingSqlReconcileV6Migration())
      ..add(const ImportPerformanceV7Migration())
      ..add(const ImportSessionsV8Migration());
    await adapter.initialize();

    expect(await _readUserVersion(db), 8);
    final sessionTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'import_sessions'",
    );
    expect(sessionTable, hasLength(1));

    migrations.add(const CatalogImportV9Migration());
    await adapter.initialize();

    expect(await _readUserVersion(db), 9);
    final itemTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'items'",
    );
    expect(itemTable, hasLength(1));

    migrations.add(const CatalogSearchV10Migration());
    await adapter.initialize();

    expect(await _readUserVersion(db), 10);
    final queueTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'items_fts_queue'",
    );
    expect(queueTable, hasLength(1));
    final seriesTable = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'series_v8'",
    );
    expect(seriesTable, hasLength(1));

    await db.insert('groups', {
      'playlist_id': 'migration-v11',
      'kind': 1,
      'title': 'News',
      'sort_title': 'news',
      'ord': 0,
    });
    final groupId = (await db.query('groups')).single['id'];
    await db.insert('items', {
      'playlist_id': 'migration-v11',
      'item_key': 501,
      'content_hash': 502,
      'ord': 0,
      'kind': 1,
      'group_id': groupId,
      'title': 'Preserved channel',
      'sort_title': 'preserved channel',
      'stream_url': 'https://stream.test/preserved.m3u8',
    });
    await db.insert('favorites_v8', {
      'profile_id': 'default',
      'playlist_id': 'migration-v11',
      'item_key': 501,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    migrations.add(const DropLegacyCatalogV11Migration());
    await adapter.initialize();

    expect(await _readUserVersion(db), 11);
    final remaining = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final remainingNames = remaining.map((row) => row['name']).toSet();
    expect(
      remainingNames,
      containsAll([
        'groups',
        'items',
        'series_v8',
        'import_sessions',
        'import_rows',
        'import_seen',
        'items_fts',
        'items_fts_queue',
        'favorites_v8',
        'playback_progress_v8',
        'watch_history_v8',
        'hidden_groups_v8',
      ]),
    );
    expect(
      remainingNames,
      isNot(
        containsAll([
          'categories',
          'series',
          'seasons',
          'episodes',
          'media_items',
          'media_items_fts',
          'favorites',
          'playback_progress',
          'watch_history',
          'hidden_categories',
          'import_staging_items',
          'search_index_queue',
        ]),
      ),
    );
    expect((await db.query('items')).single['title'], 'Preserved channel');
    expect(await db.query('favorites_v8'), hasLength(1));
  });

  test('settings repository persists app and playlist settings', () async {
    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_settings_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final repo = SqliteSettingsRepository(databaseAdapter: adapter);
    final db = await adapter.database;
    final nowIso = DateTime.now().toUtc().toIso8601String();
    await db.insert('playlists', {
      'id': 'playlist-a',
      'name': 'Playlist A',
      'secure_storage_key': 'playlist:playlist-a',
      'source_url_redacted': 'https://provider.test/playlist.m3u',
      'enabled': 1,
      'created_at': nowIso,
      'updated_at': nowIso,
      'last_import_status': 'never',
    });

    await repo.setAppSetting('show_recently_watched', 'false');
    final appValue = await repo.getAppSetting('show_recently_watched');
    expect(appValue, 'false');

    final now = DateTime.now().toUtc();
    await repo.upsertPlaylistRefreshSettings(
      PlaylistRefreshSettings(
        playlistId: 'playlist-a',
        refreshEnabled: true,
        refreshMode: RefreshMode.daily,
        refreshIntervalHours: 24,
        nextRefreshAt: now,
      ),
    );

    final loaded = await repo.getPlaylistRefreshSettings('playlist-a');
    expect(loaded, isNotNull);
    expect(loaded!.refreshMode, RefreshMode.daily);
    expect(loaded.refreshIntervalHours, 24);
  });

  test('settings repository stores multiple playlist source types', () async {
    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_playlist_sources_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final store = InMemoryPlaylistSecretStore();
    final repo = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: store,
    );

    final urlPlaylist = await repo.upsertPlaylist(
      const PlaylistSourceConfig.url(
        name: 'News',
        url: 'https://provider.test/news.m3u',
      ),
    );
    final xtreamPlaylist = await repo.upsertPlaylist(
      const PlaylistSourceConfig.xtream(
        name: 'Sports',
        server: 'https://xtream.test',
        username: 'demo',
        password: 'secret',
      ),
    );

    final playlists = await repo.listPlaylists();
    expect(playlists, hasLength(2));
    expect(
      playlists.map((playlist) => playlist.name),
      containsAll(['News', 'Sports']),
    );
    expect(
      playlists
          .firstWhere(
            (playlist) => playlist.playlistId == urlPlaylist.playlistId,
          )
          .sourceKind,
      PlaylistSourceKind.url,
    );
    expect(
      playlists
          .firstWhere(
            (playlist) => playlist.playlistId == xtreamPlaylist.playlistId,
          )
          .sourceKind,
      PlaylistSourceKind.xtream,
    );
    expect(
      await repo.resolvePlaylistUrl(urlPlaylist.playlistId),
      'https://provider.test/news.m3u',
    );
    expect(
      await repo.resolvePlaylistUrl(xtreamPlaylist.playlistId),
      'https://xtream.test/get.php?username=demo&password=secret&type=m3u_plus&output=m3u8',
    );

    final db = await adapter.database;
    final storedRows = await db.query('playlists', orderBy: 'name ASC');
    expect(storedRows, hasLength(2));

    await db.insert('groups', {
      'playlist_id': urlPlaylist.playlistId,
      'kind': 1,
      'title': 'Imported group',
      'sort_title': 'imported group',
      'ord': 0,
    });
    final v9Group = (await db.query('groups')).single;
    await db.insert('items', {
      'playlist_id': urlPlaylist.playlistId,
      'item_key': 901,
      'content_hash': 902,
      'ord': 0,
      'kind': 1,
      'group_id': v9Group['id'],
      'title': 'V9 channel',
      'sort_title': 'v9 channel',
      'stream_url': 'https://stream.test/v9-channel.m3u8',
    });
    final v9Item = (await db.query('items')).single;
    await db.insert('items_fts', {
      'rowid': v9Item['id'],
      'title': 'V9 channel',
    });
    await db.insert('favorites_v8', {
      'profile_id': 'default',
      'playlist_id': urlPlaylist.playlistId,
      'item_key': 901,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    await repo.deletePlaylist(urlPlaylist.playlistId);
    expect(await repo.listPlaylists(), hasLength(1));
    expect(await db.query('items'), isEmpty);
    expect(await db.query('groups'), isEmpty);
    expect(await db.query('favorites_v8'), isEmpty);
    expect(await db.rawQuery('SELECT rowid FROM items_fts'), isEmpty);
    final secureKey = storedRows.first['secure_storage_key'] as String;
    expect(await store.read(key: secureKey), isNull);
  });

  test('saved playlist ID owns its imported catalog', () async {
    final server = await CatalogHttpTestServer.start(
      responses: {
        '/second.m3u': '''#EXTM3U
#EXTINF:-1 group-title="News",Second Channel
https://stream.test/second.m3u8
''',
      },
    );
    addTearDown(server.close);
    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_selected_playlist_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final store = InMemoryPlaylistSecretStore();
    final settings = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: store,
    );
    final savedPlaylist = await settings.upsertPlaylist(
      PlaylistSourceConfig.url(
        name: 'Second playlist',
        url: server.url('/second.m3u'),
      ),
    );
    final catalog = SqliteCatalogRepository(
      databaseAdapter: adapter,
      autoStartSearchIndexWorker: false,
    );

    final loaded = await catalog.load(
      playlistUrl: savedPlaylist.resolvedUrl,
      playlistId: savedPlaylist.playlistId,
      playlistName: savedPlaylist.name,
      policy: CatalogLoadPolicy.networkOnly,
    );

    expect(loaded.itemCount, 1);
    final db = await adapter.database;
    final playlists = await db.query('playlists');
    expect(playlists, hasLength(1));
    expect(playlists.single['id'], savedPlaylist.playlistId);
    expect(playlists.single['name'], 'Second playlist');
    final items = await db.query('items');
    expect(items.single['playlist_id'], savedPlaylist.playlistId);
  });

  test('cache-only selection does not fetch an unimported playlist', () async {
    final server = await CatalogHttpTestServer.start(
      responses: {'/unimported.m3u': '#EXTM3U\n'},
    );
    addTearDown(server.close);
    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_cache_only_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final catalog = SqliteCatalogRepository(
      databaseAdapter: adapter,
      autoStartSearchIndexWorker: false,
    );

    final result = await catalog.load(
      playlistUrl: server.url('/unimported.m3u'),
      playlistId: 'saved-playlist-id',
      playlistName: 'Unimported playlist',
      policy: CatalogLoadPolicy.cacheOnly,
    );

    expect(result.itemCount, 0);
    expect(server.requestCount, 0);
  });

  test(
    'refreshing and selecting a second playlist shows its cached catalog',
    () async {
      final server = await CatalogHttpTestServer.start(
        responses: {
          '/first.m3u': '''#EXTM3U
#EXTINF:-1 group-title="News",First Channel
https://stream.test/first.m3u8
''',
          '/second.m3u': '''#EXTM3U
#EXTINF:-1 group-title="Movies",Second Movie
https://stream.test/second.mp4
''',
        },
      );
      addTearDown(server.close);
      final adapter = createTestDatabaseAdapter(
        fileName:
            'iptv_test_second_playlist_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);
      final store = InMemoryPlaylistSecretStore();
      final settings = SqliteSettingsRepository(
        databaseAdapter: adapter,
        secretStore: store,
      );
      final first = await settings.upsertPlaylist(
        PlaylistSourceConfig.url(
          name: 'First playlist',
          url: server.url('/first.m3u'),
        ),
      );
      final second = await settings.upsertPlaylist(
        PlaylistSourceConfig.url(
          name: 'Second playlist',
          url: server.url('/second.m3u'),
        ),
      );
      final catalog = SqliteCatalogRepository(
        databaseAdapter: adapter,
        autoStartSearchIndexWorker: false,
      );
      final catalogView = CatalogViewState();
      final navigation = NavigationController();
      final preferences = AppPreferencesController(
        settingsRepository: settings,
      );
      final playlistsController = PlaylistsController(
        catalogRepository: catalog,
        settingsRepository: settings,
        catalogView: catalogView,
        navigationController: navigation,
        preferencesController: preferences,
      );
      final controller = AppController(
        catalogView: catalogView,
        navigationController: navigation,
      );
      addTearDown(navigation.dispose);
      addTearDown(catalogView.dispose);
      addTearDown(playlistsController.dispose);
      addTearDown(preferences.dispose);

      playlistsController.activePlaylistId = first.playlistId;
      await playlistsController.loadPlaylist(
        first.playlistId,
        intent: PlaylistLoadIntent.setup,
      );

      expect(
        await playlistsController.refreshPlaylist(second.playlistId),
        isTrue,
      );
      expect(playlistsController.activePlaylistId, first.playlistId);

      expect(
        await playlistsController.selectPlaylist(second.playlistId),
        isTrue,
      );
      expect(playlistsController.activePlaylistId, second.playlistId);
      expect(controller.catalogItemCount, 1);
      expect(controller.catalogView.homeMovies.single.title, 'Second Movie');
    },
  );

  test(
    'refresh imports and selection exposes XUI-style playlist records',
    () async {
      const playlistText = '''#EXTM3U
#EXTINF:-1 xui-id="{XUI_ID}" tvg-id="svt2.se" tvg-name="SVT2 SD SE" tvg-logo="https://github.com/9967pilo724share324/pilo896to9967share324/blob/main/Sweden/svt2.png?raw=true" group-title="Sweden",SVT2 SD SE
http://nxtportal.xyz:8080/DxB63ueRBDyBf9cwi/Qk0RuQ0B5DMBNUbdj/194128
#EXTINF:-1 xui-id="{XUI_ID}" tvg-id="" tvg-name="Star Wars FHD SE [NXT Play SE]" tvg-logo="https://github.com/9967pilo724share324/pilo896to9967share324/blob/main/Sport/Back/piciconportalfull.png?raw=true" group-title="NXT Play - Sweden",Star Wars FHD SE [NXT Play SE]
http://nxtportal.xyz:8080/DxB63ueRBDyBf9cwi/Qk0RuQ0B5DMBNUbdj/118426
#EXTINF:-1 xui-id="{XUI_ID}" tvg-id="" tvg-name="80-talet FHD SE [NXT Play SE]" tvg-logo="https://github.com/9967pilo724share324/pilo896to9967share324/blob/main/Sport/Back/piciconportalfull.png?raw=true" group-title="NXT Play - Sweden",80-talet FHD SE [NXT Play SE]
http://nxtportal.xyz:8080/DxB63ueRBDyBf9cwi/Qk0RuQ0B5DMBNUbdj/324255
#EXTINF:-1 xui-id="{XUI_ID}" tvg-id="" tvg-name="90-talet FHD SE [NXT Play SE]" tvg-logo="https://github.com/9967pilo724share324/pilo896to9967share324/blob/main/Sport/Back/piciconportalfull.png?raw=true" group-title="NXT Play - Sweden",90-talet FHD SE [NXT Play SE]
http://nxtportal.xyz:8080/DxB63ueRBDyBf9cwi/Qk0RuQ0B5DMBNUbdj/323813
''';
      final server = await CatalogHttpTestServer.start(
        responses: {'/sweden.m3u': playlistText},
      );
      addTearDown(server.close);
      final adapter = createTestDatabaseAdapter(
        fileName:
            'iptv_test_xui_refresh_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);
      final store = InMemoryPlaylistSecretStore();
      final settings = SqliteSettingsRepository(
        databaseAdapter: adapter,
        secretStore: store,
      );
      final playlist = await settings.upsertPlaylist(
        PlaylistSourceConfig.url(
          name: 'Sweden',
          url: server.url('/sweden.m3u'),
        ),
      );
      final catalogView = CatalogViewState();
      final navigation = NavigationController();
      final preferences = AppPreferencesController(
        settingsRepository: settings,
      );
      final playlistsController = PlaylistsController(
        catalogRepository: SqliteCatalogRepository(
          databaseAdapter: adapter,
          autoStartSearchIndexWorker: false,
        ),
        settingsRepository: settings,
        catalogView: catalogView,
        navigationController: navigation,
        preferencesController: preferences,
      );
      final controller = AppController(
        catalogView: catalogView,
        navigationController: navigation,
      );
      addTearDown(navigation.dispose);
      addTearDown(catalogView.dispose);
      addTearDown(playlistsController.dispose);
      addTearDown(preferences.dispose);

      expect(
        await playlistsController.refreshPlaylist(playlist.playlistId),
        isTrue,
      );
      expect(
        await playlistsController.selectPlaylist(playlist.playlistId),
        isTrue,
      );

      expect(controller.catalogItemCount, 4);
      final live = controller.catalogView.homeLive;
      expect(live, hasLength(4));
      final svt2Summary = live.firstWhere((item) => item.title == 'SVT2 SD SE');
      final svt2 = await controller.catalogView.itemById(svt2Summary.id);
      expect(svt2, isNotNull);
      expect(svt2!.title, 'SVT2 SD SE');
      expect(svt2.group, 'Sweden');
      expect(svt2.streamUrl, endsWith('/194128'));
      expect(svt2.metadata['xui-id'], '{XUI_ID}');
      expect(svt2.metadata['tvg-id'], 'svt2.se');
      expect(svt2.logoUrl, contains('svt2.png?raw=true'));
    },
  );

  test('import-to-db pipeline normalizes series episodes', () async {
    const content = '''#EXTM3U
#EXTINF:-1 group-title="TV (Nordicsubs) (Serie)",Pine Gap S01 E05
https://provider.test/series/user/pass/pine-gap-s01e05.mkv
#EXTINF:-1 group-title="TV (Nordicsubs) (Serie)",Pine Gap S01 E06
https://provider.test/series/user/pass/pine-gap-s01e06.mkv
#EXTINF:-1 group-title="Movies",The Last Signal
https://stream.test/the-last-signal.mp4
''';
    final server = await CatalogHttpTestServer.start(
      responses: {'/playlist.m3u': content},
    );
    addTearDown(server.close);

    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_import_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final store = InMemoryPlaylistSecretStore();
    final settings = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: store,
    );
    final playlist = await settings.upsertPlaylist(
      PlaylistSourceConfig.url(
        name: 'Fixture',
        url: server.url('/playlist.m3u'),
      ),
    );
    final repo = SqliteCatalogRepository(
      databaseAdapter: adapter,
      autoStartSearchIndexWorker: false,
    );

    final loaded = await repo.load(
      playlistId: playlist.playlistId,
      playlistUrl: playlist.resolvedUrl,
      policy: CatalogLoadPolicy.networkOnly,
    );

    expect(loaded.itemCount, 3);
    final series = await repo.querySeries(playlist.playlistId);
    expect(series.total, 1);
    expect(series.items.single.title, 'Pine Gap');
    expect(series.items.single.seasonCount, 1);
    expect(series.items.single.episodeCount, 2);
    final seasons = await repo.seasons(series.items.single.id);
    expect(seasons, hasLength(1));
    expect(seasons.single.seasonNumber, 1);
    final episodes = await repo.episodes(seasons.single.id);
    expect(episodes.items.map((item) => item.title), [
      'Pine Gap S01 E05',
      'Pine Gap S01 E06',
    ]);
    final movie = await repo.queryItems(
      CatalogQuery(
        playlistId: playlist.playlistId,
        kinds: const [CatalogItemKind.movie],
      ),
    );
    expect(movie.items.single.title, 'The Last Signal');
    expect(
      (await settings.getPlaylist(playlist.playlistId))?.sourceConfig?.url,
      server.url('/playlist.m3u'),
    );
  });

  test('isolates catalog identity and favorites between playlists', () async {
    const content = '''#EXTM3U
#EXTINF:-1 group-title="News",Shared Channel
https://stream.test/shared.m3u8
''';
    final server = await CatalogHttpTestServer.start(
      responses: {'/first.m3u': content, '/second.m3u': content},
    );
    addTearDown(server.close);
    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_multiple_playlists_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final store = InMemoryPlaylistSecretStore();
    final settings = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: store,
    );
    final firstPlaylist = await settings.upsertPlaylist(
      PlaylistSourceConfig.url(name: 'First', url: server.url('/first.m3u')),
    );
    final secondPlaylist = await settings.upsertPlaylist(
      PlaylistSourceConfig.url(name: 'Second', url: server.url('/second.m3u')),
    );
    final repo = SqliteCatalogRepository(
      databaseAdapter: adapter,
      autoStartSearchIndexWorker: false,
    );

    final first = await repo.load(
      playlistId: firstPlaylist.playlistId,
      playlistUrl: firstPlaylist.resolvedUrl,
      policy: CatalogLoadPolicy.networkOnly,
    );
    final second = await repo.load(
      playlistId: secondPlaylist.playlistId,
      playlistUrl: secondPlaylist.resolvedUrl,
      policy: CatalogLoadPolicy.networkOnly,
    );

    expect(first.itemCount, 1);
    expect(second.itemCount, 1);
    final db = await adapter.database;
    final items = await db.query('items', orderBy: 'id ASC');
    expect(items, hasLength(2));
    expect(items.map((item) => item['playlist_id']).toSet(), {
      firstPlaylist.playlistId,
      secondPlaylist.playlistId,
    });
    expect(items[0]['id'], isNot(items[1]['id']));

    final itemKey = hash64('https://stream.test/shared.m3u8');
    await repo.setV9Favorite(
      playlistId: firstPlaylist.playlistId,
      itemKey: itemKey,
      favorite: true,
    );
    expect(
      (await repo.v9FavoriteItems(playlistId: firstPlaylist.playlistId)),
      hasLength(1),
    );
    expect(
      await repo.v9FavoriteItems(playlistId: secondPlaylist.playlistId),
      isEmpty,
    );

    final firstKey = 'playlist:${firstPlaylist.playlistId}';
    final secondKey = 'playlist:${secondPlaylist.playlistId}';
    expect(firstKey, isNot(secondKey));
    expect(await store.read(key: firstKey), isNotNull);
    expect(await store.read(key: secondKey), isNotNull);
  });

  test('settings values drive home section visibility in controller', () async {
    final controller = AppPreferencesController(
      settingsRepository: _FakeSettingsRepository(
        values: const {
          'show_home_live_tv': 'false',
          'show_home_movies': 'true',
          'show_home_series': 'false',
        },
      ),
    );

    await controller.refreshHomeSectionVisibility();

    expect(controller.showHomeLiveTv, isFalse);
    expect(controller.showHomeMovies, isTrue);
    expect(controller.showHomeSeries, isFalse);
  });

  test('v9 import keeps existing content when refresh fails', () async {
    final server = await CatalogHttpTestServer.start(
      responses: {
        '/playlist.m3u': '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
''',
      },
    );
    addTearDown(server.close);

    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_staging_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final store = InMemoryPlaylistSecretStore();
    final settings = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: store,
    );
    final playlist = await settings.upsertPlaylist(
      PlaylistSourceConfig.url(
        name: 'Fixture',
        url: server.url('/playlist.m3u'),
      ),
    );

    final repo = SqliteCatalogRepository(
      databaseAdapter: adapter,
      autoStartSearchIndexWorker: false,
    );

    await repo.load(
      playlistId: playlist.playlistId,
      playlistUrl: playlist.resolvedUrl,
      policy: CatalogLoadPolicy.networkOnly,
    );
    expect(
      (await repo.queryItems(
        CatalogQuery(
          playlistId: playlist.playlistId,
          kinds: const [CatalogItemKind.live],
        ),
      )).items.single.title,
      'Channel A',
    );

    server.responses['/playlist.m3u'] = '#EXTM3U\n';
    await expectLater(
      repo.load(
        playlistId: playlist.playlistId,
        playlistUrl: playlist.resolvedUrl,
        policy: CatalogLoadPolicy.networkOnly,
      ),
      throwsA(isA<Exception>()),
    );
    expect(server.requestCount, 2);

    expect(
      (await repo.queryItems(
        CatalogQuery(
          playlistId: playlist.playlistId,
          kinds: const [CatalogItemKind.live],
        ),
      )).items.single.title,
      'Channel A',
    );

    final loaded = await repo.load(
      playlistId: playlist.playlistId,
      playlistUrl: playlist.resolvedUrl,
    );
    expect(loaded.itemCount, 1);
    expect(server.requestCount, 2);
  });

  test('cache-first skips network refresh while cache is still fresh', () async {
    const firstContent = '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
''';
    final server = await CatalogHttpTestServer.start(
      responses: {'/playlist.m3u': firstContent},
    );
    addTearDown(server.close);

    final adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_cache_first_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final store = InMemoryPlaylistSecretStore();
    final settings = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: store,
    );
    final playlist = await settings.upsertPlaylist(
      PlaylistSourceConfig.url(
        name: 'Fixture',
        url: server.url('/playlist.m3u'),
      ),
    );

    final repo = SqliteCatalogRepository(
      databaseAdapter: adapter,
      autoStartSearchIndexWorker: false,
    );

    final firstLoad = await repo.load(
      playlistId: playlist.playlistId,
      playlistUrl: playlist.resolvedUrl,
      policy: CatalogLoadPolicy.networkOnly,
    );
    expect(firstLoad.itemCount, 1);
    expect(server.requestCount, 1);
    final firstSchedule = (await settings.getPlaylistRefreshSettings(
      playlist.playlistId,
    ))!;
    expect(firstSchedule.lastRefreshStatus, 'success');
    expect(firstSchedule.nextRefreshAt, isNotNull);
    expect(firstSchedule.nextRefreshAt!.isAfter(DateTime.now()), isTrue);

    final secondLoad = await repo.load(
      playlistId: playlist.playlistId,
      playlistUrl: playlist.resolvedUrl,
    );
    expect(secondLoad.itemCount, 1);
    expect(server.requestCount, 1);
    expect(
      (await repo.queryItems(
        CatalogQuery(
          playlistId: playlist.playlistId,
          kinds: const [CatalogItemKind.live],
        ),
      )).items.single.title,
      'Channel A',
    );

    server.responses['/playlist.m3u'] = firstContent.replaceFirst(
      'Channel A',
      'Channel B',
    );
    await repo.load(
      playlistId: playlist.playlistId,
      playlistUrl: playlist.resolvedUrl,
      policy: CatalogLoadPolicy.networkOnly,
    );
    expect(server.requestCount, 2);
    final successfulSchedule = (await settings.getPlaylistRefreshSettings(
      playlist.playlistId,
    ))!;

    server.responses['/playlist.m3u'] = '#EXTM3U\n';
    await expectLater(
      repo.load(
        playlistId: playlist.playlistId,
        playlistUrl: playlist.resolvedUrl,
        policy: CatalogLoadPolicy.networkOnly,
      ),
      throwsA(isA<Exception>()),
    );
    expect(server.requestCount, 3);
    expect(
      (await repo.queryItems(
        CatalogQuery(
          playlistId: playlist.playlistId,
          kinds: const [CatalogItemKind.live],
        ),
      )).items.single.title,
      'Channel B',
    );
    final scheduleAfterFailure = (await settings.getPlaylistRefreshSettings(
      playlist.playlistId,
    ))!;
    expect(scheduleAfterFailure.lastRefreshStatus, 'success');
    expect(
      scheduleAfterFailure.nextRefreshAt,
      successfulSchedule.nextRefreshAt,
    );
  });

  test(
    'refreshing a playlist preserves favorites/history/progress for items that remain',
    () async {
      final server = await CatalogHttpTestServer.start(
        responses: {
          '/playlist.m3u': '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
#EXTINF:-1 group-title="Sports",Channel B
https://stream.test/channel-b.m3u8
''',
        },
      );
      addTearDown(server.close);
      final adapter = createTestDatabaseAdapter(
        fileName:
            'iptv_test_refresh_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);
      final store = InMemoryPlaylistSecretStore();
      final settings = SqliteSettingsRepository(
        databaseAdapter: adapter,
        secretStore: store,
      );
      final playlist = await settings.upsertPlaylist(
        PlaylistSourceConfig.url(
          name: 'Refresh fixture',
          url: server.url('/playlist.m3u'),
        ),
      );
      final repo = SqliteCatalogRepository(
        databaseAdapter: adapter,
        autoStartSearchIndexWorker: false,
      );

      final firstLoad = await repo.load(
        playlistId: playlist.playlistId,
        playlistUrl: playlist.resolvedUrl,
        policy: CatalogLoadPolicy.networkOnly,
      );
      expect(firstLoad.itemCount, 2);
      final initialItems = await repo.queryItems(
        CatalogQuery(playlistId: playlist.playlistId),
      );
      final channelA = initialItems.items.firstWhere(
        (item) => item.title == 'Channel A',
      );
      final channelAKey = hash64('https://stream.test/channel-a.m3u8');
      await repo.setV9Favorite(
        playlistId: playlist.playlistId,
        itemKey: channelAKey,
        favorite: true,
      );
      await repo.saveV9PlaybackProgress(
        playlistId: playlist.playlistId,
        itemKey: channelAKey,
        positionMs: 1234,
        durationMs: 5000,
      );
      await repo.recordV9WatchHistory(
        playlistId: playlist.playlistId,
        itemKey: channelAKey,
        completed: false,
        positionMs: 1234,
        durationMs: 5000,
      );
      await settings.setGroupHidden(
        playlistId: playlist.playlistId,
        kind: CatalogGroupKind.live,
        groupTitle: 'News',
        hidden: true,
      );

      server.responses['/playlist.m3u'] = '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
#EXTINF:-1 group-title="News",Channel C
https://stream.test/channel-c.m3u8
''';

      final secondLoad = await repo.load(
        playlistId: playlist.playlistId,
        playlistUrl: playlist.resolvedUrl,
        policy: CatalogLoadPolicy.networkOnly,
      );
      expect(secondLoad.itemCount, 2);
      expect(
        await repo.queryGroups(
          playlist.playlistId,
          kind: CatalogGroupKind.live,
        ),
        isEmpty,
      );
      await settings.setGroupHidden(
        playlistId: playlist.playlistId,
        kind: CatalogGroupKind.live,
        groupTitle: 'News',
        hidden: false,
      );
      final refreshedItems = await repo.queryItems(
        CatalogQuery(playlistId: playlist.playlistId),
      );
      final refreshedTitles = refreshedItems.items
          .map((item) => item.title)
          .toList();
      expect(refreshedTitles, containsAll(['Channel A', 'Channel C']));
      expect(
        refreshedItems.items.firstWhere((item) => item.title == 'Channel A').id,
        channelA.id,
      );

      final favorites = await repo.v9FavoriteItems(
        playlistId: playlist.playlistId,
      );
      expect(favorites, hasLength(1));
      expect(favorites.single.title, 'Channel A');
      expect(
        (await repo.v9PlaybackProgress(
          playlistId: playlist.playlistId,
          itemKey: channelAKey,
        ))?.positionMs,
        1234,
      );
      expect(
        (await repo.v9RecentlyWatchedItems(
          playlistId: playlist.playlistId,
        )).single.title,
        'Channel A',
      );
    },
  );

  test(
    'a zero-numbered episode label imports without creating an episode row',
    () async {
      const firstContent = '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
  ''';
      const refreshedContent = '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
#EXTINF:-1 group-title="TV",Broken Show S01E00
https://stream.test/broken-show.m3u8
  ''';
      final server = await CatalogHttpTestServer.start(
        responses: {'/playlist.m3u': firstContent},
      );
      addTearDown(server.close);

      final adapter = createTestDatabaseAdapter(
        fileName:
            'iptv_test_failed_refresh_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);
      final store = InMemoryPlaylistSecretStore();
      final settings = SqliteSettingsRepository(
        databaseAdapter: adapter,
        secretStore: store,
      );
      final playlist = await settings.upsertPlaylist(
        PlaylistSourceConfig.url(
          name: 'Episode fixture',
          url: server.url('/playlist.m3u'),
        ),
      );
      final repo = SqliteCatalogRepository(
        databaseAdapter: adapter,
        autoStartSearchIndexWorker: false,
      );

      final firstLoad = await repo.load(
        playlistId: playlist.playlistId,
        playlistUrl: playlist.resolvedUrl,
        policy: CatalogLoadPolicy.networkOnly,
      );
      expect(firstLoad.itemCount, 1);
      final channelAKey = hash64('https://stream.test/channel-a.m3u8');
      final channelA = (await repo.queryItems(
        CatalogQuery(playlistId: playlist.playlistId),
      )).items.single;
      await repo.setV9Favorite(
        playlistId: playlist.playlistId,
        itemKey: channelAKey,
        favorite: true,
      );
      await repo.saveV9PlaybackProgress(
        playlistId: playlist.playlistId,
        itemKey: channelAKey,
        positionMs: 4321,
        durationMs: 9000,
      );

      server.responses['/playlist.m3u'] = refreshedContent;
      final refreshed = await repo.load(
        playlistId: playlist.playlistId,
        playlistUrl: playlist.resolvedUrl,
        policy: CatalogLoadPolicy.networkOnly,
      );
      expect(refreshed.itemCount, 2);

      final mediaRows = await repo.queryItems(
        CatalogQuery(playlistId: playlist.playlistId),
      );
      expect(mediaRows.items, hasLength(2));
      expect(
        mediaRows.items.firstWhere((item) => item.title == 'Channel A').id,
        channelA.id,
      );
      expect(
        mediaRows.items.any((item) => item.title == 'Broken Show S01E00'),
        isTrue,
      );
      expect((await repo.querySeries(playlist.playlistId)).total, 0);

      final favorites = await repo.v9FavoriteItems(
        playlistId: playlist.playlistId,
      );
      expect(favorites, hasLength(1));
      expect(favorites.single.title, 'Channel A');
      expect(
        (await repo.v9PlaybackProgress(
          playlistId: playlist.playlistId,
          itemKey: channelAKey,
        ))?.positionMs,
        4321,
      );
    },
  );
}

class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({required this.values});

  final Map<String, String> values;

  @override
  Future<String?> getAppSetting(String key) async => values[key];

  @override
  Future<List<ManagedPlaylist>> listPlaylists() async => const [];

  @override
  Future<ManagedPlaylist?> getPlaylist(String playlistId) async => null;

  @override
  Future<ManagedPlaylist> upsertPlaylist(PlaylistSourceConfig config) async {
    throw UnimplementedError();
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {}

  @override
  Future<String?> resolvePlaylistUrl(String playlistId) async => null;

  @override
  Future<PlaylistRefreshSettings?> getPlaylistRefreshSettings(
    String playlistId,
  ) async => null;

  @override
  Future<bool> isCategoryHidden({
    required String playlistId,
    required String categoryId,
    String? profileId,
  }) async => false;

  @override
  Future<void> setAppSetting(String key, String value) async {}

  @override
  Future<void> setCategoryHidden({
    required String playlistId,
    required String categoryId,
    required bool hidden,
    String? profileId,
  }) async {}

  @override
  Future<bool> isGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    String? profileId,
  }) async => false;

  @override
  Future<void> setGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    required bool hidden,
    String? profileId,
  }) async {}

  @override
  Future<void> upsertPlaylistRefreshSettings(
    PlaylistRefreshSettings settings,
  ) async {}
}

Future<int> _readUserVersion(DatabaseExecutor db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return rows.first['user_version'] as int;
}
