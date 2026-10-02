import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/catalog/catalog_importer.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_repository.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/storage_contracts.dart';

import 'synthetic_playlist.dart';

/// Phase 0 measurement harness for the current download -> parse -> import
/// pipeline. It is intentionally kept separate from production diagnostics so
/// benchmark output remains stable while the import implementation changes.
///
/// Run through Flutter because the repository transitively imports Flutter:
///   flutter test test/benchmark/import_benchmark.dart --dart-define=BENCHMARK_COUNT=200000 --dart-define=BENCHMARK_SCENARIO=all
Future<void> main(List<String> args) => runBenchmark(args);

Future<void> runBenchmark(List<String> args) async {
  final options = _Options.parse(args);
  if (options.engine == 'v9') {
    await _runV9Benchmark(options);
    return;
  }
  final playlistText = generateSyntheticPlaylist(
    itemCount: options.count,
    seed: options.seed,
  );
  final playlistBytes = utf8.encode(playlistText);
  stdout.writeln(
    'Generating synthetic playlist: ${options.count} items '
    '(seed=${options.seed}, ${(playlistBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB)...',
  );

  final results = <Map<String, Object?>>[];
  if (options.scenario == 'all') {
    results.add(
      await _runAllScenarios(playlistText: playlistText, options: options),
    );
  } else {
    final scenario = options.scenario == 'refresh'
        ? 'churn5'
        : options.scenario;
    results.add(
      await _runScenario(
        scenario: scenario,
        playlistText: playlistText,
        options: options,
      ),
    );
  }

  final report = <String, Object?>{
    'engine': options.engine,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'count': options.count,
    'seed': options.seed,
    'network': options.useNetwork,
    'scenarios': results,
  };
  final encoded = const JsonEncoder.withIndent('  ').convert(report);
  stdout.writeln('=== Phase 0 baseline JSON ===');
  stdout.writeln(encoded);
  if (options.outputPath != null) {
    final output = File(options.outputPath!);
    await output.create(recursive: true);
    await output.writeAsString('$encoded\n');
    stdout.writeln('Wrote baseline report: ${output.path}');
  }
}

Future<void> _runV9Benchmark(_Options options) async {
  final playlistText = generateSyntheticPlaylist(
    itemCount: options.count,
    seed: options.seed,
  );
  final playlistBytes = utf8.encode(playlistText);
  stdout.writeln(
    'Generating v9 playlist: ${options.count} items '
    '(seed=${options.seed}, ${(playlistBytes.length / (1024 * 1024)).toStringAsFixed(1)} MB)...',
  );

  final reports = <Map<String, Object?>>[];
  final scenarios = options.scenario == 'all'
      ? const ['cold', 'identical', 'churn5', 'reorder']
      : [options.scenario == 'refresh' ? 'churn5' : options.scenario];
  for (final scenario in scenarios) {
    if (!const {'cold', 'identical', 'churn5', 'reorder'}.contains(scenario)) {
      throw ArgumentError('Unknown v9 benchmark scenario: $scenario');
    }
    final report = await _runV9Scenario(
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
    'network': options.useNetwork,
    'scenarios': reports,
  });
  stdout.writeln('=== v9 benchmark JSON ===');
  stdout.writeln(output);
  if (options.outputPath != null) {
    final file = File(options.outputPath!);
    await file.create(recursive: true);
    await file.writeAsString('$output\n');
    stdout.writeln('Wrote v9 benchmark report: ${file.path}');
  }
}

