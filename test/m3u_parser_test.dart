import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_normalizer.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';

void main() {
  const parser = M3uParser();

  test('parses standard EXTINF metadata', () {
    final items = parser.parse('''#EXTM3U
#EXTINF:-1 tvg-id="news" tvg-name="News 24" tvg-logo="https://cdn.test/news.png" group-title="News",News 24
https://stream.test/news.m3u8
''');

    expect(items, hasLength(1));
    expect(items.single.title, 'News 24');
    expect(items.single.group, 'News');
    expect(items.single.logoUrl, 'https://cdn.test/news.png');
    expect(items.single.type, ContentType.live);
    expect(items.single.streamUrl, 'https://stream.test/news.m3u8');
    expect(items.single.sourceIndex, 0);
  });

  test('classifies VOD using group metadata', () {
    final items = parser.parse(
      '''#EXTINF:-1 group-title="Movies",The Last Signal
https://stream.test/movie.m3u8
''',
    );

    expect(items.single.type, ContentType.vod);
  });

  for (final title in ['Patrik 1,5 (2008) [SE]', '[SE] Patrik 1,5 (2008)']) {
    for (final streaming in [false, true]) {
      test('preserves quoted commas: $title, streaming=$streaming', () {
        final playlist =
            '''#EXTM3U
#EXTINF:-1 xui-id="{XUI_ID}" tvg-id="" tvg-name="$title" tvg-logo="https://cdn.test/images/poster.jpg" group-title="Sweden (VOD)",$title
https://stream.test/movie.mp4
''';
        final items = <ContentItem>[];
        if (streaming) {
          final parser = M3uStreamingParser();
          for (var index = 0; index < playlist.length; index++) {
            parser.addChunk(playlist.substring(index, index + 1), items.add);
          }
          parser.finish(items.add);
        } else {
          items.addAll(parser.parse(playlist));
        }

        expect(items, hasLength(1));
        expect(items.single.title, title);
        expect(items.single.group, 'Sweden (VOD)');
        expect(items.single.logoUrl, 'https://cdn.test/images/poster.jpg');
        expect(items.single.type, ContentType.vod);
        expect(items.single.metadata['tvg-name'], title);
        expect(items.single.metadata['xui-id'], '{XUI_ID}');
      });
    }
  }

  test('ignores commas in all quoted attributes and preserves title commas', () {
    final item = parser.parse(
      '''#EXTINF:-1 tvg-name="Fallback, name" tvg-logo="https://cdn.test/a,b.jpg" group-title="Sweden, Movies",One, two, three
https://stream.test/movie.mp4
''',
    ).single;

    expect(item.title, 'One, two, three');
    expect(item.group, 'Sweden, Movies');
    expect(item.logoUrl, 'https://cdn.test/a,b.jpg');
  });

  for (final separator in ['', ',']) {
    test('uses quoted tvg-name fallback with separator "$separator"', () {
      final item = parser.parse(
        '''#EXTINF:-1 tvg-name="Patrik 1,5" group-title="Movies"$separator
https://stream.test/movie.mp4
''',
      ).single;

      expect(item.title, 'Patrik 1,5');
      expect(item.group, 'Movies');
    });
  }

  test('does not interpret attribute-like title text as metadata', () {
    final item = parser.parse(
      '''#EXTINF:-1 tvg-name="Original" group-title="Movies",A "quoted, title" group-title="News" tvg-name="Other" tvg-logo="https://cdn.test/fake.jpg"
https://stream.test/movie.mp4
''',
    ).single;

    expect(
      item.title,
      'A "quoted, title" group-title="News" tvg-name="Other" '
      'tvg-logo="https://cdn.test/fake.jpg"',
    );
    expect(item.group, 'Movies');
    expect(item.type, ContentType.vod);
    expect(item.metadata['tvg-name'], 'Original');
    expect(item.logoUrl, isNull);
  });

  test('uses safe fallbacks for missing metadata', () {
    final items = parser.parse('''#EXTINF:-1,
https://stream.test/unnamed.m3u8
''');

    expect(items.single.title, 'https://stream.test/unnamed.m3u8');
    expect(items.single.group, 'Uncategorized');
    expect(items.single.logoUrl, isNull);
  });

  test('ignores malformed records without a stream URL', () {
    final items = parser.parse('''#EXTM3U
#EXTINF:-1 group-title="News",Missing URL
#EXTVLCOPT:http-referrer=https://referrer.test
#EXTINF:-1 group-title="News",Valid
https://stream.test/valid.m3u8
''');

    expect(items, hasLength(1));
    expect(items.single.title, 'Valid');
  });

  test('resolves relative stream URLs when a source URL is provided', () {
    final items = parser.parse('''#EXTINF:-1 group-title="News",Relative
streams/news.m3u8
''', sourceUrl: 'https://provider.test/lists/playlist.m3u');

    expect(
      items.single.streamUrl,
      'https://provider.test/lists/streams/news.m3u8',
    );
  });

  test('returns an empty list for empty or comment-only playlists', () {
    expect(parser.parse(''), isEmpty);
    expect(parser.parse('#EXTM3U\n# comment\n'), isEmpty);
  });

  test('generates deterministic strong item IDs', () {
    final first = parser.parse('''#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
''', sourceUrl: 'https://provider.test/playlist.m3u');
    final second = parser.parse('''#EXTINF:-1 group-title="News",Channel A
https://stream.test/channel-a.m3u8
''', sourceUrl: 'https://provider.test/playlist.m3u');

    expect(first.single.id, second.single.id);
    expect(first.single.id, startsWith('item-'));
    expect(first.single.id.length, greaterThan(40));
  });

  test('does not classify zero-numbered labels as episodes', () {
    expect(
      CatalogNormalizer.parseSeriesEpisodeTitle(
        'Rascal Does Not Dream of Bunny Girl Senpai (2018) S11 E00',
      ),
      isNull,
    );
    expect(
      CatalogNormalizer.parseSeriesEpisodeTitle('Valid Series S11 E01'),
      isNotNull,
    );
  });
}
