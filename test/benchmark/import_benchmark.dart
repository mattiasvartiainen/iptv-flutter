import 'package:flutter_test/flutter_test.dart';

import '../../tool/benchmark_import.dart' as bench;

/// Opt-in Phase 0 performance benchmark (not part of the default
/// `flutter test` run since the file lives outside test/*_test.dart naming
/// and it deliberately imports huge synthetic playlists).
///
/// Run explicitly, e.g.:
///   flutter test test/benchmark/import_benchmark.dart --dart-define=BENCHMARK_COUNT=200000
///   flutter test test/benchmark/import_benchmark.dart --dart-define=BENCHMARK_COUNT=200000 --dart-define=BENCHMARK_REFRESH=true
void main() {
  const count = int.fromEnvironment('BENCHMARK_COUNT', defaultValue: 20000);
  const refresh = bool.fromEnvironment('BENCHMARK_REFRESH', defaultValue: true);
  const keepDb = bool.fromEnvironment('BENCHMARK_KEEP_DB');
  const noNetwork = bool.fromEnvironment('BENCHMARK_NO_NETWORK');

  test(
    'synthetic playlist import benchmark',
    () async {
      await bench.runBenchmark([
        '--count=$count',
        if (refresh) '--refresh',
        if (keepDb) '--keep-db',
        if (noNetwork) '--no-network',
      ]);
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
