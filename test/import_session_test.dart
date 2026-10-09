import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';

import 'support/catalog_http_test_server.dart';
import 'support/database_adapter.dart';

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
      final server = await CatalogHttpTestServer.start(
        responses: {'/playlist.m3u': content},
      );
      addTearDown(server.close);
      final repository = SqliteCatalogRepository(
        databaseAdapter: adapter,
        autoStartSearchIndexWorker: false,
      );
      final progress = <CatalogImportProgress>[];

      final result = await repository.load(
        playlistId: 'v9-successful-import',
        playlistUrl: server.url('/playlist.m3u'),
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
      expect(timings, contains('total'));
    },
  );

  test(
    'failed import is recorded and does not report a successful refresh',
    () async {
      final server = await CatalogHttpTestServer.start(
        responses: {'/empty.m3u': '#EXTM3U\n'},
      );
      addTearDown(server.close);
      final repository = SqliteCatalogRepository(
        databaseAdapter: adapter,
        autoStartSearchIndexWorker: false,
      );

      await expectLater(
        repository.load(
          playlistId: 'v9-empty-import',
          playlistUrl: server.url('/empty.m3u'),
          policy: CatalogLoadPolicy.networkOnly,
        ),
        throwsA(isA<Exception>()),
      );

      final db = await adapter.database;
      final sessions = await db.query('import_sessions');
      expect(sessions.single['state'], 'failed');
      expect(sessions.single['finished_at'], isA<int>());
      expect(sessions.single['error'], isNotNull);
      expect(
        await db.query(
          'items',
          where: 'playlist_id = ?',
          whereArgs: ['v9-empty-import'],
        ),
        isEmpty,
      );
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
        'tier': 'cold_import',
      });
      await db.insert('import_sessions', {
        'playlist_id': 'abandoned-b',
        'started_at': startedAt,
        'state': 'reconciling',
        'tier': 'row_diff',
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
    final responseGate = Completer<void>();
    final server = await CatalogHttpTestServer.start(
      responses: {
        '/cancelled.m3u': '''#EXTM3U
#EXTINF:-1 group-title="News",First
https://stream.test/first.m3u8
''',
      },
      beforeResponse: responseGate.future,
    );
    addTearDown(server.close);
    final repository = SqliteCatalogRepository(
      databaseAdapter: adapter,
      autoStartSearchIndexWorker: false,
    );
    final progress = <CatalogImportProgress>[];
    final loading = repository.load(
      playlistUrl: server.url('/cancelled.m3u'),
      playlistId: 'cancelled-playlist',
      policy: CatalogLoadPolicy.networkOnly,
      onProgress: progress.add,
    );

    await server.firstRequest.future;
    await repository.cancelImport('cancelled-playlist');
    responseGate.complete();
    await expectLater(loading, throwsA(isA<Exception>()));

    final db = await adapter.database;
    final sessions = await db.query('import_sessions');
    expect(sessions.single['state'], 'cancelled');
    expect(progress.last.phase, CatalogImportPhase.cancelled);
  });
}
