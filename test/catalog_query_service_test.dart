import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/catalog_search_indexer.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/user_library_repository.dart';
import 'package:iptv_flutter/services/playback/fake_playback.dart';
import 'package:iptv_flutter/services/storage/catalog_sort_v13_migration.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';

import 'support/catalog_fixtures.dart';
import 'support/catalog_http_test_server.dart';
import 'support/catalog_services.dart';
import 'support/database_adapter.dart';

const String _playlistText = '''#EXTM3U
#EXTINF:-1 tvg-id="alpha" tvg-logo="https://img.test/alpha.png" group-title="News",Alpha News
https://stream.test/alpha.m3u8
#EXTINF:-1 group-title="Sports",Beta Sports
https://stream.test/beta.m3u8
#EXTINF:-1 group-title="News",Gamma News
https://stream.test/gamma.m3u8
#EXTINF:-1 group-title="Movies",The Last Signal
https://stream.test/last-signal.mp4
#EXTINF:-1 group-title="Movies",Zebra Crossing
https://stream.test/zebra.mp4
#EXTINF:-1 group-title="Movies",Alpha Movie
https://stream.test/alpha-movie.mp4
#EXTINF:-1 group-title="Series",Pine Gap S01 E01
https://provider.test/series/user/pass/pine-s01e01.mkv
#EXTINF:-1 group-title="Series",Pine Gap S01 E02
https://provider.test/series/user/pass/pine-s01e02.mkv
#EXTINF:-1 group-title="Series",Pine Gap S02 E01
https://provider.test/series/user/pass/pine-s02e01.mkv
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('buildFtsPrefixQuery', () {
    test('quotes every token and appends a prefix wildcard', () {
      expect(buildFtsPrefixQuery('pine gap'), '"pine"* "gap"*');
    });

    test('strips FTS5 operators that would otherwise be parsed as syntax', () {
      expect(
        buildFtsPrefixQuery('pine" OR NEAR(gap'),
        '"pine"* "OR"* "NEAR"* "gap"*',
      );
      expect(buildFtsPrefixQuery('a-b'), '"a"* "b"*');
    });

    test('returns null when nothing searchable remains', () {
      expect(buildFtsPrefixQuery('   '), isNull);
      expect(buildFtsPrefixQuery('***'), isNull);
      expect(buildFtsPrefixQuery('"'), isNull);
    });
  });

  group('InMemoryCatalogQueryService', () {
    late InMemoryCatalogQueryService service;

    setUp(() {
      final items = const M3uParser().parse(_playlistText);
      service = InMemoryCatalogQueryService('p1', items);
    });

    test('classifies live, movie and episode kinds', () async {
      Future<int> countOf(CatalogItemKind kind) async =>
          (await service.queryItems(
            CatalogQuery(playlistId: 'p1', kinds: [kind]),
          )).total;

      expect(await countOf(CatalogItemKind.live), 3);
      expect(await countOf(CatalogItemKind.movie), 3);
      expect(await countOf(CatalogItemKind.episode), 3);
    });

    test('derives series, seasons and episode counts', () async {
      final series = await service.querySeries('p1');
      expect(series.total, 1);
      expect(series.items.single.title, 'Pine Gap');
      expect(series.items.single.seasonCount, 2);
      expect(series.items.single.episodeCount, 3);

      final seasons = await service.seasons(series.items.single.id);
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(seasons.first.episodeCount, 2);

      final episodes = await service.episodes(seasons.first.id);
      expect(episodes.total, 2);
    });

    test('returns an empty page for an unknown playlist', () async {
      final page = await service.queryItems(
        const CatalogQuery(playlistId: 'other'),
      );
      expect(page.isEmpty, isTrue);
      expect(page.total, 0);
    });

    test(
      'supports all-groups default and optional single-group paging',
      () async {
        final all = await service.queryItems(
          const CatalogQuery(playlistId: 'p1', kinds: [CatalogItemKind.live]),
        );
        expect(all.total, 3);

        final groups = await service.queryGroups(
          'p1',
          kind: CatalogGroupKind.live,
        );
        expect(groups.map((group) => group.title), ['News', 'Sports']);
        expect(groups.map((group) => group.itemCount), [2, 1]);

        final selected = await service.itemsInGroup(
          'p1',
          groups.first.id,
          limit: 1,
        );
        expect(selected.total, 2);
        expect(selected.items, hasLength(1));
        expect(selected.items.single.group, 'News');
      },
    );

    test(
      'series source ordering follows its first episode across pages',
      () async {
        final service = InMemoryCatalogQueryService(
          'p1',
          const M3uParser().parse(movieSeriesPlaylistText),
        );
        final first = await service.querySeries(
          'p1',
          sort: CatalogSort.playlistOrder,
          limit: 1,
        );
        final second = await service.querySeries(
          'p1',
          sort: CatalogSort.playlistOrder,
          offset: 1,
          limit: 2,
        );
        expect([...first.items, ...second.items].map((item) => item.title), [
          'Zebra Show',
          'Alpha Show',
          'Middle Show',
        ]);
        final group = (await service.queryGroups(
          'p1',
          kind: CatalogGroupKind.series,
        )).single;
        final grouped = await service.seriesInGroup(
          'p1',
          group.id,
          sort: CatalogSort.playlistOrder,
        );
        expect(grouped.items.map((item) => item.title), [
          'Zebra Show',
          'Alpha Show',
          'Middle Show',
        ]);
      },
    );

    test('series can be filtered to the selected series group', () async {
      final groups = await service.queryGroups(
        'p1',
        kind: CatalogGroupKind.series,
      );
      expect(groups, hasLength(1));
      final series = await service.seriesInGroup('p1', groups.single.id);
      expect(series.total, 1);
      expect(series.items.single.title, 'Pine Gap');
    });
  });

  group('SqliteCatalogQueryService', () {
    late SqfliteDatabaseAdapter adapter;
    late SqliteCatalogQueryService queries;
    late CatalogHttpTestServer server;
    late String playlistId;

    setUp(() async {
      adapter = createTestDatabaseAdapter(
        fileName:
            'iptv_test_query_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);
      server = await CatalogHttpTestServer.start(
        responses: {'/playlist.m3u': _playlistText},
      );
      addTearDown(server.close);

      final searchIndexer = SqliteCatalogSearchIndexer(
        databaseAdapter: adapter,
        autoStartWorker: false,
      );
      queries = SqliteCatalogQueryService(
        databaseAdapter: adapter,
        searchIndexer: searchIndexer,
      );
      playlistId = 'query-v9-playlist';
      await createCatalogSyncService(
        adapter,
        searchIndexer: searchIndexer,
      ).load(
        playlistId: playlistId,
        playlistUrl: server.url('/playlist.m3u'),
        policy: CatalogLoadPolicy.networkOnly,
      );
      await searchIndexer.processQueue(playlistId: playlistId);
    });

    test(
      'favourite pages use persisted items, kind, profile and hidden groups',
      () async {
        final db = await adapter.database;
        final rows = await db.query(
          'items',
          columns: ['item_key', 'title'],
          where: 'playlist_id = ?',
          whereArgs: [playlistId],
        );
        final keys = {
          for (final row in rows)
            row['title'] as String: row['item_key'] as int,
        };
        final library = SqliteUserLibraryRepository(databaseAdapter: adapter);
        for (final title in [
          'Alpha News',
          'Beta Sports',
          'Zebra Crossing',
          'Pine Gap S01 E01',
          'Pine Gap S01 E02',
        ]) {
          await library.setFavorite(
            playlistId: playlistId,
            itemKey: keys[title]!,
            favorite: true,
          );
        }
        await library.setFavorite(
          playlistId: playlistId,
          itemKey: keys['Gamma News']!,
          favorite: true,
          profileId: 'other',
        );
        final first = await queries.favoriteItemsPage(
          playlistId,
          kind: CatalogItemKind.live,
          limit: 1,
          sort: CatalogSort.playlistOrder,
        );
        final next = await queries.favoriteItemsPage(
          playlistId,
          kind: CatalogItemKind.live,
          limit: 1,
          offset: first.nextOffset,
          sort: CatalogSort.playlistOrder,
        );
        expect(first.total, 2);
        expect([...first.items, ...next.items].map((e) => e.title), [
          'Alpha News',
          'Beta Sports',
        ]);
        expect(
          (await queries.favoriteItemsPage(
            playlistId,
            kind: CatalogItemKind.movie,
          )).items.single.title,
          'Zebra Crossing',
        );
        expect(
          (await queries.favoriteSeriesPage(playlistId)).items.single.title,
          'Pine Gap',
        );
        expect((await queries.favoriteSeriesPage(playlistId)).total, 1);
        expect(
          (await queries.favoriteItemsPage(
            'other',
            kind: CatalogItemKind.live,
          )).total,
          0,
        );

        await db.insert('hidden_groups_v8', {
          'playlist_id': playlistId,
          'kind': 1,
          'group_title': 'News',
          'profile_id': 'default',
        });
        expect(
          (await queries.favoriteItemsPage(
            playlistId,
            kind: CatalogItemKind.live,
          )).items.single.title,
          'Beta Sports',
        );
        await library.setFavorite(
          playlistId: playlistId,
          itemKey: keys['Pine Gap S01 E01']!,
          favorite: false,
        );
        expect((await queries.favoriteSeriesPage(playlistId)).total, 1);
        await library.setFavorite(
          playlistId: playlistId,
          itemKey: keys['Pine Gap S01 E02']!,
          favorite: false,
        );
        expect((await queries.favoriteSeriesPage(playlistId)).total, 0);
      },
    );

    test(
      'player favourite removal refreshes the selected SQLite page',
      () async {
        final library = SqliteUserLibraryRepository(databaseAdapter: adapter);
        final db = await adapter.database;
        final row = (await db.query(
          'items',
          columns: ['item_key'],
          where: 'playlist_id = ? AND title = ?',
          whereArgs: [playlistId, 'Alpha News'],
        )).single;
        await library.setFavorite(
          playlistId: playlistId,
          itemKey: row['item_key'] as int,
          favorite: true,
        );
        final view = CatalogViewState();
        final navigation = NavigationController();
        final player = PlayerController(
          playbackAdapter: FakePlaybackAdapter(transitionDelay: Duration.zero),
          navigationController: navigation,
          favorites: library,
          onFavoriteChanged: view.favoriteChanged,
        );
        addTearDown(() {
          player.dispose();
          navigation.dispose();
          view.dispose();
        });
        await view.bind(service: queries, playlistId: playlistId);
        await view.showItems(CatalogItemKind.live, selectFirstGroup: true);
        await view.selectFavorites();
        final item = await queries.itemById(view.items.items.single.id);
        await player.openPlayer(item!);
        if (player.favoriteBusy) {
          final loaded = Completer<void>();
          void onLoaded() {
            if (!player.favoriteBusy && !loaded.isCompleted) loaded.complete();
          }

          player.addListener(onLoaded);
          await loaded.future.timeout(const Duration(seconds: 5));
          player.removeListener(onLoaded);
        }
        expect(player.favorite, isTrue);
        final refreshed = Completer<void>();
        void listener() {
          if (!view.items.isLoading &&
              view.items.total == 0 &&
              !refreshed.isCompleted) {
            refreshed.complete();
          }
        }

        view.items.addListener(listener);
        await player.toggleFavorite();
        await refreshed.future.timeout(const Duration(seconds: 5));
        view.items.removeListener(listener);
        expect(view.favoriteGroupSelected, isTrue);
        expect(view.items.items, isEmpty);
        expect(
          await library.isFavorite(
            playlistId: playlistId,
            itemKey: row['item_key'] as int,
          ),
          isFalse,
        );
      },
    );

    test('favourite results page across many items and distinct series', () async {
      const id = 'favourite-pages';
      server.responses['/favorite-pages.m3u'] =
          '#EXTM3U\n${List.generate(125, (i) => '#EXTINF:-1 group-title="Movies",Movie ${i.toString().padLeft(3, '0')}\nhttps://example.invalid/movie/$i.mp4\n').join()}'
          '${List.generate(3, (show) => List.generate(2, (episode) => '#EXTINF:-1 group-title="Series",Show $show S01 E0${episode + 1}\nhttps://example.invalid/series/$show/$episode.mkv\n').join()).join()}';
      await createCatalogSyncService(
        adapter,
        searchIndexer: SqliteCatalogSearchIndexer(
          databaseAdapter: adapter,
          autoStartWorker: false,
        ),
      ).load(
        playlistId: id,
        playlistUrl: server.url('/favorite-pages.m3u'),
        policy: CatalogLoadPolicy.networkOnly,
      );
      final db = await adapter.database;
      await db.rawInsert(
        "INSERT INTO favorites_v8(profile_id, playlist_id, item_key, created_at) "
        "SELECT 'default', playlist_id, item_key, 0 FROM items WHERE playlist_id = ?",
        [id],
      );
      final titles = <String>[];
      var offset = 0;
      while (true) {
        final page = await queries.favoriteItemsPage(
          id,
          kind: CatalogItemKind.movie,
          offset: offset,
          limit: 23,
          sort: CatalogSort.playlistOrder,
        );
        expect(page.total, 125);
        titles.addAll(page.items.map((item) => item.title));
        if (!page.hasMore) break;
        offset = page.nextOffset;
      }
      expect(titles, [
        for (var i = 0; i < 125; i++) 'Movie ${i.toString().padLeft(3, '0')}',
      ]);
      final first = await queries.favoriteSeriesPage(id, limit: 2);
      final second = await queries.favoriteSeriesPage(
        id,
        offset: first.nextOffset,
        limit: 2,
      );
      expect(first.total, 3);
      expect([...first.items, ...second.items].map((s) => s.title), [
        'Show 0',
        'Show 1',
        'Show 2',
      ]);
    });

    test(
      'automatic filtering keeps SQLite paging totals and offsets correct',
      () async {
        const id = 'adult-paging';
        server.responses['/adult-paging.m3u'] =
            '#EXTM3U\n${List.generate(135, (index) {
              final marker = index % 4 == 0 ? ' [XXX]' : '';
              return '#EXTINF:-1 group-title="Movies",Movie $index$marker\n'
                  'https://example.invalid/movie/$index.mp4\n';
            }).join()}';
        await createCatalogSyncService(
          adapter,
          searchIndexer: SqliteCatalogSearchIndexer(
            databaseAdapter: adapter,
            autoStartWorker: false,
          ),
        ).load(
          playlistId: id,
          playlistUrl: server.url('/adult-paging.m3u'),
          policy: CatalogLoadPolicy.networkOnly,
        );
        final group = (await queries.queryGroups(
          id,
          kind: CatalogGroupKind.movie,
        )).single;
        final titles = <String>[];
        var offset = 0;
        while (true) {
          final page = await queries.itemsInGroup(
            id,
            group.id,
            sort: CatalogSort.playlistOrder,
            excludeMarkedAdult: true,
            offset: offset,
            limit: 17,
          );
          expect(page.total, 101);
          titles.addAll(page.items.map((item) => item.title));
          if (!page.hasMore) break;
          offset = page.nextOffset;
        }
        expect(titles, [
          for (var index = 0; index < 135; index++)
            if (index % 4 != 0) 'Movie $index',
        ]);
        expect((await queries.itemsInGroup(id, group.id)).total, 135);
      },
    );

    test(
      'automatic views filter marked groups and items across pages',
      () async {
        const id = 'adult-labels';
        server.responses['/adult-labels.m3u'] = adultLabelsPlaylistText;
        await createCatalogSyncService(
          adapter,
          searchIndexer: SqliteCatalogSearchIndexer(
            databaseAdapter: adapter,
            autoStartWorker: false,
          ),
        ).load(
          playlistId: id,
          playlistUrl: server.url('/adult-labels.m3u'),
          policy: CatalogLoadPolicy.networkOnly,
        );
        final view = CatalogViewState();
        addTearDown(view.dispose);
        await view.bind(service: queries, playlistId: id);
        expect(view.homeLiveGroup?.title, 'Sweden');
        expect(view.homeMoviesGroup?.title, 'Family Movies');
        expect(view.homeSeriesGroup?.title, 'Family Series');
        expect(view.homeLive.map((item) => item.title), ['Ordinary channel']);
        expect(view.homeMovies.map((item) => item.title), [
          'Another film',
          'Ordinary film',
        ]);
        expect(view.homeSeries.map((item) => item.title), ['Ordinary Show']);
        final db = await adapter.database;
        final plan = await db.rawQuery(
          '''
