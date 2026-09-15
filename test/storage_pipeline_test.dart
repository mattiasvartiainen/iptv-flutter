import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:iptv_flutter/services/errors/app_issue.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/id_identity.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';
import 'package:iptv_flutter/services/storage/storage_bootstrap.dart';
import 'package:iptv_flutter/services/storage/storage_contracts.dart';
import 'package:iptv_flutter/services/storage/storage_migrations.dart';
import 'package:iptv_flutter/state/app_controller.dart';

void main() {
  test(
    'a cold import and a refresh both reconcile via the set-based SQL path',
    () async {
      final adapter = SqfliteDatabaseAdapter(
        fileName:
            'iptv_test_set_based_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);
      addTearDown(
        () => SqliteCatalogRepository.onStagingReconcileFallback = null,
      );

      final fallbacks = <Object>[];
      SqliteCatalogRepository.onStagingReconcileFallback = fallbacks.add;

      final catalog = SqliteCatalogRepository(
        source: const FakePlaylistSource('''#EXTM3U
#EXTINF:-1 tvg-id="alpha" group-title="News",Alpha News
https://stream.test/alpha.m3u8
#EXTINF:-1 group-title="Series",Beta Show S01E02
https://stream.test/beta-s01e02.m3u8
'''),
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
        autoStartSearchIndexWorker: false,
      );

      await catalog.load(playlistUrl: 'https://provider.test/playlist.m3u');
      await catalog.load(
        playlistUrl: 'https://provider.test/playlist.m3u',
        policy: CatalogLoadPolicy.networkOnly,
      );

      // The Dart-loop fallback is correct but orders of magnitude slower, so
      // silently degrading to it is a performance regression, not a detail.
      expect(fallbacks, isEmpty);
    },
  );

  test('contracts and migrations initialize schema v1 tables', () async {
    final adapter = SqfliteDatabaseAdapter(
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
    expect(rows.first['value'], '7');

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
    expect(tableNames, contains('import_staging_items'));
    expect(tableNames, contains('search_index_queue'));

    final indexes = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );
    final indexNames = indexes.map((row) => row['name']).toSet();
    expect(indexNames, contains('idx_media_playlist_group_sort'));
    expect(indexNames, contains('idx_media_playlist_type_sort'));

    final settings = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['show_continue_watching'],
      limit: 1,
    );
    expect(settings, hasLength(1));
  });

  test('an already-open database applies newly added migrations', () async {
    final migrations = <StorageMigration>[
      const InitialSchemaV1Migration(),
      const PlaylistImportMetricsV2Migration(),
      const PlaylistScopedIdentityV3Migration(),
    ];
    final adapter = SqfliteDatabaseAdapter(
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
  });

  test('storage bootstrap shares a single adapter instance', () {
    final bootstrap = AppStorageBootstrap.instance;
    final repoA = bootstrap.catalogRepository;
    final repoB = bootstrap.settingsRepository;

    expect(repoA, isNotNull);
    expect(repoB, isNotNull);
    expect(identical(bootstrap.adapter, bootstrap.adapter), isTrue);
  });

  test('settings repository persists app and playlist settings', () async {
    final adapter = SqfliteDatabaseAdapter(
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
    final adapter = SqfliteDatabaseAdapter(
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

    await repo.deletePlaylist(urlPlaylist.playlistId);
    expect(await repo.listPlaylists(), hasLength(1));
    final secureKey = storedRows.first['secure_storage_key'] as String;
    expect(await store.read(key: secureKey), isNull);
  });

  test('saved playlist ID owns its imported catalog', () async {
    final adapter = SqfliteDatabaseAdapter(
      fileName:
          'iptv_test_selected_playlist_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final store = InMemoryPlaylistSecretStore();
    final settings = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: store,
    );
    final playlist = await settings.upsertPlaylist(
      const PlaylistSourceConfig.url(
        name: 'Second playlist',
        url: 'https://provider.test/second.m3u',
      ),
    );
    final catalog = SqliteCatalogRepository(
      source: const FakePlaylistSource('''#EXTM3U
#EXTINF:-1 group-title="News",Second Channel
https://stream.test/second.m3u8
'''),
      databaseAdapter: adapter,
      secretStore: store,
    );

    final loaded = await catalog.load(
      playlistUrl: playlist.resolvedUrl,
      playlistId: playlist.playlistId,
      playlistName: playlist.name,
      policy: CatalogLoadPolicy.networkOnly,
    );

    expect(loaded.itemCount, 1);
    final db = await adapter.database;
    final playlists = await db.query('playlists');
    expect(playlists, hasLength(1));
    expect(playlists.single['id'], playlist.playlistId);
    expect(playlists.single['name'], 'Second playlist');
    final media = await db.query('media_items');
    expect(media.single['playlist_id'], playlist.playlistId);
  });

  test('cache-only selection does not fetch an unimported playlist', () async {
    final adapter = SqfliteDatabaseAdapter(
      fileName:
          'iptv_test_cache_only_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final source = _SwitchingSource(first: '', second: '');
    final catalog = SqliteCatalogRepository(
      source: source,
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
    );

    final result = await catalog.load(
      playlistUrl: 'https://provider.test/unimported.m3u',
      playlistId: 'saved-playlist-id',
      playlistName: 'Unimported playlist',
      policy: CatalogLoadPolicy.cacheOnly,
    );

    expect(result.itemCount, 0);
    expect(source.callCount, 0);
  });

  test(
    'refreshing and selecting a second playlist shows its cached catalog',
    () async {
      final adapter = SqfliteDatabaseAdapter(
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
        const PlaylistSourceConfig.url(
          name: 'First playlist',
          url: 'https://provider.test/first.m3u',
        ),
      );
      final second = await settings.upsertPlaylist(
        const PlaylistSourceConfig.url(
          name: 'Second playlist',
          url: 'https://provider.test/second.m3u',
        ),
      );
      final catalog = SqliteCatalogRepository(
        source: _UrlSource({
          first.resolvedUrl: '''#EXTM3U
#EXTINF:-1 group-title="News",First Channel
https://stream.test/first.m3u8
''',
          second.resolvedUrl: '''#EXTM3U
#EXTINF:-1 group-title="Movies",Second Movie
https://stream.test/second.m3u8
''',
        }),
        databaseAdapter: adapter,
        secretStore: store,
      );
      final controller = AppController(
        catalogRepository: catalog,
        settingsRepository: settings,
      );
      addTearDown(controller.dispose);

      controller.activePlaylistId = first.playlistId;
      await controller.loadPlaylist(
        first.playlistId,
        policy: CatalogLoadPolicy.networkOnly,
      );

      expect(await controller.refreshPlaylist(second.playlistId), isTrue);
      expect(controller.activePlaylistId, first.playlistId);

      expect(await controller.selectPlaylist(second.playlistId), isTrue);
      expect(controller.activePlaylistId, second.playlistId);
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
      final adapter = SqfliteDatabaseAdapter(
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
        const PlaylistSourceConfig.url(
          name: 'Sweden',
          url: 'https://provider.test/sweden.m3u',
        ),
      );
      final controller = AppController(
        catalogRepository: SqliteCatalogRepository(
          source: const FakePlaylistSource(playlistText),
          databaseAdapter: adapter,
          secretStore: store,
        ),
        settingsRepository: settings,
      );
      addTearDown(controller.dispose);

      expect(await controller.refreshPlaylist(playlist.playlistId), isTrue);
      expect(await controller.selectPlaylist(playlist.playlistId), isTrue);

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
    const source = FakePlaylistSource('''#EXTM3U
#EXTINF:-1 group-title="TV (Nordicsubs) (Serie)",Pine Gap S01 E05
https://stream.test/pine-gap-s01e05.m3u8
#EXTINF:-1 group-title="TV (Nordicsubs) (Serie)",Pine Gap S01 E06
https://stream.test/pine-gap-s01e06.m3u8
#EXTINF:-1 group-title="Movies",The Last Signal
https://stream.test/the-last-signal.m3u8
''');

    final adapter = SqfliteDatabaseAdapter(
      fileName:
          'iptv_test_import_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final store = InMemoryPlaylistSecretStore();

    final repo = SqliteCatalogRepository(
      source: source,
      databaseAdapter: adapter,
      secretStore: store,
    );

    final loaded = await repo.load(
      playlistUrl: 'https://provider.test/playlist.m3u',
    );

    expect(loaded.itemCount, 3);

    final db = await adapter.database;
    final series = await db.query('series');
    final seasons = await db.query('seasons');
    final episodes = await db.query('episodes');
    final playlists = await db.query('playlists');

    expect(series, hasLength(1));
    expect(seasons, hasLength(1));
    expect(episodes, hasLength(2));

    final episodeMediaRows = await db.query(
      'media_items',
      where: 'content_type = ?',
      whereArgs: ['episode'],
    );
    expect(episodeMediaRows, hasLength(2));

    final secureKey = playlists.first['secure_storage_key'] as String;
    expect(secureKey, startsWith('playlist:'));
    expect(
      await store.read(key: secureKey),
      'https://provider.test/playlist.m3u',
    );
    expect(playlists.first['last_import_status'], 'success');
    expect(playlists.first['last_import_staged_rows'], 3);
    expect(playlists.first['last_import_staged_duration_ms'], isA<int>());
  });

  test('isolates secure storage and media IDs between playlists', () async {
    const content = '''#EXTM3U
#EXTINF:-1 group-title="News",Shared Channel
https://stream.test/shared.m3u8
''';
    final adapter = SqfliteDatabaseAdapter(
      fileName:
          'iptv_test_multiple_playlists_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final store = InMemoryPlaylistSecretStore();
    final repo = SqliteCatalogRepository(
      source: const FakePlaylistSource(content),
      databaseAdapter: adapter,
      secretStore: store,
    );

    final first = await repo.load(
      playlistUrl: 'https://provider-a.test/playlist.m3u',
    );
    final second = await repo.load(
      playlistUrl: 'https://provider-b.test/playlist.m3u',
    );

    expect(first.itemCount, 1);
    expect(second.itemCount, 1);
    final db = await adapter.database;
    final playlists = await db.query('playlists', orderBy: 'id ASC');
    final media = await db.query('media_items', orderBy: 'id ASC');
    expect(playlists, hasLength(2));
    final firstKey = playlists[0]['secure_storage_key'] as String;
    final secondKey = playlists[1]['secure_storage_key'] as String;
    expect(firstKey, startsWith('playlist:'));
    expect(secondKey, startsWith('playlist:'));
    expect(firstKey, isNot(secondKey));
    expect(await store.read(key: firstKey), isNotNull);
    expect(await store.read(key: secondKey), isNotNull);
    expect(media, hasLength(2));
    expect(media[0]['playlist_id'], isNot(media[1]['playlist_id']));
  });

  test(
    'preserves legacy cached media IDs when refreshed with strong IDs',
    () async {
      final adapter = SqfliteDatabaseAdapter(
        fileName:
            'iptv_test_legacy_identity_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);

      final playlistUrl = 'https://provider.test/playlist.m3u';
      final playlistId = legacyStableId('id', 'playlist|$playlistUrl');
      final nowIso = DateTime.now().toUtc().toIso8601String();
      final db = await adapter.database;

      await db.insert('playlists', {
        'id': playlistId,
        'name': 'Primary Playlist',
        'secure_storage_key': 'playlist:$playlistId',
        'source_url_redacted': 'https://provider.test/playlist.m3u',
        'enabled': 1,
        'created_at': nowIso,
        'updated_at': nowIso,
        'last_import_status': 'success',
      });

      final legacyItemId = legacyStableId(
        'item',
        '$playlistUrl|https://stream.test/channel-a.m3u8|Channel A|0',
      );
      final categoryId = legacyStableId('id', 'category|$playlistId|News');

      await db.insert('categories', {
        'id': categoryId,
        'playlist_id': playlistId,
        'provider_group_title': 'News',
        'normalized_name': 'news',
        'content_kind': 'unknown',
        'country_code': null,
        'language_code': null,
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      await db.insert('media_items', {
        'id': legacyItemId,
        'playlist_id': playlistId,
        'content_type': 'live',
        'title': 'Channel A',
        'sort_title': 'channel a',
        'description': '',
        'artwork_url': null,
        'logo_url': null,
        'stream_url': 'https://stream.test/channel-a.m3u8',
        'category_id': categoryId,
        'group_title': 'News',
        'tvg_id': null,
        'tvg_name': null,
        'tvg_chno': null,
        'source_index': 0,
        'provider_item_hash': null,
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      await db.insert('profiles', {
        'id': 'profile-1',
        'name': 'Default',
        'is_default': 1,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      await db.insert('favorites', {
        'profile_id': 'profile-1',
        'media_item_id': legacyItemId,
        'created_at': nowIso,
      });

      final repo = SqliteCatalogRepository(
        source: const FakePlaylistSource('''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
'''),
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
      );

      final loaded = await repo.load(
        playlistUrl: playlistUrl,
        policy: CatalogLoadPolicy.networkOnly,
      );
      expect(loaded.itemCount, 1);

      final refreshedRows = await db.query('media_items');
      expect(refreshedRows, hasLength(1));
      expect(refreshedRows.single['id'], legacyItemId);

      final favorites = await db.query('favorites');
      expect(favorites, hasLength(1));
      expect(favorites.single['media_item_id'], legacyItemId);
    },
  );

  test('settings values drive home section visibility in controller', () async {
    final controller = AppController(
      catalogRepository: const FixtureCatalogRepository(),
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

  test('staging import keeps existing content when refresh fails', () async {
    final source = _SwitchingSource(
      first: '''#EXTM3U
#EXTINF:-1 group-title="TV (Nordicsubs) (Serie)",Pine Gap S01 E05
https://stream.test/pine-gap-s01e05.m3u8
''',
      second: '',
    );

    final adapter = SqfliteDatabaseAdapter(
      fileName:
          'iptv_test_staging_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);

    final repo = SqliteCatalogRepository(
      source: source,
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
      useStagingImport: true,
    );

    await repo.load(playlistUrl: 'https://provider.test/playlist.m3u');

    final db = await adapter.database;
    final beforeRows = await db.query('media_items');
    expect(beforeRows, hasLength(1));

    await expectLater(
      () => repo.load(
        playlistUrl: 'https://provider.test/playlist.m3u',
        policy: CatalogLoadPolicy.networkOnly,
      ),
      throwsA(isA<AppIssueException>()),
    );

    final afterRows = await db.query('media_items');
    expect(afterRows, hasLength(1));
    expect(
      afterRows.first['stream_url'],
      'https://stream.test/pine-gap-s01e05.m3u8',
    );

    final loaded = await repo.load(
      playlistUrl: 'https://provider.test/playlist.m3u',
    );
    expect(loaded.itemCount, 1);
  });

  test('cache-first skips network refresh while cache is still fresh', () async {
    final source = _SwitchingSource(
      first: '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
''',
      second: '',
    );

    final adapter = SqfliteDatabaseAdapter(
      fileName:
          'iptv_test_cache_first_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);

    final repo = SqliteCatalogRepository(
      source: source,
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
    );

    final firstLoad = await repo.load(
      playlistUrl: 'https://provider.test/playlist.m3u',
    );
    expect(firstLoad.itemCount, 1);
    expect(source.callCount, 1);

    // next_refresh_at is set after a successful import, so this should use
    // cached rows and avoid a second network call.
    final secondLoad = await repo.load(
      playlistUrl: 'https://provider.test/playlist.m3u',
    );
    expect(secondLoad.itemCount, 1);
    expect(source.callCount, 1);
  });

  test(
    'refreshing a playlist preserves favorites/history/progress for items that remain',
    () async {
      final source = _SwitchingSource(
        first: '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
#EXTINF:-1 group-title="Sports",Channel B
https://stream.test/channel-b.m3u8
''',
        second: '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
#EXTINF:-1 group-title="News",Channel C
https://stream.test/channel-c.m3u8
''',
      );

      final adapter = SqfliteDatabaseAdapter(
        fileName:
            'iptv_test_refresh_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);

      final repo = SqliteCatalogRepository(
        source: source,
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
      );

      final firstLoad = await repo.load(
        playlistUrl: 'https://provider.test/playlist.m3u',
      );
      expect(firstLoad.itemCount, 2);

      final db = await adapter.database;
      final categories = await db.query('categories');
      final newsCategoryId =
          categories.firstWhere(
                (row) => row['provider_group_title'] == 'News',
              )['id']
              as String;
      final sportsCategoryId =
          categories.firstWhere(
                (row) => row['provider_group_title'] == 'Sports',
              )['id']
              as String;
      final firstMediaRows = await db.query('media_items');
      final channelAId =
          firstMediaRows.firstWhere((row) => row['title'] == 'Channel A')['id']
              as String;
      final channelBId =
          firstMediaRows.firstWhere((row) => row['title'] == 'Channel B')['id']
              as String;
      final playlistId = (await db.query('playlists')).first['id'] as String;
      final nowIso = DateTime.now().toUtc().toIso8601String();

      await db.insert('profiles', {
        'id': 'profile-1',
        'name': 'Default',
        'is_default': 1,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      await db.insert('favorites', {
        'profile_id': 'profile-1',
        'media_item_id': channelAId,
        'created_at': nowIso,
      });
      await db.insert('playback_progress', {
        'profile_id': 'profile-1',
        'media_item_id': channelAId,
        'position_ms': 1234,
        'duration_ms': 5000,
        'updated_at': nowIso,
      });
      await db.insert('watch_history', {
        'id': 'history-1',
        'profile_id': 'profile-1',
        'media_item_id': channelBId,
        'watched_at': nowIso,
        'completed': 0,
        'created_at': nowIso,
      });
      await db.insert('hidden_categories', {
        'playlist_id': playlistId,
        'category_id': newsCategoryId,
        'profile_id': null,
        'created_at': nowIso,
      });

      final secondLoad = await repo.load(
        playlistUrl: 'https://provider.test/playlist.m3u',
        policy: CatalogLoadPolicy.networkOnly,
      );
      expect(secondLoad.itemCount, 2);
      final refreshedTitles = (await db.query(
        'media_items',
      )).map((row) => row['title']).toList();
      expect(refreshedTitles, containsAll(['Channel A', 'Channel C']));

      // Channel A still exists, so its media_item id must be unchanged and
      // its favorite/progress must survive the refresh.
      final favorites = await db.query('favorites');
      expect(favorites, hasLength(1));
      expect(favorites.first['media_item_id'], channelAId);

      final progress = await db.query('playback_progress');
      expect(progress, hasLength(1));
      expect(progress.first['media_item_id'], channelAId);
      expect(progress.first['position_ms'], 1234);

      // Channel B was removed from the playlist, so its history row is
      // correctly gone (the item itself no longer exists).
      final history = await db.query('watch_history');
      expect(history, isEmpty);

      // The "News" category still exists (Channel A + C), so the hidden
      // category preference should survive. "Sports" is gone since no item
      // references it anymore.
      final hidden = await db.query('hidden_categories');
      expect(hidden, hasLength(1));
      expect(hidden.first['category_id'], newsCategoryId);

      final remainingCategories = await db.query('categories');
      expect(
        remainingCategories.map((row) => row['id']),
        isNot(contains(sportsCategoryId)),
      );
    },
  );

  test(
    'a zero-numbered episode label imports without creating an episode row',
    () async {
      // Providers sometimes label a title SxxE00. The item must remain in
      // the catalog without being treated as an invalid database episode.
      final source = _SwitchingSource(
        first: '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
''',
        second: '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
#EXTINF:-1 group-title="TV",Broken Show S01E00
https://stream.test/broken-show.m3u8
''',
      );

      final adapter = SqfliteDatabaseAdapter(
        fileName:
            'iptv_test_failed_refresh_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);

      final repo = SqliteCatalogRepository(
        source: source,
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
      );

      final firstLoad = await repo.load(
        playlistUrl: 'https://provider.test/playlist.m3u',
      );
      expect(firstLoad.itemCount, 1);

      final db = await adapter.database;
      final channelAId = (await db.query('media_items')).single['id'] as String;
      final nowIso = DateTime.now().toUtc().toIso8601String();

      await db.insert('profiles', {
        'id': 'profile-1',
        'name': 'Default',
        'is_default': 1,
        'created_at': nowIso,
        'updated_at': nowIso,
      });
      await db.insert('favorites', {
        'profile_id': 'profile-1',
        'media_item_id': channelAId,
        'created_at': nowIso,
      });
      await db.insert('playback_progress', {
        'profile_id': 'profile-1',
        'media_item_id': channelAId,
        'position_ms': 4321,
        'duration_ms': 9000,
        'updated_at': nowIso,
      });

      final refreshed = await repo.load(
        playlistUrl: 'https://provider.test/playlist.m3u',
        policy: CatalogLoadPolicy.networkOnly,
      );
      expect(refreshed.itemCount, 2);

      // The original item keeps its stable identity and user data after the
      // successful refresh.
      final mediaRows = await db.query('media_items');
      expect(mediaRows, hasLength(2));
      expect(
        mediaRows.firstWhere((row) => row['title'] == 'Channel A')['id'],
        channelAId,
      );

      final favorites = await db.query('favorites');
      expect(favorites, hasLength(1));
      expect(favorites.first['media_item_id'], channelAId);

      final progress = await db.query('playback_progress');
      expect(progress, hasLength(1));
      expect(progress.first['position_ms'], 4321);

      final playlists = await db.query('playlists');
      expect(playlists, hasLength(1));
      expect(playlists.first['last_import_status'], 'success');
      expect(playlists.first['last_import_error'], isNull);

      final brokenRows = await db.query(
        'media_items',
        where: 'title = ?',
        whereArgs: ['Broken Show S01E00'],
      );
      expect(brokenRows, hasLength(1));
      expect((await db.query('episodes')), isEmpty);
    },
  );

  test('a database-rejected item does not abort the remaining import', () async {
    final source = _SwitchingSource(
      first: '''#EXTM3U
#EXTINF:-1 group-title="News",Cached Channel
https://stream.test/cached.m3u8
''',
      second: '''#EXTM3U
#EXTINF:-1 group-title="News",Good Channel
https://stream.test/good.m3u8
#EXTINF:-1 group-title="News",Rejected Channel
https://stream.test/rejected.m3u8
''',
    );
    final adapter = SqfliteDatabaseAdapter(
      fileName:
          'iptv_test_partial_import_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final repo = SqliteCatalogRepository(
      source: source,
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
    );
    const playlistUrl = 'https://provider.test/playlist.m3u';

    await repo.load(playlistUrl: playlistUrl);
    final db = await adapter.database;
    await db.execute('''
CREATE TRIGGER reject_playlist_item
BEFORE INSERT ON media_items
WHEN NEW.title = 'Rejected Channel'
BEGIN
  SELECT RAISE(ABORT, 'Rejected test item');
END
''');

    final refreshed = await repo.load(
      playlistUrl: playlistUrl,
      policy: CatalogLoadPolicy.networkOnly,
    );

    expect(refreshed.itemCount, 1);
    final mediaRows = await db.query('media_items', orderBy: 'title ASC');
    expect(mediaRows.map((row) => row['title']), [
      'Cached Channel',
      'Good Channel',
    ]);
    final playlist = (await db.query('playlists')).single;
    expect(playlist['last_import_status'], 'success');
    expect(
      playlist['last_import_error'],
      contains('1 invalid entries skipped'),
    );
  });
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
  Future<void> upsertPlaylistRefreshSettings(
    PlaylistRefreshSettings settings,
  ) async {}
}

class _SwitchingSource implements PlaylistSource {
  _SwitchingSource({required this.first, required this.second});

  final String first;
  final String second;
  int _count = 0;

  int get callCount => _count;

  @override
  Future<String> fetch(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    _count += 1;
    if (_count == 1) return first;
    if (second.isEmpty) {
      throw StateError('Simulated refresh failure');
    }
    return second;
  }
}

class _UrlSource implements PlaylistSource {
  const _UrlSource(this._contentByUrl);

  final Map<String, String> _contentByUrl;

  @override
  Future<String> fetch(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final content = _contentByUrl[url];
    if (content == null) throw StateError('No fixture for $url');
    return content;
  }
}

Future<int> _readUserVersion(DatabaseExecutor db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  return rows.first['user_version'] as int;
}
