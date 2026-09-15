import 'dart:io';

import 'synthetic_playlist.dart';

/// Standalone playlist generator, useful for inspecting the fixture or
/// feeding it to other tools without running the full benchmark.
///
/// Usage: dart run tool/generate_synthetic_playlist.dart --count=200000 --out=/tmp/playlist.m3u
Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final content = generateSyntheticPlaylist(
    itemCount: options.count,
    seed: options.seed,
  );
  final file = File(options.outPath);
  await file.create(recursive: true);
  await file.writeAsString(content);
  final sizeMb = (await file.length()) / (1024 * 1024);
  stdout.writeln(
    'Wrote ${options.count} items to ${file.path} '
    '(${sizeMb.toStringAsFixed(1)} MB)',
  );
}

class _Options {
  _Options({required this.count, required this.seed, required this.outPath});

  final int count;
  final int seed;
  final String outPath;

  static _Options parse(List<String> args) {
    var count = 100000;
    var seed = 42;
    var outPath = 'build/synthetic_playlist.m3u';
    for (final arg in args) {
      if (arg.startsWith('--count=')) {
        count = int.parse(arg.substring('--count='.length));
      } else if (arg.startsWith('--seed=')) {
        seed = int.parse(arg.substring('--seed='.length));
      } else if (arg.startsWith('--out=')) {
        outPath = arg.substring('--out='.length);
      }
    }
    return _Options(count: count, seed: seed, outPath: outPath);
  }
}