EXPLAIN QUERY PLAN SELECT s.series_key FROM series_v8 s
WHERE s.group_id = ? AND NOT EXISTS (
  SELECT 1 FROM items i WHERE i.series_key = s.series_key
    AND instr(lower(i.title), ?) > 0
)
''',
          [view.homeSeriesGroup!.id, '[xxx]'],
        );
        expect(
          plan.map((row) => row['detail'].toString()).join(' '),
          contains('idx_items_series_episode'),
        );
        final movieGroup = view.homeMoviesGroup!;
        final first = await queries.itemsInGroup(
          id,
          movieGroup.id,
          sort: CatalogSort.playlistOrder,
          excludeMarkedAdult: true,
          limit: 1,
        );
        final next = await queries.itemsInGroup(
          id,
          movieGroup.id,
          sort: CatalogSort.playlistOrder,
          excludeMarkedAdult: true,
          limit: 1,
          offset: first.nextOffset,
        );
        expect(first.total, 2);
        expect([...first.items, ...next.items].map((e) => e.title), [
          'Ordinary film',
          'Another film',
        ]);
        await view.showItems(CatalogItemKind.movie, selectFirstGroup: true);
        await view.setCatalogSort(
          CatalogGroupKind.movie,
          CatalogSort.playlistOrder,
        );
        expect(view.items.items.map((e) => e.title), [
          'Ordinary film',
          'Another film',
        ]);
        await view.selectBrowseGroup(view.selectedGroupId);
        expect(view.items.total, 3);
        await view.selectBrowseGroup(null);
        expect(view.items.total, 4);
        final indexer = SqliteCatalogSearchIndexer(
          databaseAdapter: adapter,
          autoStartWorker: false,
        );
        await indexer.processQueue(playlistId: id);
        await view.search('Marked film');
        expect(view.searchResults.items.single.title, 'Marked film [xXx]');
        await view.showSeries(selectFirstGroup: true);
        expect(view.series.items.single.title, 'Ordinary Show');
        await view.selectBrowseGroup(view.selectedGroupId);
        expect(view.series.total, 2);
      },
    );

    test(
      'Home and browse follow first visible group after refresh reorders it',
      () async {
        const id = 'first-groups';
        server.responses['/groups.m3u'] = firstGroupsPlaylistText;
        final sync = createCatalogSyncService(
          adapter,
          searchIndexer: SqliteCatalogSearchIndexer(
            databaseAdapter: adapter,
            autoStartWorker: false,
          ),
        );
        Future<void> refresh() async {
          await sync.load(
            playlistId: id,
            playlistUrl: server.url('/groups.m3u'),
            policy: CatalogLoadPolicy.networkOnly,
          );
        }

        await refresh();
        final view = CatalogViewState();
        addTearDown(view.dispose);
        await view.bind(service: queries, playlistId: id);
        expect(view.homeLiveGroup?.title, 'Sweden');
        expect(view.homeLive.map((item) => item.title), [
          'Welcome channel',
          'SVT channel',
        ]);
        expect(view.homeMoviesGroup?.title, 'Zulu Movies');
        expect(view.homeSeriesGroup?.title, 'Zulu Series');
        await view.showItems(CatalogItemKind.live, selectFirstGroup: true);
        expect(view.items.items.map((item) => item.title), [
          'Welcome channel',
          'SVT channel',
        ]);
        await view.showItems(CatalogItemKind.movie, selectFirstGroup: true);
        expect(view.items.items.single.title, 'Z movie');
        await view.showSeries(selectFirstGroup: true);
        expect(view.series.items.single.title, 'Z Show');

        final database = await adapter.database;
        await database.insert('hidden_groups_v8', {
          'playlist_id': id,
          'kind': 1,
          'group_title': 'Sweden',
          'profile_id': 'default',
        });
        await view.refreshHomeSections();
        expect(view.homeLiveGroup?.title, 'Alpha Live');
        await view.showItems(CatalogItemKind.live, selectFirstGroup: true);
        expect(view.items.items.single.title, 'A channel');
        await database.delete(
          'hidden_groups_v8',
          where: 'playlist_id = ?',
          whereArgs: [id],
        );

        const welcome =
            '#EXTINF:-1 group-title="Sweden",Welcome channel\nhttps://example.invalid/live/welcome.m3u8\n';
        server.responses['/groups.m3u'] =
            '${firstGroupsPlaylistText.replaceFirst(welcome, '')}$welcome';
        await refresh();
        await view.refreshHomeSections();
        expect(view.homeLiveGroup?.title, 'Alpha Live');
        await view.showItems(CatalogItemKind.live, selectFirstGroup: true);
        expect(view.items.items.single.title, 'A channel');
      },
    );

    test(
      'paginates without gaps or duplicates and reports a stable total',
      () async {
        final first = await queries.queryItems(
          CatalogQuery(
            playlistId: playlistId,
            kinds: const [CatalogItemKind.live],
            limit: 2,
          ),
        );
        expect(first.total, 3);
        expect(first.items.map((i) => i.title), ['Alpha News', 'Beta Sports']);
        expect(first.hasMore, isTrue);

        final second = await queries.queryItems(
          CatalogQuery(
            playlistId: playlistId,
            kinds: const [CatalogItemKind.live],
            limit: 2,
            offset: first.nextOffset,
          ),
        );
        expect(second.items.map((i) => i.title), ['Gamma News']);
        expect(second.hasMore, isFalse);

        final merged = first.append(second);
        expect(merged.items.map((i) => i.id).toSet(), hasLength(3));
      },
    );

    test(
      'an offset beyond the end yields an empty page, not an error',
      () async {
        final page = await queries.queryItems(
          CatalogQuery(playlistId: playlistId, offset: 500),
        );
        expect(page.items, isEmpty);
        expect(page.total, 9);
        expect(page.hasMore, isFalse);
      },
    );

    test('filters by kind and group', () async {
      final page = await queries.queryItems(
        CatalogQuery(
          playlistId: playlistId,
          kinds: const [CatalogItemKind.live],
          group: 'News',
        ),
      );
      expect(page.items.map((i) => i.title), ['Alpha News', 'Gamma News']);
    });

    test('playlistOrder sort follows the source index', () async {
      final page = await queries.queryItems(
        CatalogQuery(playlistId: playlistId, sort: CatalogSort.playlistOrder),
      );
      expect(page.items.first.title, 'Alpha News');
      expect(page.items.last.title, 'Pine Gap S02 E01');
    });

    test(
      'Swedish group sorts across pages and follows a reordered refresh',
      () async {
        const swedishId = 'swedish-query';
        server.responses['/swedish.m3u'] = swedishPlaylistText(
          swedishChannelNames,
        );
        final sync = createCatalogSyncService(
          adapter,
          searchIndexer: SqliteCatalogSearchIndexer(
            databaseAdapter: adapter,
            autoStartWorker: false,
          ),
        );
        Future<void> refresh() => sync
            .load(
              playlistId: swedishId,
              playlistUrl: server.url('/swedish.m3u'),
              policy: CatalogLoadPolicy.networkOnly,
            )
            .then((_) {});
        await refresh();
        final groups = await queries.queryGroups(
          swedishId,
          kind: CatalogGroupKind.live,
        );
        final groupId = groups.single.id;
        for (final sort in CatalogSort.values) {
          final titles = <String>[];
          final ids = <String>{};
          var offset = 0;
          while (true) {
            final page = await queries.itemsInGroup(
              swedishId,
              groupId,
              sort: sort,
              limit: 2,
              offset: offset,
            );
            expect(page.total, 7);
            titles.addAll(page.items.map((item) => item.title));
            ids.addAll(page.items.map((item) => item.id));
            if (!page.hasMore) break;
            offset = page.nextOffset;
          }
          final expected = [...swedishChannelNames];
          if (sort == CatalogSort.title) expected.sort();
          expect(titles, expected);
          expect(ids, hasLength(7));
        }
        final reordered = swedishChannelNames.reversed.toList();
        server.responses['/swedish.m3u'] = swedishPlaylistText(reordered);
        await refresh();
        final refreshed = await queries.itemsInGroup(
          swedishId,
          groupId,
          sort: CatalogSort.playlistOrder,
        );
        expect(refreshed.items.map((item) => item.title), reordered);
      },
    );

    test(
      'groups are distinct, sorted and scoped to the requested kinds',
      () async {
        expect(
          await queries.groups(playlistId, kinds: const [CatalogItemKind.live]),
          ['News', 'Sports'],
        );
        expect(
          await queries.groups(
            playlistId,
            kinds: const [CatalogItemKind.movie],
          ),
          ['Movies'],
        );
      },
    );

    test('homePreview is bounded by the requested limit', () async {
      final preview = await queries.homePreview(
        playlistId,
        kind: CatalogItemKind.movie,
        limit: 2,
      );
      expect(preview, hasLength(2));
      expect(preview.first.title, 'Alpha Movie');
    });

    test(
      'Movies and Series sort globally and within groups across pages and refresh',
      () async {
        final repository = SqliteCatalogRepository(
          databaseAdapter: adapter,
          autoStartSearchIndexWorker: false,
        );
        server.responses['/vod.m3u'] = movieSeriesPlaylistText;
        final sync = createCatalogSyncService(
          adapter,
          searchIndexer: SqliteCatalogSearchIndexer(
            databaseAdapter: adapter,
            autoStartWorker: false,
          ),
        );
        Future<void> refresh() async {
          await sync.load(
            playlistId: 'vod',
            playlistUrl: server.url('/vod.m3u'),
            policy: CatalogLoadPolicy.networkOnly,
          );
        }

        await refresh();
        for (final kind in [CatalogGroupKind.movie, CatalogGroupKind.series]) {
          final group = (await queries.queryGroups('vod', kind: kind)).single;
          for (final grouped in [false, true]) {
            for (final sort in CatalogSort.values) {
              final titles = <String>[];
              final ids = <String>{};
              for (var offset = 0; offset < 3; offset++) {
                if (kind == CatalogGroupKind.series) {
                  final page = grouped
                      ? await repository.seriesInGroup(
                          'vod',
                          group.id,
                          sort: sort,
                          offset: offset,
                          limit: 1,
                        )
                      : await repository.querySeries(
                          'vod',
                          sort: sort,
                          offset: offset,
                          limit: 1,
                        );
                  expect(page.total, 3);
                  titles.addAll(page.items.map((item) => item.title));
                  ids.addAll(page.items.map((item) => item.id));
                } else {
                  final page = grouped
                      ? await queries.itemsInGroup(
                          'vod',
                          group.id,
                          sort: sort,
                          offset: offset,
                          limit: 1,
                        )
                      : await queries.queryItems(
                          CatalogQuery(
                            playlistId: 'vod',
                            kinds: const [CatalogItemKind.movie],
                            sort: sort,
                            offset: offset,
                            limit: 1,
                          ),
                        );
                  expect(page.total, 3);
                  titles.addAll(page.items.map((item) => item.title));
                  ids.addAll(page.items.map((item) => item.id));
                }
              }
              final suffix = kind == CatalogGroupKind.series ? 'Show' : 'Movie';
              final expected = [
                'Zebra $suffix',
                'Alpha $suffix',
                'Middle $suffix',
              ];
              if (sort == CatalogSort.title) expected.sort();
              expect(titles, expected);
              expect(ids, hasLength(3));
            }
          }
        }
        final zebra = (await queries.querySeries(
          'vod',
          searchTerm: 'Zebra',
        )).items.single;
        final seasons = await queries.seasons(zebra.id);
        expect(seasons.map((season) => season.seasonNumber), [1, 2]);
        expect(
          (await queries.episodes(
            seasons.last.id,
          )).items.map((item) => item.episodeNumber),
          [1, 2],
        );
        // Move the first series and movie to the end without changing their contents.
        final entries = movieSeriesPlaylistText
            .substring('#EXTM3U\n'.length)
            .split('#EXTINF:')
            .skip(1)
            .toList();
        server.responses['/vod.m3u'] =
            '#EXTM3U\n${[...entries.skip(2), ...entries.take(2)].map((entry) => '#EXTINF:$entry').join()}';
        await refresh();
        expect(
          (await queries.querySeries(
            'vod',
            sort: CatalogSort.playlistOrder,
          )).items.map((item) => item.title),
          ['Alpha Show', 'Zebra Show', 'Middle Show'],
        );
        expect(
          (await queries.queryItems(
            const CatalogQuery(
              playlistId: 'vod',
              kinds: [CatalogItemKind.movie],
              sort: CatalogSort.playlistOrder,
            ),
          )).items.map((item) => item.title),
          ['Alpha Movie', 'Middle Movie', 'Zebra Movie'],
        );
        final db = await adapter.database;
        final beforeRepair = await db.query(
          'series_v8',
          where: 'playlist_id = ?',
          whereArgs: ['vod'],
          orderBy: 'series_key',
        );
        await db.rawUpdate(
          "UPDATE series_v8 SET ord = -series_key WHERE playlist_id = 'vod'",
        );
        // Reconstruct a persisted v12 cache with stale series positions.
        await db.execute('DROP INDEX idx_items_series_membership');
        await db.execute('DROP TRIGGER invalidate_series_metadata_source');
        await db.execute('DROP TRIGGER invalidate_series_metadata_episode');
        await db.execute(
          'DROP TRIGGER invalidate_series_metadata_episode_update',
        );
        await db.execute(
          'DROP TRIGGER invalidate_series_metadata_episode_insert',
        );
        await db.execute('DROP TRIGGER invalidate_series_metadata_title');
        await db.execute('DROP TABLE series_metadata_cache');
        await db.execute('DROP TRIGGER invalidate_movie_metadata_source');
        await db.execute('DROP TABLE movie_provider_bindings');
        await db.execute('DROP TABLE movie_metadata_cache');
        await db.execute('DROP INDEX idx_series_v8_group_ord');
        await db.execute('DROP INDEX idx_series_v8_playlist_ord');
        await db.delete('schema_migrations', where: 'version = 13');
        await db.update('schema_meta', {
          'value': '12',
        }, where: "key = 'schema_version'");
        await db.execute('PRAGMA user_version = 12');
        await adapter.close();
        final upgradedDb = await adapter.database;
        expect(
          (await upgradedDb.rawQuery(
            'PRAGMA user_version',
          )).single.values.single,
          17,
        );
        await const CatalogSortV13Migration().up(upgradedDb);
        expect(
          await upgradedDb.query(
            'series_v8',
            where: 'playlist_id = ?',
            whereArgs: ['vod'],
            orderBy: 'series_key',
          ),
          beforeRepair,
        );
        for (final filter in ['playlist_id', 'group_id']) {
          final plan = await upgradedDb.rawQuery(
            'EXPLAIN QUERY PLAN SELECT series_key FROM series_v8 '
            'WHERE $filter = ? ORDER BY ord, series_key LIMIT 1',
            [filter == 'playlist_id' ? 'vod' : zebra.groupId],
          );
          final details = plan.map((row) => row['detail']).join(' ');
          expect(
            details,
            contains(
              'idx_series_v8_${filter == 'playlist_id' ? 'playlist' : 'group'}_ord',
            ),
          );
          expect(details, isNot(contains('TEMP B-TREE')));
        }
      },
    );

    test('reads the series hierarchy from the database', () async {
      final series = await queries.querySeries(playlistId);
      expect(series.total, 1);
      final pineGap = series.items.single;
      expect(pineGap.title, 'Pine Gap');
      expect(pineGap.seasonCount, 2);
      expect(pineGap.episodeCount, 3);

      final seasons = await queries.seasons(pineGap.id);
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(seasons.first.episodeCount, 2);
      expect(seasons.last.episodeCount, 1);

      final episodes = await queries.episodes(seasons.first.id);
      expect(episodes.total, 2);
      expect(episodes.items.map((e) => e.title), [
        'Pine Gap S01 E01',
        'Pine Gap S01 E02',
      ]);
      expect(
        episodes.items.every((e) => e.kind == CatalogItemKind.episode),
        isTrue,
      );
    });

    test('series search matches on normalized titles', () async {
      expect(
        (await queries.querySeries(playlistId, searchTerm: 'PINE')).total,
        1,
      );
      expect(
        (await queries.querySeries(playlistId, searchTerm: 'nope')).total,
        0,
      );
    });

    test('full-text search matches token prefixes', () async {
      final page = await queries.queryItems(
        CatalogQuery(playlistId: playlistId, searchTerm: 'sig'),
      );
      expect(page.items.map((i) => i.title), ['The Last Signal']);

      final pine = await queries.queryItems(
        CatalogQuery(playlistId: playlistId, searchTerm: 'pine'),
      );
      expect(pine.total, 3);
    });

    test('search respects kind filters and playlist scope', () async {
      final page = await queries.queryItems(
        CatalogQuery(
          playlistId: playlistId,
          searchTerm: 'alpha',
          kinds: const [CatalogItemKind.movie],
        ),
      );
      expect(page.items.map((i) => i.title), ['Alpha Movie']);
    });

    test('hostile search input is neutralized instead of throwing', () async {
      for (final term in const ['pine" OR NEAR(', '*', '""', 'gap*"']) {
        await expectLater(
          queries.queryItems(
            CatalogQuery(playlistId: playlistId, searchTerm: term),
          ),
          completes,
        );
      }

      final page = await queries.queryItems(
        const CatalogQuery(playlistId: 'p', searchTerm: '***'),
      );
      expect(page.total, 0);
    });

    test('itemById returns the full item and null for unknown ids', () async {
      final page = await queries.queryItems(
        CatalogQuery(
          playlistId: playlistId,
          kinds: const [CatalogItemKind.live],
          group: 'News',
        ),
      );
      final item = await queries.itemById(page.items.first.id);

      expect(item, isNotNull);
      expect(item!.title, 'Alpha News');
      expect(item.streamUrl, 'https://stream.test/alpha.m3u8');
      expect(item.type, ContentType.live);
      expect(item.metadata['tvg-id'], 'alpha');

      expect(await queries.itemById('does-not-exist'), isNull);
    });
  });
}
