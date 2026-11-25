import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/services/playback/playback_session.dart';
import 'package:iptv_flutter/services/playback/video_player_playback.dart';

import '../../support/controlled_playback.dart';

const first = ContentItem(
  id: 'first',
  title: 'First',
  type: ContentType.vod,
  streamUrl: 'https://example.com/first',
  group: 'Tests',
);
const second = ContentItem(
  id: 'second',
  title: 'Second',
  type: ContentType.vod,
  streamUrl: 'https://example.com/second',
  group: 'Tests',
);
const third = ContentItem(
  id: 'third',
  title: 'Third',
  type: ContentType.vod,
  streamUrl: 'https://example.com/third',
  group: 'Tests',
);

Future<void> flushCommands() => Future<void>.delayed(Duration.zero);

void main() {
  late ControlledPlayback backend;
  late PlaybackSession session;
  late bool disposalFailureExpected;

  setUp(() {
    backend = ControlledPlayback();
    session = PlaybackSession(backend);
    disposalFailureExpected = false;
  });
  tearDown(() async {
    if (disposalFailureExpected) {
      await expectLater(session.dispose(), throwsStateError);
    } else {
      await session.dispose();
    }
  });

  test(
    'replacement cancels initialization without waiting for its event',
    () async {
      final initialization = backend.loadGate = Completer<void>();
      final opening = session.load(first);
      await flushCommands();
      expect(backend.calls, ['load:first']);

      final replacement = session.load(second);
      expect(session.state.item, second);
      expect(session.state.status, PlaybackStatus.loading);
      await Future.wait([opening, replacement]);
      expect(initialization.isCompleted, isFalse);
      expect(backend.calls, ['load:first', 'stop', 'load:second']);
      expect(session.state.item, second);
      expect(session.state.status, PlaybackStatus.playing);

      initialization.completeError(StateError('Obsolete initialization'));
      await flushCommands();
      expect(session.state.item, second);
      expect(session.state.status, PlaybackStatus.playing);
    },
  );

  test(
    'unsupported commands never reach the backend or alter the session',
    () async {
      final unsupported = ControlledPlayback(
        capabilities: const PlaybackCapabilities(
          supportsPause: false,
          supportsSeek: false,
          supportsVolume: false,
          supportsDrm: false,
          supportsLiveStreams: false,
        ),
      );
      final guarded = PlaybackSession(unsupported);
      addTearDown(guarded.dispose);
      await guarded.load(first);
      final previous = guarded.state;
      for (final command in [
        guarded.pause,
        () => guarded.seek(Duration.zero),
        () => guarded.setVolume(50),
        () => guarded.selectAudioTrack('1'),
        () => guarded.selectSubtitleTrack('off'),
        () => guarded.load(
          const ContentItem(
            id: 'live',
            title: 'Live',
            type: ContentType.live,
            streamUrl: 'https://example.com/live',
            group: 'Tests',
          ),
        ),
      ]) {
        await expectLater(command(), throwsUnsupportedError);
        expect(guarded.state, same(previous));
      }
      expect(unsupported.calls, ['load:first']);
      await guarded.stop();
      await guarded.play();
      expect(guarded.state.status, PlaybackStatus.playing);
      expect(unsupported.calls, ['load:first', 'stop', 'load:first']);
    },
  );

  test('advertised tracks require the optional track interface', () async {
    final invalid = _InvalidTrackBackend();
    addTearDown(invalid.dispose);
    expect(() => PlaybackSession(invalid), throwsArgumentError);
  });

  test(
    'surface lookup observes replacement and invalidation within the same item',
    () async {
      await session.load(first);
      expect(session.buildVideoView(), isNull);
      backend.view = const SizedBox(key: ValueKey('native-first'));
      backend.emit(backend.state.copyWith());
      final old = session.buildVideoView();
      expect(old, same(backend.view));
      expect(session.buildVideoView(), same(old));
      backend.view = const SizedBox(key: ValueKey('native-second'));
      backend.emit(backend.state.copyWith());
      expect(session.buildVideoView(), same(backend.view));
      expect(session.buildVideoView(), isNot(same(old)));
      backend.view = null;
      backend.emit(backend.state.copyWith());
      expect(session.buildVideoView(), isNull);
      await session.dispose();
      expect(session.buildVideoView(), isNull);
    },
  );

  test(
    'only the latest queued replacement reaches the native backend',
    () async {
      backend.loadGate = Completer<void>();
      final opening = session.load(first);
      await flushCommands();
      final skipped = session.load(second);
      final replacement = session.load(third);
      await Future.wait([opening, skipped, replacement]);
      expect(backend.calls, ['load:first', 'stop', 'load:third']);
      expect(session.state.item, third);
    },
  );

  test(
    'stop retains the requested item even when its queued load was cancelled',
    () async {
      backend.view = const SizedBox();
      await session.load(first);
      expect(session.buildVideoView(), same(backend.view));
      final opening = session.load(second);
      final stopping = session.stop();
      await Future.wait([opening, stopping]);
      expect(backend.calls, ['load:first', 'stop']);
      expect(session.state.item, second);
      expect(session.buildVideoView(), isNull);
      backend.emit(backend.state.copyWith(status: PlaybackStatus.paused));
      expect(session.state.item, second);
      expect(session.state.status, PlaybackStatus.stopped);
      await session.play();
      expect(backend.calls, ['load:first', 'stop', 'load:second']);
      expect(session.state.item, second);
      expect(session.state.status, PlaybackStatus.playing);
    },
  );

  test(
    'stop invalidates queued loads and prevents autoplay immediately',
    () async {
      backend.loadGate = Completer<void>();
      final opening = session.load(first);
      await flushCommands();
      final replacement = session.load(second);
      final stopping = session.stop();
      expect(session.state.status, PlaybackStatus.stopped);
      expect(session.buildVideoView(), isNull);
      await Future.wait([opening, replacement, stopping]);
      expect(backend.calls, isNot(contains('load:second')));
      expect(session.state.status, PlaybackStatus.stopped);
    },
  );

  test(
    'a replacement overtakes a queued stop but waits for cancellation',
    () async {
      backend.loadGate = Completer<void>();
      final cancellation = backend.stopGate = Completer<void>();
      final opening = session.load(first);
      await flushCommands();
      final stopping = session.stop();
      final replacement = session.load(second);
      await flushCommands();
      expect(backend.calls, ['load:first', 'stop']);
      cancellation.complete();
      await Future.wait([opening, stopping, replacement]);
      expect(backend.calls, ['load:first', 'stop', 'load:second']);
      expect(session.state.status, PlaybackStatus.playing);
    },
  );

  for (final fail in [false, true]) {
    test(
      'late command ${fail ? 'failure' : 'completion'} cannot overwrite a replacement',
      () async {
        await session.load(first);
        final command = backend.commandGate = Completer<void>();
        final pausing = session.pause();
        await flushCommands();
        final replacement = session.load(second);
        final obsoleteSeek = session.seek(const Duration(seconds: 5));
        final latest = session.load(third);
        expect(session.state.item, third);
        expect(session.state.status, PlaybackStatus.loading);
        expect(backend.calls, ['load:first', 'pause']);
        if (fail) {
          command.completeError(StateError('Obsolete pause'));
        } else {
          command.complete();
        }

        await Future.wait([pausing, replacement, obsoleteSeek, latest]);
        expect(backend.calls, ['load:first', 'pause', 'load:third']);
        expect(session.state.item, third);
        expect(session.state.status, PlaybackStatus.playing);
      },
    );
  }

  test('commands including track requests are serialized', () async {
    await session.load(first);
    final command = backend.commandGate = Completer<void>();
    final pausing = session.pause();
    final seeking = session.seek(const Duration(seconds: 5));
    final volume = session.setVolume(30);
    final audio = session.selectAudioTrack('1');
    final subtitle = session.selectSubtitleTrack('off');
    await flushCommands();
    expect(backend.calls, ['load:first', 'pause']);
    command.complete();
    await Future.wait([pausing, seeking, volume, audio, subtitle]);
    expect(backend.calls, [
      'load:first',
      'pause',
      'seek',
      'volume',
      'audio:1',
      'subtitle:off',
    ]);
    expect(session.state.position, const Duration(seconds: 5));
    expect(session.state.volume, 30);
  });

  test(
    'current command errors are observable without poisoning the queue',
    () async {
      await session.load(first);
      final command = backend.commandGate = Completer<void>();
      final pausing = session.pause();
      final failure = expectLater(pausing, throwsStateError);
      await flushCommands();
      command.completeError(StateError('Pause failed'));
      await failure;
      await session.load(second);
      expect(session.state.item, second);
      expect(session.state.status, PlaybackStatus.playing);
    },
  );

  test(
    'obsolete load errors and events cannot overwrite a new session',
    () async {
      backend.cancelLoads = false;
      final initialization = backend.loadGate = Completer<void>();
      final opening = session.load(first);
      await flushCommands();
      final replacement = session.load(second);
      backend.emit(PlaybackState(status: PlaybackStatus.error, item: first));
      expect(session.state.item, second);
      expect(session.state.status, PlaybackStatus.loading);
      initialization.completeError(StateError('Old load failed'));
      await Future.wait([opening, replacement]);
      expect(session.state.item, second);
      expect(session.state.status, PlaybackStatus.playing);
    },
  );

  test(
    'cancellation failures are observable and later loads can recover',
    () async {
      backend.loadGate = Completer<void>();
      final opening = session.load(first);
      await flushCommands();
      backend.stopError = StateError('Stop failed');
      final replacement = session.load(second);
      await expectLater(replacement, throwsStateError);
      await opening;
      expect(backend.calls, isNot(contains('load:second')));
      backend.stopError = null;
      await session.load(third);
      expect(session.state.item, third);
    },
  );

  test(
    'explicit restart after stop is interruptible during initialization',
    () async {
      await session.load(first);
      await session.stop();
      backend.loadGate = Completer<void>();
      final restarting = session.play();
      await flushCommands();
      expect(session.state.status, PlaybackStatus.loading);
      final replacement = session.load(second);
      await Future.wait([restarting, replacement]);
      expect(session.state.item, second);
      expect(session.state.status, PlaybackStatus.playing);
    },
  );

  test(
    'disposal cancels loading, suppresses events and awaits native cleanup once',
    () async {
      backend.loadGate = Completer<void>();
      final nativeCleanup = backend.disposalGate = Completer<void>();
      final opening = session.load(first);
      await flushCommands();
      final observed = <PlaybackState>[];
      var closed = false;
      final subscription = session.states.listen(
        observed.add,
        onDone: () => closed = true,
      );
      var cleaned = false;
      final disposal = session.dispose();
      final completion = disposal.then((_) => cleaned = true);
      expect(session.dispose(), same(disposal));
      backend.emit(PlaybackState(status: PlaybackStatus.error, item: first));
      await session.load(second);
      await session.play();
      await opening;
      await flushCommands();
      expect(observed, isEmpty);
      expect(backend.calls.where((call) => call == 'dispose'), hasLength(1));
      expect(cleaned, isFalse);
      expect(closed, isFalse);
      nativeCleanup.complete();
      await completion;
      expect(closed, isTrue);
      await subscription.cancel();
    },
  );

  test('disposal drains an in-flight command and skips queued work', () async {
    await session.load(first);
    final command = backend.commandGate = Completer<void>();
    final pausing = session.pause();
    await flushCommands();
    final seeking = session.seek(Duration.zero);
    final disposal = session.dispose();
    await flushCommands();
    expect(backend.calls, ['load:first', 'pause']);
    command.completeError(StateError('Obsolete pause'));
    await Future.wait([pausing, seeking, disposal]);
    expect(backend.calls, ['load:first', 'pause', 'dispose']);
  });

  test(
    'native disposal failure is observable and repeated calls do not retry',
    () async {
      backend.disposalError = StateError('Native cleanup failed');
      disposalFailureExpected = true;
      final disposal = session.dispose();
      expect(session.dispose(), same(disposal));
      await expectLater(disposal, throwsStateError);
      expect(backend.calls, ['dispose']);
    },
  );

  test(
    'cancellation failure still releases the backend during disposal',
    () async {
      backend.loadGate = Completer<void>();
      final opening = session.load(first);
      await flushCommands();
      backend.stopError = StateError('Cancellation failed');
      disposalFailureExpected = true;
      await expectLater(session.dispose(), throwsStateError);
      await opening;
      expect(backend.calls.last, 'dispose');
    },
  );
}

class _InvalidTrackBackend extends VideoPlayerPlaybackAdapter {
  @override
  PlaybackCapabilities get capabilities => const PlaybackCapabilities(
    supportsSeek: true,
    supportsPause: true,
    supportsVolume: true,
    supportsDrm: false,
    supportsLiveStreams: true,
    supportsAudioTracks: true,
  );
}
