import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_classifier.dart';
import 'package:iptv_flutter/services/catalog/catalog_hash.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';

void main() {
  group('catalog identity', () {
    test('hash64 matches the FNV-1a 64-bit empty-string vector', () {
      expect(hash64(''), -3750763034362895579);
      expect(
        hash64('hello'),
        (BigInt.parse('a430d84680aabd0b', radix: 16) - (BigInt.one << 64))
            .toInt(),
      );
    });

    test('item key is stable when title and playlist order change', () {
      expect(
        itemKey('https://stream.test/42'),
        itemKey('https://stream.test/42'),
      );
      expect(
        itemKey('https://stream.test/42', title: 'Old title'),
        itemKey('https://stream.test/42', title: 'New title'),
      );
    });

    test('duplicate URL occurrences are disambiguated deterministically', () {
      final first = itemKey('https://stream.test/42');
      final duplicate = itemKey(
        'https://stream.test/42',
        title: 'Second entry',
        duplicateOccurrence: 1,
      );

      expect(duplicate, isNot(first));
      expect(
        duplicate,
        itemKey(
          'https://stream.test/42',
          title: 'Second entry',
          duplicateOccurrence: 1,
        ),
      );
      expect(
        duplicate,
        isNot(
          itemKey(
            'https://stream.test/42',
            title: 'Second entry',
            duplicateOccurrence: 2,
          ),
        ),
      );
    });

    test(
      'content hash is typed, ordered and distinguishes null from empty',
      () {
        expect(
          contentHash(['title', 'url']),
          isNot(contentHash(['url', 'title'])),
        );
        expect(contentHash([1]), isNot(contentHash(['1'])));
        expect(contentHash([null]), isNot(contentHash([''])));
        expect(contentHash(['title', null]), contentHash(['title', null]));
      },
    );

    test('series key is scoped by playlist, group kind and series title', () {
      final key = seriesKey(
        playlistId: 'playlist-a',
        groupKind: CatalogGroupKind.series,
        groupTitle: 'Drama',
        seriesTitle: 'Example',
      );
      expect(
        key,
        seriesKey(
          playlistId: 'playlist-a',
          groupKind: CatalogGroupKind.series,
          groupTitle: 'Drama',
          seriesTitle: 'Example',
        ),
      );
      expect(
        key,
        isNot(
          seriesKey(
            playlistId: 'playlist-b',
            groupKind: CatalogGroupKind.series,
            groupTitle: 'Drama',
            seriesTitle: 'Example',
          ),
        ),
      );
    });
  });

  group('catalog classification', () {
    test('Xtream path takes precedence over extension, group and title', () {
      final result = classifyCatalogItem(
        streamUrl: 'https://provider.test/series/user/pass/42.ts',
        groupTitle: 'Movies',
        title: 'Example S01E02',
      );

      expect(result.reason, 'xtream_series_path');
      expect(result.itemKind, CatalogItemKind.episode);
      expect(result.groupKind, CatalogGroupKind.series);
      expect(result.episodeMatch?.seasonNumber, 1);
    });

    test('recognized media extension takes precedence over group hints', () {
      final result = classifyCatalogItem(
        streamUrl: 'https://cdn.test/channel.mkv',
        groupTitle: 'Live Sports',
        title: 'Sports Channel',
      );

      expect(result.reason, 'url_extension');
      expect(result.itemKind, CatalogItemKind.movie);
      expect(result.groupKind, CatalogGroupKind.movie);
    });

    test(
      'group and provider hints take precedence over episode-shaped title',
      () {
        final result = classifyCatalogItem(
          streamUrl: 'https://cdn.test/content',
          groupTitle: 'Movies',
          providerType: 'series',
          title: 'Example S01E02',
        );

        expect(result.reason, 'group_or_provider_hint');
        expect(result.groupKind, CatalogGroupKind.movie);
      },
    );

    test(
      'series group hint classifies episode and retains parsed episode data',
      () {
        final result = classifyCatalogItem(
          streamUrl: 'https://cdn.test/content',
          groupTitle: 'TV Series',
          title: 'Example S02E07',
        );

        expect(result.groupKind, CatalogGroupKind.series);
        expect(result.itemKind, CatalogItemKind.episode);
        expect(result.episodeMatch?.episodeNumber, 7);
      },
    );

    test('episode-shaped title is the fallback before live', () {
      final result = classifyCatalogItem(
        streamUrl: 'https://cdn.test/content',
        groupTitle: 'Unsorted',
        title: 'Example S02E07',
      );

      expect(result.reason, 'episode_title');
      expect(result.groupKind, CatalogGroupKind.series);
    });

    test('unclassified item defaults to live', () {
      final result = classifyCatalogItem(
        streamUrl: 'https://cdn.test/content',
        groupTitle: 'News',
        title: 'World News',
      );

      expect(result.reason, 'default_live');
      expect(result.itemKind, CatalogItemKind.live);
      expect(result.groupKind, CatalogGroupKind.live);
    });
  });
}