Future<Map<String, Object?>> _runV9Scenario({
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
  final adapter = SqfliteDatabaseAdapter(fileName: fileName);
  final importer = CatalogImporter(databaseAdapter: adapter);
  final playlistId = 'benchmark-v9-$scenario';
  try {
    final cold = await _runV9Import(
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
      refresh = await _runV9Import(
        importer: importer,
        databaseAdapter: adapter,
        playlistId: playlistId,
        playlistUrl: playlistUrl,
        playlistText: responseBody,
        label: '$scenario / refresh',
      );
    }
    return {
      'scenario': scenario,
      'cold': cold,
      if (refresh != null) 'refresh': refresh,
    };
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

Future<Map<String, Object?>> _runV9Import({
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
  final body = utf8.encode(playlistText);
  final result = await importer.importPlaylist(
    playlistId: playlistId,
    playlistUrl: playlistUrl,
  );
  stopwatch.stop();
  eventLoopProbe.stop();
  final endRss = ProcessInfo.currentRss;
  final db = await databaseAdapter.database;
  final sessions = await db.query(
    'import_sessions',
    columns: const ['items_parsed', 'items_rejected', 'state', 'tier'],
    where: 'id = ?',
    whereArgs: [result.importSessionId],
  );
  final session = sessions.single;
  final report = <String, Object?>{
    'label': label,
    'items': result.itemCount,
    'new': result.newCount == 0 && session['tier'] == 'cold_import'
        ? result.itemCount
        : result.newCount,
    'changed': result.changedCount,
    'moved': result.movedCount,
    'removed': result.removedCount,
    'rejected': result.rejectedCount,
    'bytes': body.length,
    'network': 'loopback_http',
    'bodyHash': result.bodyHash,
    'state': session['state'],
    'wallMs': stopwatch.elapsedMilliseconds,
    'rssStartBytes': startRss,
    'rssEndBytes': endRss,
    'rssPeakBytes': ProcessInfo.maxRss,
    'rssPeakDeltaBytes': max(0, ProcessInfo.maxRss - peakRssBefore),
    'eventLoopMaxDelayMs': eventLoopProbe.maxDelay.inMilliseconds,
    'eventLoopDelayedTicks': eventLoopProbe.delayedTicks,
  };
  stdout.writeln('  -> $report');
  return report;
}

Future<Map<String, Object?>> _runAllScenarios({
  required String playlistText,
  required _Options options,
}) async {
  final source = _MutablePlaylistSource(playlistText);
  HttpServer? server;
  final playlistUrl = options.useNetwork
      ? 'http://127.0.0.1:${(server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)).port}/playlist.m3u'
      : 'memory://playlist.m3u';
  if (server != null) {
    unawaited(_serve(server, () => utf8.encode(source.content)));
  }
  final dbFileName =
      'iptv_benchmark_all_${DateTime.now().microsecondsSinceEpoch}.sqlite';
  final adapter = SqfliteDatabaseAdapter(fileName: dbFileName);
  final repository = SqliteCatalogRepository(
    source: options.useNetwork ? const HttpPlaylistSource() : source,
    databaseAdapter: adapter,
    autoStartSearchIndexWorker: false,
  );

  try {
    final coldRun = await _runImport(
      repository: repository,
      playlistUrl: playlistUrl,
      playlistId: 'benchmark-playlist',
      label: 'all / cold',
    );
    _printRun(coldRun);
    final refreshes = <String, Object?>{};
    for (final scenario in const ['identical', 'churn5', 'reorder']) {
      source.content = switch (scenario) {
        'identical' => playlistText,
        'churn5' => churnSyntheticPlaylist(playlistText),
        'reorder' => reorderSyntheticPlaylist(playlistText),
        _ => playlistText,
      };
      final refreshRun = await _runImport(
        repository: repository,
        playlistUrl: playlistUrl,
        playlistId: 'benchmark-playlist',
        label: 'all / $scenario refresh',
      );
      _printRun(refreshRun);
      refreshes[scenario] = refreshRun.toJson();
    }
    return <String, Object?>{
      'scenario': 'all',
      'cold': coldRun.toJson(),
      'refreshes': refreshes,
    };
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

Future<Map<String, Object?>> _runScenario({
  required String scenario,
  required String playlistText,
  required _Options options,
}) async {
  final body = switch (scenario) {
    'cold' => playlistText,
    'identical' => playlistText,
    'churn5' => churnSyntheticPlaylist(playlistText),
    'reorder' => reorderSyntheticPlaylist(playlistText),
    _ => throw ArgumentError('Unknown benchmark scenario: $scenario'),
  };
  final source = _MutablePlaylistSource(playlistText);
  HttpServer? server;
  String playlistUrl;
  if (options.useNetwork) {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    playlistUrl = 'http://127.0.0.1:${server.port}/playlist.m3u';
    unawaited(_serve(server, () => utf8.encode(source.content)));
  } else {
    playlistUrl = 'memory://playlist.m3u';
  }

  final dbFileName =
      'iptv_benchmark_${scenario}_${DateTime.now().microsecondsSinceEpoch}.sqlite';
  final adapter = SqfliteDatabaseAdapter(fileName: dbFileName);
  final repository = SqliteCatalogRepository(
    source: options.useNetwork ? const HttpPlaylistSource() : source,
    databaseAdapter: adapter,
    autoStartSearchIndexWorker: false,
  );

  try {
    final coldRun = await _runImport(
      repository: repository,
      playlistUrl: playlistUrl,
      playlistId: 'benchmark-playlist',
      label: '$scenario / cold',
    );
    _printRun(coldRun);

    _RunResult? refreshRun;
    if (scenario != 'cold') {
      source.content = body;
      refreshRun = await _runImport(
        repository: repository,
        playlistUrl: playlistUrl,
        playlistId: 'benchmark-playlist',
        label: '$scenario / refresh',
      );
      _printRun(refreshRun);
    }

    return <String, Object?>{
      'scenario': scenario,
      'cold': coldRun.toJson(),
      if (refreshRun != null) 'refresh': refreshRun.toJson(),
    };
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
    required this.stageTimings,
    required this.maxEventLoopDelay,
    required this.delayedTicks,
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
  final Map<String, Duration> stageTimings;
  final Duration maxEventLoopDelay;
  final int delayedTicks;

  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'items': itemCount,
    'totalMs': totalElapsed.inMilliseconds,
    'downloadAndParseMs': downloadElapsed?.inMilliseconds,
    'importMs': importElapsed?.inMilliseconds,
    'searchIndexMs': searchIndexElapsed.inMilliseconds,
    'searchIndexRows': searchIndexRows,
    'rssStartBytes': rssAtStart,
    'rssEndBytes': rssAtEnd,
    'rssPeakBytes': maxRss,
    'rssPeakDeltaBytes': max(0, maxRss - rssAtStart),
    'stageMs': <String, int>{
      for (final entry in stageTimings.entries)
        entry.key: entry.value.inMilliseconds,
    },
    'eventLoopMaxDelayMs': maxEventLoopDelay.inMilliseconds,
    'eventLoopDelayedTicks': delayedTicks,
  };
}

Future<_RunResult> _runImport({
  required SqliteCatalogRepository repository,
  required String playlistUrl,
  required String playlistId,
  required String label,
}) async {
  final rssAtStart = ProcessInfo.currentRss;
  final stopwatch = Stopwatch()..start();
  final stageTimings = <String, Duration>{};
  final eventLoopProbe = _EventLoopProbe()..start();

  SqliteCatalogRepository.onImportStageTiming = (stage, elapsed) {
    stageTimings[stage] = elapsed;
    stdout.writeln('     [$label] $stage: ${elapsed.inMilliseconds} ms');
  };
  SqliteCatalogRepository.onStagingReconcileFallback = (error) =>
      stderr.writeln('     [$label] SET-BASED RECONCILE FAILED: $error');

  DateTime? downloadStartedAt;
  DateTime? importStartedAt;
  DateTime? lastEventAt;

  try {
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
    final downloadElapsed =
        (downloadStartedAt != null && importStartedAt != null)
        ? importStartedAt!.difference(downloadStartedAt!)
        : null;
    final importElapsed = (importStartedAt != null && lastEventAt != null)
        ? lastEventAt!.difference(importStartedAt!)
        : null;

    stdout.writeln(
      '  -> imported ${result.itemCount} items for playlist ${result.playlistId}',
    );

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
      stageTimings: Map.unmodifiable(stageTimings),
      maxEventLoopDelay: eventLoopProbe.maxDelay,
      delayedTicks: eventLoopProbe.delayedTicks,
    );
  } finally {
    eventLoopProbe.stop();
    SqliteCatalogRepository.onImportStageTiming = null;
    SqliteCatalogRepository.onStagingReconcileFallback = null;
  }
}

void _printRun(_RunResult run) {
  String fmtDuration(Duration? duration) =>
      duration == null ? 'n/a' : '${duration.inMilliseconds} ms';
  String fmtMb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  stdout.writeln('--- ${run.label} ---');
  stdout.writeln('  items:                 ${run.itemCount}');
  stdout.writeln('  total wall time:       ${fmtDuration(run.totalElapsed)}');
  stdout.writeln(
    '  ~download+parse:       ${fmtDuration(run.downloadElapsed)}',
  );
  stdout.writeln('  ~import (db):          ${fmtDuration(run.importElapsed)}');
  stdout.writeln(
    '  search index:          ${fmtDuration(run.searchIndexElapsed)} '
    '(${run.searchIndexRows} rows)',
  );
  stdout.writeln('  RSS before:            ${fmtMb(run.rssAtStart)}');
  stdout.writeln('  RSS after:             ${fmtMb(run.rssAtEnd)}');
  stdout.writeln('  RSS peak:              ${fmtMb(run.maxRss)}');
  stdout.writeln(
    '  RSS peak delta:        ${fmtMb(max(0, run.maxRss - run.rssAtStart))}',
  );
  stdout.writeln(
    '  event-loop max delay:  ${fmtDuration(run.maxEventLoopDelay)} '
    '(${run.delayedTicks} delayed ticks)',
  );
  stdout.writeln('');
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

class _MutablePlaylistSource implements PlaylistSource {
  _MutablePlaylistSource(this.content);

  String content;

  @override
  Future<String> fetch(
    String url, {
    void Function(int received, int? total)? onProgress,
  }) async {
    onProgress?.call(content.length, content.length);
    return content;
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
  _Options({
    required this.count,
    required this.seed,
    required this.scenario,
    required this.engine,
    required this.keepDb,
    required this.useNetwork,
    required this.outputPath,
  });

  final int count;
  final int seed;
  final String scenario;
  final String engine;
  final bool keepDb;
  final bool useNetwork;
  final String? outputPath;

  static _Options parse(List<String> args) {
    var count = 100000;
    var seed = 42;
    var scenario = 'cold';
    var engine = 'legacy';
    var keepDb = false;
    var useNetwork = true;
    String? outputPath;
    for (final arg in args) {
      if (arg.startsWith('--count=')) {
        count = int.parse(arg.substring('--count='.length));
      } else if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
      } else if (arg.startsWith('--scenario=')) {
        scenario = arg.substring('--scenario='.length);
      } else if (arg.startsWith('--engine=')) {
        engine = arg.substring('--engine='.length);
      } else if (arg == '--refresh') {
        scenario = 'churn5';
      } else if (arg == '--all') {
        scenario = 'all';
      } else if (arg == '--keep-db') {
        keepDb = true;
      } else if (arg == '--no-network') {
        useNetwork = false;
      } else if (arg.startsWith('--out=')) {
        outputPath = arg.substring('--out='.length);
      }
    }
    return _Options(
      count: count,
      seed: seed,
      scenario: scenario,
      engine: engine,
      keepDb: keepDb,
      useNetwork: useNetwork,
      outputPath: outputPath,
    );
  }
}

int max(int left, int right) => left > right ? left : right;
