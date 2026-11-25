import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/catalog_search_indexer.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/storage/catalog_sort_v13_migration.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';

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
          14,
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
