import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';

import 'support/catalog_http_test_server.dart';
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

  group('SqliteCatalogRepository as CatalogQueryService', () {
    late SqfliteDatabaseAdapter adapter;
    late SqliteCatalogRepository repo;
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

      repo = SqliteCatalogRepository(
        databaseAdapter: adapter,
        autoStartSearchIndexWorker: false,
        useCatalogImporterV9: true,
      );
      playlistId = 'query-v9-playlist';
      await repo.load(
        playlistId: playlistId,
        playlistUrl: server.url('/playlist.m3u'),
        policy: CatalogLoadPolicy.networkOnly,
      );
      await repo.processCatalogSearchIndexQueue(playlistId: playlistId);
    });

    test(
      'paginates without gaps or duplicates and reports a stable total',
      () async {
        final first = await repo.queryItems(
          CatalogQuery(
            playlistId: playlistId,
            kinds: const [CatalogItemKind.live],
            limit: 2,
          ),
        );
        expect(first.total, 3);
        expect(first.items.map((i) => i.title), ['Alpha News', 'Beta Sports']);
        expect(first.hasMore, isTrue);

        final second = await repo.queryItems(
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
        final page = await repo.queryItems(
          CatalogQuery(playlistId: playlistId, offset: 500),
        );
        expect(page.items, isEmpty);
        expect(page.total, 9);
        expect(page.hasMore, isFalse);
      },
    );

    test('filters by kind and group', () async {
      final page = await repo.queryItems(
        CatalogQuery(
          playlistId: playlistId,
          kinds: const [CatalogItemKind.live],
          group: 'News',
        ),
      );
      expect(page.items.map((i) => i.title), ['Alpha News', 'Gamma News']);
    });

    test('playlistOrder sort follows the source index', () async {
      final page = await repo.queryItems(
        CatalogQuery(playlistId: playlistId, sort: CatalogSort.playlistOrder),
      );
      expect(page.items.first.title, 'Alpha News');
      expect(page.items.last.title, 'Pine Gap S02 E01');
    });

    test(
      'groups are distinct, sorted and scoped to the requested kinds',
      () async {
        expect(
          await repo.groups(playlistId, kinds: const [CatalogItemKind.live]),
          ['News', 'Sports'],
        );
        expect(
          await repo.groups(playlistId, kinds: const [CatalogItemKind.movie]),
          ['Movies'],
        );
      },
    );

    test('homePreview is bounded by the requested limit', () async {
      final preview = await repo.homePreview(
        playlistId,
        kind: CatalogItemKind.movie,
        limit: 2,
      );
      expect(preview, hasLength(2));
      expect(preview.first.title, 'Alpha Movie');
    });

    test('reads the series hierarchy from the database', () async {
      final series = await repo.querySeries(playlistId);
      expect(series.total, 1);
      final pineGap = series.items.single;
      expect(pineGap.title, 'Pine Gap');
      expect(pineGap.seasonCount, 2);
      expect(pineGap.episodeCount, 3);

      final seasons = await repo.seasons(pineGap.id);
      expect(seasons.map((s) => s.seasonNumber), [1, 2]);
      expect(seasons.first.episodeCount, 2);
      expect(seasons.last.episodeCount, 1);

      final episodes = await repo.episodes(seasons.first.id);
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
      expect((await repo.querySeries(playlistId, searchTerm: 'PINE')).total, 1);
      expect((await repo.querySeries(playlistId, searchTerm: 'nope')).total, 0);
    });

    test('full-text search matches token prefixes', () async {
      final page = await repo.queryItems(
        CatalogQuery(playlistId: playlistId, searchTerm: 'sig'),
      );
      expect(page.items.map((i) => i.title), ['The Last Signal']);

      final pine = await repo.queryItems(
        CatalogQuery(playlistId: playlistId, searchTerm: 'pine'),
      );
      expect(pine.total, 3);
    });

    test('search respects kind filters and playlist scope', () async {
      final page = await repo.queryItems(
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
          repo.queryItems(
            CatalogQuery(playlistId: playlistId, searchTerm: term),
          ),
          completes,
        );
      }

      final page = await repo.queryItems(
        const CatalogQuery(playlistId: 'p', searchTerm: '***'),
      );
      expect(page.total, 0);
    });

    test('itemById returns the full item and null for unknown ids', () async {
      final page = await repo.queryItems(
        CatalogQuery(
          playlistId: playlistId,
          kinds: const [CatalogItemKind.live],
          group: 'News',
        ),
      );
      final item = await repo.itemById(page.items.first.id);

      expect(item, isNotNull);
      expect(item!.title, 'Alpha News');
      expect(item.streamUrl, 'https://stream.test/alpha.m3u8');
      expect(item.type, ContentType.live);
      expect(item.metadata['tvg-id'], 'alpha');

      expect(await repo.itemById('does-not-exist'), isNull);
    });
  });
}
