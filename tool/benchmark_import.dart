// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iptv_flutter/services/catalog/catalog_importer.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/storage_contracts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'synthetic_playlist.dart';

final DatabaseFactory _benchmarkDatabaseFactory =
    _createBenchmarkDatabaseFactory();

DatabaseFactory _createBenchmarkDatabaseFactory() {
  sqfliteFfiInit();
  return databaseFactoryFfi;
}

/// Measures the v9 download, parse, diff, and import path using loopback HTTP.
///
/// Run through Flutter because the database adapter transitively imports Flutter:
///   flutter test test/benchmark/import_benchmark.dart --dart-define=BENCHMARK_COUNT=50000
Future<void> main(List<String> args) => runBenchmark(args);

Future<void> runBenchmark(List<String> args) async {
  final options = _Options.parse(args);
  final playlistText = generateSyntheticPlaylist(
    itemCount: options.count,
    seed: options.seed,
  );
  final playlistBytes = utf8.encode(playlistText);
  stdout.writeln(
    'Generating v9 playlist: ${options.count} items '
    '(seed=${options.seed}, ${(playlistBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB)...',
  );

  final scenarios = options.scenario == 'all'
      ? const ['cold', 'identical', 'churn5', 'reorder']
      : [options.scenario == 'refresh' ? 'churn5' : options.scenario];
  final reports = <Map<String, Object?>>[];
  for (final scenario in scenarios) {
    if (!const {'cold', 'identical', 'churn5', 'reorder'}.contains(scenario)) {
      throw ArgumentError('Unknown v9 benchmark scenario: $scenario');
    }
    final report = await _runScenario(
      scenario: scenario,
      playlistText: playlistText,
      options: options,
    );
    reports.add(report);
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  }

  final output = const JsonEncoder.withIndent('  ').convert({
    'engine': 'v9',
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'count': options.count,
    'seed': options.seed,
    'network': 'loopback_http',
    'scenarios': reports,
  });
  stdout.writeln('=== v9 benchmark JSON ===');
  stdout.writeln(output);
  if (options.outputPath case final outputPath?) {
    final file = File(outputPath);
    await file.create(recursive: true);
    await file.writeAsString('$output\n');
    stdout.writeln('Wrote v9 benchmark report: ${file.path}');
  }
}

Future<Map<String, Object?>> _runScenario({
  required String scenario,
  required String playlistText,
  required _Options options,
}) async {
  var responseBody = playlistText;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final playlistUrl = 'http://127.0.0.1:${server.port}/playlist.m3u';
  unawaited(_serve(server, () => utf8.encode(responseBody)));

  final fileName =
      'iptv_v9_benchmark_${scenario}_${DateTime.now().microsecondsSinceEpoch}.sqlite';
  final adapter = SqfliteDatabaseAdapter(
    databaseFactory: _benchmarkDatabaseFactory,
    fileName: fileName,
  );
  final importer = CatalogImporter(databaseAdapter: adapter);
  final playlistId = 'benchmark-v9-$scenario';
  try {
    final cold = await _runImport(
      importer: importer,
      databaseAdapter: adapter,
      playlistId: playlistId,
      playlistUrl: playlistUrl,
      playlistText: playlistText,
      label: '$scenario / cold',
    );
    Map<String, Object?>? refresh;
    if (scenario != 'cold') {
      responseBody = switch (scenario) {
        'identical' => playlistText,
        'churn5' => churnSyntheticPlaylist(playlistText),
        'reorder' => reorderSyntheticPlaylist(playlistText),
        _ => playlistText,
      };
      refresh = await _runImport(
        importer: importer,
        databaseAdapter: adapter,
        playlistId: playlistId,
        playlistUrl: playlistUrl,
        playlistText: responseBody,
        label: '$scenario / refresh',
      );
    }
    return {'scenario': scenario, 'cold': cold, 'refresh': ?refresh};
  } finally {
    await server.close(force: true);
    final path = (await adapter.database).path;
    await adapter.close();
    if (!options.keepDb) {
      await _deleteDatabaseFile(path);
    } else {
      stdout.writeln('Kept v9 database file: $path');
    }
  }
}

