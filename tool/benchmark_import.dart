import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';

import 'synthetic_playlist.dart';

/// Phase 0 measurement harness: exercises the real download -> parse ->
/// import pipeline against a synthetic playlist and reports wall-clock
/// timings + RSS, so later perf changes can be judged against a number
/// instead of "feels faster". See docs/improvements-1.md.
///
/// This file depends on `package:iptv_flutter` code that transitively
/// imports `package:flutter/foundation.dart`, so it must run under a
/// Flutter-aware Dart VM — plain `dart run`/`flutter pub run` fail to
/// resolve `dart:ui` for it. Invoke it via the `flutter test` runner
/// instead, see test/benchmark/import_benchmark.dart:
///   flutter test test/benchmark/import_benchmark.dart --dart-define=BENCHMARK_COUNT=200000
Future<void> main(List<String> args) => runBenchmark(args);

Future<void> runBenchmark(List<String> args) async {
  final options = _Options.parse(args);
  stdout.writeln(
    'Generating synthetic playlist: ${options.count} items (seed=${options.seed})...',
  );
  final playlistText = generateSyntheticPlaylist(
    itemCount: options.count,
    seed: options.seed,
  );
  final playlistBytes = utf8.encode(playlistText);
  stdout.writeln(
    '  ${(playlistBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB of M3U text.',
  );

  HttpServer? server;
  String playlistUrl;
  if (options.useNetwork) {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    playlistUrl = 'http://127.0.0.1:${server.port}/playlist.m3u';
    unawaited(_serve(server, playlistBytes));
  } else {
    playlistUrl = 'memory://playlist.m3u';
  }

  final dbFileName =
      'iptv_benchmark_${DateTime.now().microsecondsSinceEpoch}.sqlite';
  final adapter = SqfliteDatabaseAdapter(fileName: dbFileName);
  final source = options.useNetwork
      ? const HttpPlaylistSource()
      : FakePlaylistSource(playlistText);
  final repository = SqliteCatalogRepository(
    source: source,
    databaseAdapter: adapter,
    autoStartSearchIndexWorker: false,
  );

  try {
    final coldRun = await _runImport(
      repository: repository,
      playlistUrl: playlistUrl,
      playlistId: 'benchmark-playlist',
      label: 'Cold import',
    );
    _printRun(coldRun);

    if (options.refresh) {
      // A second load() against the same (or slightly churned) playlist
      // is the realistic "user clicked Refresh" case: the DB already has
      // ~all rows, so this exercises the existing-row preload + diff path
      // that a cold import never touches.
      if (options.useNetwork) {
        final churned = churnSyntheticPlaylist(playlistText);
        server!.close(force: true);
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        playlistUrl = 'http://127.0.0.1:${server.port}/playlist.m3u';
        unawaited(_serve(server, utf8.encode(churned)));
      }
      final warmRun = await _runImport(
        repository: repository,
        playlistUrl: playlistUrl,
        playlistId: 'benchmark-playlist',
        label: 'Warm refresh (5% churn)',
      );
      _printRun(warmRun);
    }
  } finally {
    await server?.close(force: true);
    final dbPath = (await adapter.database).path;
    await adapter.close();
    if (!options.keepDb) {
      await _deleteDatabaseFile(dbPath);
    } else {
      stdout.writeln('Kept database file: $dbPath');
    }
  }
}

class _RunResult {
  _RunResult({
    required this.label,
    required this.itemCount,
    required this.totalElapsed,
    required this.downloadElapsed,
    required this.importElapsed,
    required this.searchIndexElapsed,
    required this.searchIndexRows,
    required this.rssAtStart,
    required this.rssAtEnd,
    required this.maxRss,
  });

  final String label;
  final int itemCount;
  final Duration totalElapsed;
  final Duration? downloadElapsed;
  final Duration? importElapsed;
  final Duration searchIndexElapsed;
  final int searchIndexRows;
  final int rssAtStart;
  final int rssAtEnd;
  final int maxRss;
}

