import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_coordinator.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_progress.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_protocol.dart'
    show CatalogImportCancelledException;
import 'package:iptv_flutter/services/catalog/catalog_import_worker.dart';
import 'package:iptv_flutter/services/catalog/catalog_importer.dart';
import 'package:iptv_flutter/services/catalog/catalog_search_indexer.dart';
import 'package:iptv_flutter/services/telemetry/app_telemetry.dart';

import '../../../tool/synthetic_playlist.dart';
import '../../support/database_adapter.dart';

void main() {
  test(
    'progress is throttled and outside callbacks retain the root context',
    () async {
      final telemetry = RecordingTelemetry();
      final coordinator = CatalogImportCoordinator(telemetry: telemetry);
      final pending = Completer<int>();
      late CatalogImportReporter reporter;
      final result = coordinator.run<int>(
        playlistId: 'throttle',
        operation: (value) {
          reporter = value;
          for (var count = 1; count <= 1000; count++) {
            value.emit(
              CatalogImportProgress(
                phase: CatalogImportPhase.parsing,
                startedAt: value.startedAt,
                parsedItems: count,
              ),
            );
          }
          return pending.future;
        },
      );
      expect(telemetry.events, hasLength(1));
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      reporter.emit(
        CatalogImportProgress(
          phase: CatalogImportPhase.indexing,
          startedAt: reporter.startedAt,
          currentOperation: 'queued',
        ),
      );
      expect(telemetry.events, hasLength(2));
      expect(telemetry.events.last.$2['parsed'], 1000);
      pending.complete(7);
      expect(await result, 7);
      expect(telemetry.events.last.$2['phase'], 'completed');
      expect(telemetry.events.last.$2['parsed'], 1000);
      expect(
        telemetry.events.every((event) => event.$3 == 'playlist.import'),
        isTrue,
      );
      expect(telemetry.active, isEmpty);
    },
  );

  test('cancelling before headers closes the pending header span', () async {
    final telemetry = RecordingTelemetry();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requested = Completer<void>();
    server.listen((request) => requested.complete());
    final worker = await CatalogImportWorker.start(
      playlistId: 'pending',
      playlistUrl: 'http://127.0.0.1:${server.port}/secret',
      telemetry: telemetry,
      selectRows: (_) async => [],
      onRows: (_, rows) async {},
    );
    final check = expectLater(
      worker.done,
      throwsA(isA<CatalogImportCancelledException>()),
    );
    await requested.future;
    await worker.cancel();
    await check;
    expect(telemetry.failed, contains('http.playlist.headers'));
    expect(telemetry.active, isEmpty);
  });

  test(
    'synthetic cold/warm imports trace SQLite callbacks and index work',
    () async {
      final adapter = createTestDatabaseAdapter(
        fileName:
            'import_telemetry_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      );
      addTearDown(adapter.close);
      final telemetry = RecordingTelemetry();
      final original = generateSyntheticPlaylist(itemCount: 24);
      var body = original;
      final server = await _serve(() => body);
      addTearDown(() => server.close(force: true));
      final importer = CatalogImporter(
        databaseAdapter: adapter,
        telemetry: telemetry,
      );
      final url =
          'http://127.0.0.1:${server.port}/private-user/private-password';
      final cold = await importer.importPlaylist(
        playlistId: 'synthetic',
        playlistUrl: url,
      );
      expect(cold.itemCount, 24);
      final indexer = SqliteCatalogSearchIndexer(
        databaseAdapter: adapter,
        telemetry: telemetry,
        autoStartWorker: false,
      );
      await indexer.resumePendingIndexing();
      await indexer.status('synthetic');
      expect(await indexer.processQueue(playlistId: 'synthetic'), 24);
      body = reorderSyntheticPlaylist(original);
      final warm = await importer.importPlaylist(
        playlistId: 'synthetic',
        playlistUrl: url,
      );
      expect(warm.changedCount, 0);
      expect(warm.movedCount, greaterThan(0));
      body = generateSyntheticPlaylist(
        itemCount: 20,
      ).replaceAll('tvg-id="', 'tvg-name="changed" tvg-id="');
      final removed = await importer.importPlaylist(
        playlistId: 'synthetic',
        playlistUrl: url,
      );
      expect(removed.removedCount, 4);
      expect(removed.changedCount, greaterThan(0));
      expect(
        telemetry.operations.where((name) => name == 'playlist.import'),
        hasLength(3),
      );
      expect(
        telemetry.operations,
        containsAll([
          'playlist.import.cold',
          'playlist.import.warm',
          'http.playlist.headers',
          'db.import.diff',
          'db.import.write',
          'db.import.finalize',
          'db.index.recovery',
          'db.index.status',
          'db.index.process_queue',
          'db.index.batch',
        ]),
      );
      expect(
        telemetry.parents
            .where((entry) => entry.$1 == 'db.import.write')
            .every(
              (entry) =>
                  entry.$2 == 'playlist.import.cold' ||
                  entry.$2 == 'playlist.import.warm',
            ),
        isTrue,
      );
      final counts = telemetry.events
          .where((event) => event.$1 == 'playlist.import.counts')
          .toList();
      expect(counts.first.$2['new'], 24);
      expect(counts[1].$2['moved'], greaterThan(0));
      expect(counts.last.$2['changed'], removed.changedCount);
      expect(counts.last.$2['removed'], 4);
      expect(counts.every((event) => (event.$2['bytes']! as int) > 0), isTrue);
      final diagnostics = telemetry.events.where(
        (event) => event.$1 == 'playlist.import.worker',
      );
      expect(diagnostics, hasLength(3));
      expect(
        diagnostics.every(
          (event) =>
              (event.$2['parsingCpuUs']! as int) > 0 &&
              (event.$2['acknowledgementWaitUs']! as int) > 0,
        ),
        isTrue,
      );
      expect(telemetry.active, isEmpty);
      final encoded = jsonEncode(
        telemetry.events.map((event) => event.$2).toList(),
      );
      expect(encoded, isNot(contains('private-password')));
      expect(encoded, isNot(contains('https://')));
      expect(encoded, isNot(contains('Movie Title')));
    },
  );

  test('failed headers are observed and cleanup closes spans', () async {
    final adapter = createTestDatabaseAdapter(
      fileName:
          'import_telemetry_failure_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(adapter.close);
    final telemetry = RecordingTelemetry();
    final server = await _serve(() => '', status: 503);
    addTearDown(() => server.close(force: true));
    await expectLater(
      CatalogImporter(
        databaseAdapter: adapter,
        telemetry: telemetry,
      ).importCold(
        playlistId: 'failure',
        playlistUrl: 'http://127.0.0.1:${server.port}/secret',
      ),
      throwsA(isA<CatalogImportWorkerException>()),
    );
    expect(
      telemetry.events
          .firstWhere((event) => event.$1 == 'http.playlist.status')
          .$2['http.response.status_code'],
      503,
    );
    expect(telemetry.operations, contains('db.import.cleanup'));
    expect(telemetry.failed, contains('http.playlist.headers'));
    expect(telemetry.events.last.$2['phase'], 'failed');
    expect(telemetry.active, isEmpty);
  });

  test('worker callback measures preserve original exceptions', () async {
    final server = await _serve(() => generateSyntheticPlaylist(itemCount: 1));
    addTearDown(() => server.close(force: true));
    for (final failSelection in [true, false]) {
      final telemetry = RecordingTelemetry();
      final error = StateError('private callback exception');
      final worker = await CatalogImportWorker.start(
        playlistId: 'callback',
        playlistUrl: 'http://127.0.0.1:${server.port}/secret',
        telemetry: telemetry,
        selectRows: (batch) async {
          if (failSelection) throw error;
          return [0];
        },
        onRows: (_, rows) async => throw error,
      );
      await expectLater(worker.done, throwsA(same(error)));
      expect(
        telemetry.failed,
        contains(failSelection ? 'db.import.diff' : 'db.import.write'),
      );
      expect(telemetry.active, isEmpty);
    }
  });

  test(
    'dedup shares a root; heartbeat and cancellation retain context',
    () async {
      final telemetry = RecordingTelemetry();
      final coordinator = CatalogImportCoordinator(telemetry: telemetry);
      final pending = Completer<int>();
      final error = const CatalogImportCancelledException();
      final first = coordinator.run<int>(
        playlistId: 'test',
        operation: (reporter) {
          reporter.attachSession(42);
          reporter.emit(
            CatalogImportProgress(
              phase: CatalogImportPhase.parsing,
              startedAt: reporter.startedAt,
              parsedItems: 17,
              currentOperation: 'parsing',
            ),
          );
          reporter.onCancel(() => pending.completeError(error));
          return pending.future;
        },
      );
      final second = coordinator.run<int>(
        playlistId: 'test',
        operation: (_) async => 9,
      );
      final firstCheck = expectLater(first, throwsA(same(error)));
      final secondCheck = expectLater(second, throwsA(same(error)));
      addTearDown(() => coordinator.cancel('test'));
      expect(telemetry.operations, ['playlist.import']);
      expect(telemetry.events.single.$2['phase'], 'starting');
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(telemetry.events.last.$1, 'playlist.import.heartbeat');
      expect(telemetry.events.last.$2['parsed'], 17);
      expect(telemetry.events.last.$2['importSessionId'], 42);
      await coordinator.cancel('test');
      await firstCheck;
      await secondCheck;
      expect(telemetry.events.last.$2['phase'], 'cancelled');
      expect(
        telemetry.events.every((event) => event.$3 == 'playlist.import'),
        isTrue,
      );
      final count = telemetry.events.length;
      await Future<void>.delayed(const Duration(milliseconds: 5100));
      expect(telemetry.events, hasLength(count));
    },
  );
}

class RecordingTelemetry extends AppTelemetry {
  static final _key = Object();
  final operations = <String>[];
  final events = <(String, Map<String, Object?>, String?)>[];
  final parents = <(String, String?)>[];
  final active = <Object>{};
  final failed = <String>[];

  @override
  Future<T> measure<T>(
    String operation,
    Future<T> Function() action, {
    Map<String, Object?> attributes = const {},
  }) async {
    operations.add(operation);
    parents.add((operation, Zone.current[_key] as String?));
    final token = Object();
    active.add(token);
    try {
      return await runZoned(action, zoneValues: {_key: operation});
    } catch (error) {
      failed.add(operation);
      rethrow;
    } finally {
      active.remove(token);
    }
  }

  @override
  void event(String name, {Map<String, Object?> attributes = const {}}) {
    events.add((name, attributes, Zone.current[_key] as String?));
  }

  @override
  void failure(String name, Object error, StackTrace stackTrace) {}
}

Future<HttpServer> _serve(String Function() body, {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final bytes = utf8.encode(body());
    request.response.statusCode = status;
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  });
  return server;
}
