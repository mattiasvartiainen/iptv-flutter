import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../models/content_item.dart';
import 'catalog_import_progress.dart';
import 'm3u_parser.dart';

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

abstract interface class PlaylistSource {
  Future<String> fetch(
    String url, {
    void Function(int received, int? total)? onProgress,
  });
}

class PlaylistSourceChunk {
  const PlaylistSourceChunk({
    required this.text,
    required this.received,
    required this.total,
  });

  final String text;
  final int received;
  final int? total;
}

abstract interface class StreamingPlaylistSource {
  Stream<PlaylistSourceChunk> stream(
    String url, {
    void Function(int received, int? total)? onProgress,
  });
}

class HttpPlaylistSource implements PlaylistSource, StreamingPlaylistSource {
  const HttpPlaylistSource({this.timeout = const Duration(seconds: 20)});

  final Duration timeout;

  @override
  Stream<PlaylistSourceChunk> stream(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async* {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/x-mpegURL, text/plain, */*',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'IPTV-Flutter/0.1');
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Playlist request failed: ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      var received = 0;
      await for (final text
          in response.transform(utf8.decoder).timeout(timeout)) {
        received += utf8.encode(text).length;
        onProgress?.call(received, total);
        yield PlaylistSourceChunk(text: text, received: received, total: total);
      }
    } finally {
      client.close();
    }
  }

  @override
  Future<String> fetch(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url)).timeout(timeout);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/x-mpegURL, text/plain, */*',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'IPTV-Flutter/0.1');
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Playlist request failed: ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      var received = 0;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        bytes.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      return utf8.decode(bytes.takeBytes(), allowMalformed: true);
    } finally {
      client.close();
    }
  }
}

class FakePlaylistSource implements PlaylistSource, StreamingPlaylistSource {
  const FakePlaylistSource(this.content);

  final String content;

  @override
  Stream<PlaylistSourceChunk> stream(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async* {
    onProgress?.call(content.length, content.length);
    yield PlaylistSourceChunk(
      text: content,
      received: content.length,
      total: content.length,
    );
  }

  @override
  Future<String> fetch(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    onProgress?.call(content.length, content.length);
    return content;
  }
}

class M3uCatalogRepository implements CatalogRepository {
  const M3uCatalogRepository({PlaylistSource? source})
    : source = source ?? const HttpPlaylistSource();

  final PlaylistSource source;

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) async {
    final startedAt = DateTime.now();
    onProgress?.call(
      CatalogImportProgress(
        phase: CatalogImportPhase.downloading,
        startedAt: startedAt,
      ),
    );
    final text = await source.fetch(
      playlistUrl,
      onProgress: (received, total) => onProgress?.call(
        CatalogImportProgress(
          phase: CatalogImportPhase.downloading,
          startedAt: startedAt,
          current: received,
          total: total,
        ),
      ),
    );
    final items = M3uParser().parse(text, sourceUrl: playlistUrl);
    return CatalogLoadResult(playlistId: playlistId, itemCount: items.length);
  }
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
