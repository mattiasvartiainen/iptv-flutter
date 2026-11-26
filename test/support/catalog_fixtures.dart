import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';

const swedishChannelNames = [
  'Welcome to NXT 2026',
  'SVT1 SD SE',
  'SVT1 HD SE',
  'SVT1 FHD SE',
  'SVT2 SD SE',
  'SVT2 HD SE',
  'SVT2 FHD SE',
];

const movieSeriesPlaylistText = '''#EXTM3U
#EXTINF:-1 group-title="Movies",Zebra Movie
https://example.invalid/movie/zebra.mp4
#EXTINF:-1 group-title="Series",Zebra Show S02 E02
https://example.invalid/series/zebra-s02e02.mkv
#EXTINF:-1 group-title="Movies",Alpha Movie
https://example.invalid/movie/alpha.mp4
#EXTINF:-1 group-title="Series",Alpha Show S01 E01
https://example.invalid/series/alpha-s01e01.mkv
#EXTINF:-1 group-title="Series",Zebra Show S01 E01
https://example.invalid/series/zebra-s01e01.mkv
#EXTINF:-1 group-title="Movies",Middle Movie
https://example.invalid/movie/middle.mp4
#EXTINF:-1 group-title="Series",Middle Show S01 E01
https://example.invalid/series/middle-s01e01.mkv
#EXTINF:-1 group-title="Series",Zebra Show S02 E01
https://example.invalid/series/zebra-s02e01.mkv
''';

const firstGroupsPlaylistText = '''#EXTM3U
#EXTINF:-1 group-title="Sweden",Welcome channel
https://example.invalid/live/welcome.m3u8
#EXTINF:-1 group-title="Alpha Live",A channel
https://example.invalid/live/alpha.m3u8
#EXTINF:-1 group-title="Sweden",SVT channel
https://example.invalid/live/svt.m3u8
#EXTINF:-1 group-title="Zulu Movies",Z movie
https://example.invalid/movie/z.mp4
#EXTINF:-1 group-title="Alpha Movies",A movie
https://example.invalid/movie/a.mp4
#EXTINF:-1 group-title="Zulu Series",Z Show S01 E01
https://example.invalid/series/z.mkv
#EXTINF:-1 group-title="Alpha Series",A Show S01 E01
https://example.invalid/series/a.mkv
''';

String swedishPlaylistText(Iterable<String> names) =>
    '#EXTM3U\n${names.map((name) => '#EXTINF:-1 group-title="Sweden",$name\n'
        'https://example.invalid/live/${Uri.encodeComponent(name)}.m3u8\n').join()}';

class FixtureCatalogRepository implements CatalogRepository {
  const FixtureCatalogRepository();

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) async => CatalogLoadResult(
    playlistId: playlistId,
    itemCount: fixtureCatalog.length,
  );
}

const fixtureCatalog = <ContentItem>[
  ContentItem(
    id: 'news-24',
    title: 'News 24',
    type: ContentType.live,
    streamUrl: 'https://example.invalid/live/news-24.m3u8',
    group: 'News',
    description: 'A fixture live channel for testing navigation and playback.',
  ),
  ContentItem(
    id: 'world-sports',
    title: 'World Sports',
    type: ContentType.live,
    streamUrl: 'https://example.invalid/live/world-sports.m3u8',
    group: 'Sports',
    sourceIndex: 1,
    description: 'A fixture sports channel with a fake stream URL.',
  ),
  ContentItem(
    id: 'city-radio',
    title: 'City Radio',
    type: ContentType.live,
    streamUrl: 'https://example.invalid/live/city-radio.m3u8',
    group: 'News',
    sourceIndex: 2,
    description: 'A fixture music channel for focus testing.',
  ),
  ContentItem(
    id: 'the-last-signal',
    title: 'The Last Signal',
    type: ContentType.vod,
    streamUrl: 'https://example.invalid/vod/the-last-signal.m3u8',
    group: 'Movies',
    sourceIndex: 3,
    description: 'A fixture movie entry for the VOD flow.',
  ),
  ContentItem(
    id: 'northbound',
    title: 'Northbound',
    type: ContentType.vod,
    streamUrl: 'https://example.invalid/vod/northbound.m3u8',
    group: 'Movies',
    sourceIndex: 4,
    description: 'A fixture movie entry with no external metadata.',
  ),
];