Future<_RunResult> _runImport({
  required SqliteCatalogRepository repository,
  required String playlistUrl,
  required String playlistId,
  required String label,
}) async {
  final rssAtStart = ProcessInfo.currentRss;
  final stopwatch = Stopwatch()..start();

  SqliteCatalogRepository.onImportStageTiming = (stage, elapsed) =>
      stdout.writeln('     [$label] $stage: ${elapsed.inMilliseconds} ms');
  SqliteCatalogRepository.onStagingReconcileFallback = (error) =>
      stderr.writeln('     [$label] SET-BASED RECONCILE FAILED: $error');

  DateTime? downloadStartedAt;
  DateTime? importStartedAt;
  DateTime? lastEventAt;

  final result = await repository.load(
    playlistUrl: playlistUrl,
    playlistId: playlistId,
    playlistName: 'Benchmark Playlist',
    policy: CatalogLoadPolicy.networkOnly,
    onProgress: (progress) {
      lastEventAt = DateTime.now();
      if (progress.phase == CatalogImportPhase.downloading) {
        downloadStartedAt ??= progress.startedAt;
      } else if (progress.phase == CatalogImportPhase.importing) {
        importStartedAt ??= lastEventAt;
      }
    },
  );

  stopwatch.stop();

  final downloadElapsed = (downloadStartedAt != null && importStartedAt != null)
      ? importStartedAt!.difference(downloadStartedAt!)
      : null;
  final importElapsed = (importStartedAt != null && lastEventAt != null)
      ? lastEventAt!.difference(importStartedAt!)
      : null;

  stdout.writeln(
    '  -> imported ${result.itemCount} items for playlist ${result.playlistId}',
  );

  // The background index worker keeps running after load() returns, so its
  // cost is invisible to the user as "import time" but very visible as a
  // device that stays busy. Drain it here and report it separately.
  final indexStopwatch = Stopwatch()..start();
  final indexedRows = await repository.processSearchIndexQueue(
    playlistId: result.playlistId,
  );
  indexStopwatch.stop();

  final rssAtEnd = ProcessInfo.currentRss;

  return _RunResult(
    label: label,
    itemCount: result.itemCount,
    totalElapsed: stopwatch.elapsed,
    downloadElapsed: downloadElapsed,
    importElapsed: importElapsed,
    searchIndexElapsed: indexStopwatch.elapsed,
    searchIndexRows: indexedRows,
    rssAtStart: rssAtStart,
    rssAtEnd: rssAtEnd,
    maxRss: ProcessInfo.maxRss,
  );
}

void _printRun(_RunResult run) {
  String fmtDuration(Duration? d) =>
      d == null ? 'n/a' : '${d.inMilliseconds} ms';
  String fmtMb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  stdout.writeln('--- ${run.label} ---');
  stdout.writeln('  items:            ${run.itemCount}');
  stdout.writeln('  total wall time:  ${fmtDuration(run.totalElapsed)}');
  stdout.writeln('  ~download+parse:  ${fmtDuration(run.downloadElapsed)}');
  stdout.writeln('  ~import (db):     ${fmtDuration(run.importElapsed)}');
  stdout.writeln(
    '  search index:     ${fmtDuration(run.searchIndexElapsed)} '
    '(${run.searchIndexRows} rows)',
  );
  stdout.writeln('  RSS before:       ${fmtMb(run.rssAtStart)}');
  stdout.writeln('  RSS after:        ${fmtMb(run.rssAtEnd)}');
  stdout.writeln('  RSS peak (proc):  ${fmtMb(run.maxRss)}');
  stdout.writeln('');
}

Future<void> _serve(HttpServer server, List<int> bytes) async {
  await for (final request in server) {
    request.response.headers.contentType = ContentType(
      'application',
      'x-mpegURL',
    );
    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    await request.response.close();
  }
}

Future<void> _deleteDatabaseFile(String path) async {
  try {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  } catch (error) {
    stderr.writeln('Warning: could not clean up benchmark database: $error');
  }
}

class _Options {
  _Options({
    required this.count,
    required this.seed,
    required this.refresh,
    required this.keepDb,
    required this.useNetwork,
  });

  final int count;
  final int seed;
  final bool refresh;
  final bool keepDb;
  final bool useNetwork;

  static _Options parse(List<String> args) {
    var count = 100000;
    var seed = 42;
    var refresh = false;
    var keepDb = false;
    var useNetwork = true;
    for (final arg in args) {
      if (arg.startsWith('--count=')) {
        count = int.parse(arg.substring('--count='.length));
      } else if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
      } else if (arg == '--refresh') {
        refresh = true;
      } else if (arg == '--keep-db') {
        keepDb = true;
      } else if (arg == '--no-network') {
        useNetwork = false;
      }
    }
    return _Options(
      count: count,
      seed: seed,
      refresh: refresh,
      keepDb: keepDb,
      useNetwork: useNetwork,
    );
  }
}
