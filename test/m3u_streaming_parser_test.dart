import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';

void main() {
  const parser = M3uParser();

  test(
    'streaming parser matches the existing parser for one-character chunks',
    () {
      const playlist = '''#EXTM3U
#EXTINF:-1 tvg-id="news" tvg-name="News 24" tvg-logo="https://cdn.test/news.png" group-title="News",News 24
https://stream.test/news.m3u8
#EXTINF:-1 group-title="Movies",The Last Signal
https://stream.test/movie.m3u8
#EXTINF:-1 group-title="News",Missing URL
#EXTVLCOPT:http-referrer=https://referrer.test
#EXTINF:-1 group-title="Sports",Valid
https://stream.test/valid.m3u8''';
      final expected = parser.parse(
        playlist,
        sourceUrl: 'https://provider.test/lists/playlist.m3u',
      );
      final actual = <ContentItem>[];
      final streaming = M3uStreamingParser(
        sourceUrl: 'https://provider.test/lists/playlist.m3u',
      );

      for (var index = 0; index < playlist.length; index++) {
        streaming.addChunk(playlist.substring(index, index + 1), actual.add);
      }
      streaming.finish(actual.add);

      expect(actual, hasLength(expected.length));
      for (var index = 0; index < expected.length; index++) {
        _expectSameItem(actual[index], expected[index]);
      }
      expect(streaming.parsedItemCount, expected.length);
    },
  );

  test('streaming parser handles chunks split at every line boundary', () {
    const playlist = '''#EXTM3U
#EXTINF:-1 group-title="News",Channel A
https://stream.test/a.m3u8
#EXTINF:-1 group-title="News",Channel B
https://stream.test/b.m3u8''';
    final actual = <ContentItem>[];
    final streaming = M3uStreamingParser();

    for (final line in playlist.split('\n')) {
      streaming.addChunk('$line\n', actual.add);
    }
    streaming.finish(actual.add);

    final expected = parser.parse(playlist);
    expect(actual.map((item) => item.id), expected.map((item) => item.id));
    expect(actual.map((item) => item.sourceIndex), [0, 1]);
  });

  test('streaming parser rejects chunks after finish', () {
    final streaming = M3uStreamingParser();
    streaming.finish((_) {});

    expect(() => streaming.addChunk('#EXTM3U\n', (_) {}), throwsStateError);
  });
}

void _expectSameItem(ContentItem actual, ContentItem expected) {
  expect(actual.id, expected.id);
  expect(actual.title, expected.title);
  expect(actual.type, expected.type);
  expect(actual.streamUrl, expected.streamUrl);
  expect(actual.group, expected.group);
  expect(actual.description, expected.description);
  expect(actual.logoUrl, expected.logoUrl);
  expect(actual.posterUrl, expected.posterUrl);
  expect(actual.metadata, expected.metadata);
  expect(actual.sourceIndex, expected.sourceIndex);
}
