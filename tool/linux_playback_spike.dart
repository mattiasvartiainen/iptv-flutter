import 'dart:async';

import 'package:media_kit/media_kit.dart';

class SpikeCase {
  const SpikeCase({
    required this.id,
    required this.url,
    required this.kind,
    this.expectFailure = false,
  });

  final String id;
  final String url;
  final String kind;
  final bool expectFailure;
}

class SpikeResult {
  const SpikeResult({
    required this.id,
    required this.kind,
    required this.outcome,
    required this.detail,
    required this.elapsed,
    required this.startupLatency,
    required this.buffering,
    required this.position,
    required this.duration,
  });

  final String id;
  final String kind;
  final String outcome;
  final String detail;
  final Duration elapsed;
  final Duration? startupLatency;
  final bool buffering;
  final Duration position;
  final Duration? duration;
}

Future<void> main() async {
  MediaKit.ensureInitialized();

  const cases = <SpikeCase>[
    SpikeCase(
      id: 'mux-live-x36xhzz',
      kind: 'live',
      url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    ),
    SpikeCase(
      id: 'apple-bipbop-variant',
      kind: 'vod',
      url:
          'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8',
    ),
    SpikeCase(
      id: 'sintel-vod-hls',
      kind: 'vod',
      url: 'https://bitdash-a.akamaihd.net/content/sintel/hls/playlist.m3u8',
    ),
    SpikeCase(
      id: 'expected-failure-404',
      kind: 'live',
      url: 'https://test-streams.mux.dev/does-not-exist/index.m3u8',
      expectFailure: true,
    ),
  ];

  final results = <SpikeResult>[];
  for (final testCase in cases) {
    results.add(await _runCase(testCase));
  }

  final passed = results
      .where((r) => r.outcome == 'PASS' || r.outcome == 'EXPECTED_FAIL')
      .length;
  final failed = results.length - passed;

  print('\n=== Linux Playback Spike Results ===');
  for (final result in results) {
    print(
      '${result.outcome.padRight(14)} | ${result.kind.padRight(4)} | ${result.id.padRight(26)} | startup=${result.startupLatency?.inMilliseconds ?? -1}ms | buffering=${result.buffering.toString().padRight(5)} | pos=${result.position.inSeconds}s | dur=${result.duration?.inSeconds ?? -1}s | ${result.detail}',
    );
  }
  print(
    'Summary: $passed/${results.length} passing expectations, $failed failing expectations.',
  );

  if (failed > 0) {
    throw StateError('One or more spike cases failed expectations.');
  }
}

Future<SpikeResult> _runCase(SpikeCase testCase) async {
  final started = DateTime.now();
  final player = Player();
  StreamSubscription<String>? errorSub;
  StreamSubscription<bool>? playingSub;
  StreamSubscription<bool>? completedSub;
  StreamSubscription<bool>? bufferingSub;
  StreamSubscription<Duration>? positionSub;
  StreamSubscription<Duration>? durationSub;

  var lastBuffering = false;
  var lastPosition = Duration.zero;
  Duration? lastDuration;
  DateTime? playbackStartedAt;

  try {
    final playbackStarted = Completer<void>();
    final playbackError = Completer<String>();

    errorSub = player.stream.error.listen((value) {
      if (!playbackError.isCompleted) {
        playbackError.complete(value);
      }
    });

    playingSub = player.stream.playing.listen((isPlaying) {
      if (isPlaying && !playbackStarted.isCompleted) {
        playbackStartedAt = DateTime.now();
        playbackStarted.complete();
      }
    });

    completedSub = player.stream.completed.listen((isCompleted) {
      if (isCompleted && !playbackStarted.isCompleted) {
        playbackStarted.complete();
      }
    });

    bufferingSub = player.stream.buffering.listen((isBuffering) {
      lastBuffering = isBuffering;
    });

    positionSub = player.stream.position.listen((position) {
      lastPosition = position;
    });

    durationSub = player.stream.duration.listen((duration) {
      if (duration != Duration.zero) {
        lastDuration = duration;
      }
    });

    await player.open(
      Media(
        testCase.url,
        httpHeaders: const {
          'Accept': 'application/x-mpegURL,application/vnd.apple.mpegurl,*/*',
          'User-Agent': 'IPTV-Flutter/0.1',
        },
      ),
    );

    final settled = await Future.any<Object>([
      playbackStarted.future.then<Object>((_) => true),
      playbackError.future.then<Object>((value) => value),
      Future<Object>.delayed(const Duration(seconds: 20), () => 'timeout'),
    ]);

    final elapsed = DateTime.now().difference(started);
    if (settled == true) {
      return SpikeResult(
        id: testCase.id,
        kind: testCase.kind,
        outcome: testCase.expectFailure ? 'UNEXPECTED_PASS' : 'PASS',
        detail: 'playback started',
        elapsed: elapsed,
        startupLatency: playbackStartedAt?.difference(started),
        buffering: lastBuffering,
        position: lastPosition,
        duration: lastDuration,
      );
    }

    final errorText = settled.toString();
    return SpikeResult(
      id: testCase.id,
      kind: testCase.kind,
      outcome: testCase.expectFailure ? 'EXPECTED_FAIL' : 'FAIL',
      detail: errorText,
      elapsed: elapsed,
      startupLatency: playbackStartedAt?.difference(started),
      buffering: lastBuffering,
      position: lastPosition,
      duration: lastDuration,
    );
  } catch (error) {
    final elapsed = DateTime.now().difference(started);
    return SpikeResult(
      id: testCase.id,
      kind: testCase.kind,
      outcome: testCase.expectFailure ? 'EXPECTED_FAIL' : 'FAIL',
      detail: error.toString(),
      elapsed: elapsed,
      startupLatency: playbackStartedAt?.difference(started),
      buffering: lastBuffering,
      position: lastPosition,
      duration: lastDuration,
    );
  } finally {
    await errorSub?.cancel();
    await playingSub?.cancel();
    await completedSub?.cancel();
    await bufferingSub?.cancel();
    await positionSub?.cancel();
    await durationSub?.cancel();
    await player.dispose();
  }
}
