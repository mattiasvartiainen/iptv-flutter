import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/errors/app_issue.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';

import 'support/database_adapter.dart';

class _PausedPlaylistSource implements PlaylistSource, StreamingPlaylistSource {
  final firstChunkAccepted = Completer<void>();
  final releaseNextChunk = Completer<void>();

  @override
  Future<String> fetch(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) => throw UnimplementedError();

  @override
  Stream<PlaylistSourceChunk> stream(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async* {
    yield const PlaylistSourceChunk(
      text:
          '#EXTM3U\n#EXTINF:-1 group-title="News",First\nhttps://stream.test/first.m3u8\n',
      received: 80,
      total: 160,
    );
    firstChunkAccepted.complete();
    await releaseNextChunk.future;
    yield const PlaylistSourceChunk(
      text:
          '#EXTINF:-1 group-title="News",Second\nhttps://stream.test/second.m3u8\n',
      received: 160,
      total: 160,
    );
  }
}

void main() {
  late SqfliteDatabaseAdapter adapter;

  setUp(() {
    adapter = createTestDatabaseAdapter(
      fileName:
          'iptv_test_import_sessions_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
  });

  tearDown(() => adapter.close());

  test(
    'successful import persists lifecycle, counts and stage timings',
    () async {
      const content = '''#EXTM3U
#EXTINF:-1 group-title="News",Alpha
https://stream.test/alpha.m3u8
''';
      final repository = SqliteCatalogRepository(
        source: const FakePlaylistSource(content),
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
        autoStartSearchIndexWorker: false,
      );
      final progress = <CatalogImportProgress>[];

      final result = await repository.load(
        playlistUrl: 'https://provider.test/playlist.m3u',
        policy: CatalogLoadPolicy.networkOnly,
        onProgress: progress.add,
      );

      final db = await adapter.database;
      final sessions = await db.query('import_sessions');
      final session = sessions.single;
      final timings = jsonDecode(session['stage_timings']! as String);

      expect(result.itemCount, 1);
      expect(session['playlist_id'], result.playlistId);
      expect(session['state'], 'done');
      expect(session['started_at'], isA<int>());
      expect(session['finished_at'], isA<int>());
      expect(session['bytes_received'], greaterThan(0));
      expect(session['items_parsed'], 1);
      expect(session['items_new'], 1);
      expect(
        progress.where((event) => event.phase == CatalogImportPhase.parsing),
        isNotEmpty,
      );
      expect(
        progress
            .where((event) => event.phase != CatalogImportPhase.starting)
            .every((event) => event.importSessionId == session['id']),
        isTrue,
      );
      expect(timings, contains('parsing'));
      expect(timings, contains('importing'));
    },
  );

  test(
    'failed import is recorded and does not report a successful refresh',
    () async {
      final repository = SqliteCatalogRepository(
        source: const FakePlaylistSource('#EXTM3U\n'),
        databaseAdapter: adapter,
        secretStore: InMemoryPlaylistSecretStore(),
        autoStartSearchIndexWorker: false,
      );

      await expectLater(
        repository.load(
          playlistUrl: 'https://provider.test/empty.m3u',
          policy: CatalogLoadPolicy.networkOnly,
        ),
        throwsA(isA<Exception>()),
      );

      final db = await adapter.database;
      final sessions = await db.query('import_sessions');
      expect(sessions.single['state'], 'failed');
      expect(sessions.single['finished_at'], isA<int>());
      expect(sessions.single['error'], isNotNull);
      final playlists = await db.query('playlists');
      expect(playlists.single['last_import_status'], 'failed');
    },
  );

  test(
    'startup recovery marks running and reconciling sessions aborted',
    () async {
      final db = await adapter.database;
      final startedAt = DateTime.now().millisecondsSinceEpoch;
      await db.insert('import_sessions', {
        'playlist_id': 'abandoned-a',
        'started_at': startedAt,
        'state': 'running',
      });
      await db.insert('import_sessions', {
        'playlist_id': 'abandoned-b',
        'started_at': startedAt,
        'state': 'reconciling',
      });
      await db.insert('import_sessions', {
        'playlist_id': 'finished',
        'started_at': startedAt,
        'finished_at': startedAt,
        'state': 'done',
      });

      final repository = SqliteCatalogRepository(databaseAdapter: adapter);
      await repository.recoverAbandonedImports();

      final sessions = await db.query('import_sessions', orderBy: 'id');
      expect(sessions.map((row) => row['state']), [
        'aborted',
        'aborted',
        'done',
      ]);
      expect(sessions[0]['finished_at'], isA<int>());
      expect(sessions[1]['error'], contains('interrupted'));
    },
  );

  test('cancelled stream import is finalized as cancelled', () async {
    final source = _PausedPlaylistSource();
    final repository = SqliteCatalogRepository(
      source: source,
      databaseAdapter: adapter,
      secretStore: InMemoryPlaylistSecretStore(),
      autoStartSearchIndexWorker: false,
    );
    final progress = <CatalogImportProgress>[];
    final loading = repository.load(
      playlistUrl: 'https://provider.test/cancelled.m3u',
      playlistId: 'cancelled-playlist',
      policy: CatalogLoadPolicy.networkOnly,
      onProgress: progress.add,
    );

    await source.firstChunkAccepted.future;
    await repository.cancelImport('cancelled-playlist');
    source.releaseNextChunk.complete();
    await expectLater(loading, throwsA(isA<AppIssueException>()));

    final db = await adapter.database;
    final sessions = await db.query('import_sessions');
    expect(sessions.single['state'], 'cancelled');
    expect(progress.last.phase, CatalogImportPhase.cancelled);
  });
}
