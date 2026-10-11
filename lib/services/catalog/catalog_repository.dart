import '../../models/content_item.dart';
import 'catalog_import_progress.dart';

export 'catalog_import_progress.dart';

enum CatalogLoadPolicy {
  /// Return cached rows only and never make a network request.
  cacheOnly,

  /// Return cached rows if present and refresh only when the cache is stale.
  cacheFirst,

  /// Always attempt a network refresh before returning data.
  networkOnly,
}

abstract interface class CatalogRepository {
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  });
}

class CatalogLoadResult {
  const CatalogLoadResult({required this.playlistId, required this.itemCount});

  final String? playlistId;
  final int itemCount;
}

class FixtureCatalogRepository implements CatalogRepository {
  const FixtureCatalogRepository();

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) async {
    return CatalogLoadResult(
      playlistId: playlistId,
      itemCount: fixtureCatalog.length,
    );
  }
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
    description: 'A fixture sports channel with a fake stream URL.',
  ),
  ContentItem(
    id: 'city-radio',
    title: 'City Radio',
    type: ContentType.live,
    streamUrl: 'https://example.invalid/live/city-radio.m3u8',
    group: 'Music',
    description: 'A fixture music channel for focus testing.',
  ),
  ContentItem(
    id: 'the-last-signal',
    title: 'The Last Signal',
    type: ContentType.vod,
    streamUrl: 'https://example.invalid/vod/the-last-signal.m3u8',
    group: 'Movies',
    description: 'A fixture movie entry for the VOD flow.',
  ),
  ContentItem(
    id: 'northbound',
    title: 'Northbound',
    type: ContentType.vod,
    streamUrl: 'https://example.invalid/vod/northbound.m3u8',
    group: 'Movies',
    description: 'A fixture movie entry with no external metadata.',
  ),
];