Future<Map<String, Object?>> _runImport({
  required CatalogImporter importer,
  required DatabaseAdapter databaseAdapter,
  required String playlistId,
  required String playlistUrl,
  required String playlistText,
  required String label,
}) async {
  final startRss = ProcessInfo.currentRss;
  final peakRssBefore = ProcessInfo.maxRss;
  final stopwatch = Stopwatch()..start();
  final eventLoopProbe = _EventLoopProbe()..start();
  final bytes = utf8.encode(playlistText);
  final result = await importer.importPlaylist(
    playlistId: playlistId,
    playlistUrl: playlistUrl,
  );
  stopwatch.stop();
  eventLoopProbe.stop();

  final db = await databaseAdapter.database;
  final sessions = await db.query(
    'import_sessions',
    columns: const ['state', 'tier'],
    where: 'id = ?',
    whereArgs: [result.importSessionId],
  );
  final session = sessions.single;
  final report = <String, Object?>{
    'label': label,
    'items': result.itemCount,
    'new': session['tier'] == 'cold_import'
        ? result.itemCount
        : result.newCount,
    'changed': result.changedCount,
    'moved': result.movedCount,
    'removed': result.removedCount,
    'rejected': result.rejectedCount,
    'bytes': bytes.length,
    'network': 'loopback_http',
    'bodyHash': result.bodyHash,
    'state': session['state'],
    'wallMs': stopwatch.elapsedMilliseconds,
    'rssStartBytes': startRss,
    'rssEndBytes': ProcessInfo.currentRss,
    'rssPeakBytes': ProcessInfo.maxRss,
    'rssPeakDeltaBytes': _max(0, ProcessInfo.maxRss - peakRssBefore),
    'eventLoopMaxDelayMs': eventLoopProbe.maxDelay.inMilliseconds,
    'eventLoopDelayedTicks': eventLoopProbe.delayedTicks,
  };
  stdout.writeln('  -> $report');
  return report;
}

Future<void> _serve(HttpServer server, List<int> Function() body) async {
  await for (final request in server) {
    final bytes = body();
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

class _EventLoopProbe {
  static const _tick = Duration(milliseconds: 16);

  Timer? _timer;
  Stopwatch? _clock;
  Duration _nextTick = Duration.zero;
  Duration maxDelay = Duration.zero;
  int delayedTicks = 0;

  void start() {
    _clock = Stopwatch()..start();
    _timer = Timer.periodic(_tick, (_) {
      final elapsed = _clock!.elapsed;
      final delay = elapsed - _nextTick - _tick;
      if (delay > maxDelay) maxDelay = delay;
      if (delay >= const Duration(milliseconds: 100)) delayedTicks++;
      _nextTick += _tick;
    });
  }

  void stop() {
    _timer?.cancel();
    _clock?.stop();
  }
}

class _Options {
  const _Options({
    required this.count,
    required this.seed,
    required this.scenario,
    required this.keepDb,
    required this.outputPath,
  });

  final int count;
  final int seed;
  final String scenario;
  final bool keepDb;
  final String? outputPath;

  static _Options parse(List<String> args) {
    var count = 100000;
    var seed = 42;
    var scenario = 'cold';
    var keepDb = false;
    String? outputPath;
    for (final arg in args) {
      if (arg.startsWith('--count=')) {
        count = int.parse(arg.substring('--count='.length));
      } else if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
      } else if (arg.startsWith('--scenario=')) {
        scenario = arg.substring('--scenario='.length);
      } else if (arg == '--refresh') {
        scenario = 'churn5';
      } else if (arg == '--all') {
        scenario = 'all';
      } else if (arg == '--keep-db') {
        keepDb = true;
      } else if (arg.startsWith('--out=')) {
        outputPath = arg.substring('--out='.length);
      }
    }
    return _Options(
      count: count,
      seed: seed,
      scenario: scenario,
      keepDb: keepDb,
      outputPath: outputPath,
    );
  }
}

int _max(int left, int right) => left > right ? left : right;
