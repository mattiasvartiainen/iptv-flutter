import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';

void main() {
  group('CatalogPage', () {
    test('reports paging state from offset, length and total', () {
      const page = CatalogPage<int>(items: [1, 2, 3], offset: 0, total: 10);

      expect(page.hasMore, isTrue);
      expect(page.nextOffset, 3);

      const last = CatalogPage<int>(items: [9, 10], offset: 8, total: 10);
      expect(last.hasMore, isFalse);
      expect(last.nextOffset, 10);
    });

    test('append keeps the original offset and adopts the newer total', () {
      const first = CatalogPage<int>(items: [1, 2], offset: 0, total: 5);
      const second = CatalogPage<int>(items: [3, 4], offset: 2, total: 4);

      final merged = first.append(second);

      expect(merged.items, [1, 2, 3, 4]);
      expect(merged.offset, 0);
      expect(merged.total, 4);
      expect(merged.hasMore, isFalse);
    });

    test('empty page has no items and no more results', () {
      const page = CatalogPage<int>.empty();

      expect(page.isEmpty, isTrue);
      expect(page.hasMore, isFalse);
    });
  });

  group('CatalogQuery', () {
    const base = CatalogQuery(playlistId: 'p1', limit: 50);

    test('nextPage advances the offset by the page size', () {
      expect(base.nextPage().offset, 50);
      expect(base.nextPage().nextPage().offset, 100);
      expect(base.nextPage().reset().offset, 0);
    });

    test('resultSetKey ignores paging position', () {
      expect(base.nextPage().resultSetKey, base.resultSetKey);

      final filtered = base.copyWith(group: 'Sports');
      expect(filtered.resultSetKey, isNot(base.resultSetKey));
    });

    test('copyWith can clear nullable filters', () {
      final filtered = base.copyWith(group: 'Sports', searchTerm: 'news');
      final cleared = filtered.copyWith(group: null, searchTerm: null);

      expect(cleared.group, isNull);
      expect(cleared.searchTerm, isNull);
      expect(cleared.hasSearchTerm, isFalse);
      expect(filtered.group, 'Sports');
    });

    test('blank search terms are not treated as a search', () {
      expect(base.copyWith(searchTerm: '   ').hasSearchTerm, isFalse);
      expect(base.copyWith(searchTerm: 'bbc').hasSearchTerm, isTrue);
    });
  });

  group('CatalogItemKind', () {
    test('maps storage values and falls back to unknown', () {
      expect(CatalogItemKind.fromStorage('live'), CatalogItemKind.live);
      expect(CatalogItemKind.fromStorage('movie'), CatalogItemKind.movie);
      expect(CatalogItemKind.fromStorage('episode'), CatalogItemKind.episode);
      expect(CatalogItemKind.fromStorage(null), CatalogItemKind.unknown);
      expect(CatalogItemKind.fromStorage('bogus'), CatalogItemKind.unknown);
    });

    test('collapses to ContentType for playback and legacy filters', () {
      expect(CatalogItemKind.live.contentType, ContentType.live);
      expect(CatalogItemKind.movie.contentType, ContentType.vod);
      expect(CatalogItemKind.episode.contentType, ContentType.vod);
    });
  });

  group('row mapping', () {
    test('CatalogItemSummary reads a media_items projection', () {
      final summary = CatalogItemSummary.fromRow(const {
        'id': 'item-1',
        'title': 'BBC One',
        'sort_title': 'bbc one',
        'content_type': 'live',
        'group_title': 'UK',
        'logo_url': 'https://example.test/logo.png',
        'artwork_url': null,
        'source_index': 7,
      });

      expect(summary.id, 'item-1');
      expect(summary.kind, CatalogItemKind.live);
      expect(summary.group, 'UK');
      expect(summary.sourceIndex, 7);
    });

    test(
      'CatalogItemSummary falls back to title when sort_title is absent',
      () {
        final summary = CatalogItemSummary.fromRow(const {
          'id': 'item-2',
          'title': 'Movie',
          'sort_title': null,
          'content_type': 'movie',
        });

        expect(summary.sortTitle, 'Movie');
        expect(summary.sourceIndex, 0);
        expect(summary.group, isNull);
      },
    );

    test('series and season summaries default their counts', () {
      final series = SeriesSummary.fromRow(const {
        'id': 'series-1',
        'title': 'Show',
        'sort_title': 'show',
        'season_count': 2,
        'episode_count': null,
      });
      expect(series.seasonCount, 2);
      expect(series.episodeCount, 0);

      final season = SeasonSummary.fromRow(const {
        'id': 'season-1',
        'series_id': 'series-1',
        'season_number': 1,
        'episode_count': 10,
      });
      expect(season.seasonNumber, 1);
      expect(season.episodeCount, 10);
    });
  });
}
