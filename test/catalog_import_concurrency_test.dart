import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';

/// Counts fetches and lets a test hold the response open to force overlap
/// between two concurrent [SqliteCatalogRepository.load] calls.
class _CountingPlaylistSource implements PlaylistSource {
  _CountingPlaylistSource(this.content);

  final String content;
  int fetchCount = 0;

  @override
  Future<String> fetch(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    fetchCount++;
    final completer = _pendingRelease;
    if (completer != null) {
      await completer.future;
    }
    return content;
  }

  _Gate? _pendingRelease;

  /// Makes the next fetch() wait until [release] is called.
  _Gate gate() {
    final gate = _Gate();
    _pendingRelease = gate;
    return gate;
  }
}

class _Gate {
  final Completer<void> _completer = Completer<void>();
  Future<void> get future => _completer.future;
  void release() => _completer.complete();
}

const String _oneLiveChannel = '''#EXTM3U
#EXTINF:-1 group-title="News",Alpha News
https://stream.test/alpha.m3u8
''';

void main() {
  late SqfliteDatabaseAdapter adapter;

  setUp(() {
    adapter = SqfliteDatabaseAdapter(
      fileName:
          'iptv_test_concurrency_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() => adapter.close());

  test('two concurrent load() calls for the same playlist share one import '
      'instead of racing a second transaction', () async {
    final source = _CountingPlaylistSource(_oneLiveChannel);
    final repo = SqliteCatalogRepository(
      source: source,
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
      autoStartSearchIndexWorker: false,
    );

    final gate = source.gate();
    final first = repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
    final second = repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
    gate.release();

    final results = await Future.wait([first, second]);

    expect(source.fetchCount, 1);
    expect(results[0].itemCount, 1);
    expect(results[1].itemCount, 1);
    expect(results[0].playlistId, results[1].playlistId);
  });

  test('a load() after the first completes starts a fresh import', () async {
    final source = _CountingPlaylistSource(_oneLiveChannel);
    final repo = SqliteCatalogRepository(
      source: source,
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
      autoStartSearchIndexWorker: false,
    );

    await repo.load(playlistUrl: 'https://provider.test/playlist.m3u');
    await repo.load(
      playlistUrl: 'https://provider.test/playlist.m3u',
      policy: CatalogLoadPolicy.networkOnly,
    );

    expect(source.fetchCount, 2);
  });
}
