import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/playback/desktop_media_kit_playback.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:media_kit/media_kit.dart';

const item = ContentItem(
  id: 'desktop',
  title: 'Desktop video',
  type: ContentType.vod,
  streamUrl: 'https://example.com/video',
  group: 'Tests',
);

void main() {
  late _ControlledPlatformPlayer native;
  late DesktopMediaKitPlaybackAdapter adapter;
  late bool disposalFailureExpected;
  setUp(() {
    native = _ControlledPlatformPlayer();
    adapter = DesktopMediaKitPlaybackAdapter.forTesting(
      Player(platformPlayer: native),
    );
    disposalFailureExpected = false;
  });
  tearDown(() async {
    if (disposalFailureExpected) {
      await expectLater(adapter.dispose(), throwsStateError);
    } else {
      await adapter.dispose();
    }
  });

  test(
    'initialization cannot autoplay after stop even when native open completes late',
    () async {
      final opening = native.openGate = Completer<void>();
      final loading = adapter.load(item);
      expect(native.calls, ['open:false']);
      await adapter.stop();
      await loading;
      opening.complete();
      native.emitDetachedEvents();
      await Future<void>.delayed(Duration.zero);
      expect(native.calls, ['open:false', 'stop']);
      expect(adapter.state.status, PlaybackStatus.stopped);
      await adapter.play();
      await Future<void>.delayed(Duration.zero);
      expect(native.calls, ['open:false', 'stop', 'open:false', 'play']);
      expect(adapter.state.status, PlaybackStatus.playing);
    },
  );

  test(
    'pause and explicit resume retain the current native resource',
    () async {
      await adapter.load(item);
      await Future<void>.delayed(Duration.zero);
      await adapter.pause();
      expect(adapter.state.status, PlaybackStatus.paused);
      await adapter.play();
      await Future<void>.delayed(Duration.zero);
      expect(native.calls, ['open:false', 'play', 'pause', 'play']);
      expect(adapter.state.status, PlaybackStatus.playing);
    },
  );

  test(
    'desktop native failures preserve typed classification without native text',
    () async {
      final opening = native.openGate = Completer<void>();
      final loading = adapter.load(item);
      final failure = expectLater(
        loading,
        throwsA(
          isA<PlaybackException>()
              .having((error) => error.kind, 'kind', PlaybackErrorKind.timeout)
              .having(
                (error) => error.toString(),
                'safe text',
                isNot(contains('token')),
              ),
        ),
      );
      opening.completeError(
        StateError('Timeout https://example.com/video?token=test'),
      );
      await failure;
      expect(adapter.state.errorKind, PlaybackErrorKind.timeout);
    },
  );

  test(
    'disposal cancels initialization and awaits native cleanup exactly once',
    () async {
      final opening = native.openGate = Completer<void>();
      final loading = adapter.load(item);
      final cleanup = native.disposalGate = Completer<void>();
      final observed = <PlaybackState>[];
      final subscription = adapter.states.listen(observed.add);
      await Future<void>.delayed(Duration.zero);
      observed.clear();
      var done = false;
      final disposal = adapter.dispose();
      final completion = disposal.then((_) => done = true);
      expect(adapter.dispose(), same(disposal));
      await loading;
      await Future<void>.delayed(Duration.zero);
      native.emitDetachedEvents();
      await Future<void>.delayed(Duration.zero);
      expect(observed, isEmpty);
      expect(done, isFalse);
      opening.complete();
      cleanup.complete();
      await completion;
      expect(native.calls, ['open:false', 'dispose']);
      await subscription.cancel();
    },
  );

  test(
    'native disposal failures are observable without repeated release',
    () async {
      native.disposalError = StateError('Desktop cleanup failed');
      disposalFailureExpected = true;
      final disposal = adapter.dispose();
      await expectLater(disposal, throwsStateError);
      expect(adapter.dispose(), same(disposal));
      expect(native.calls, ['dispose']);
    },
  );
}

class _ControlledPlatformPlayer extends PlatformPlayer {
  _ControlledPlatformPlayer()
    : super(configuration: const PlayerConfiguration());

  final calls = <String>[];
  Completer<void>? openGate;
  Completer<void>? disposalGate;
  Object? disposalError;

  void emitDetachedEvents() {
    playingController.add(true);
    errorController.add('Detached error');
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    calls.add('open:$play');
    final gate = openGate;
    openGate = null;
    if (gate != null) await gate.future;
    state = state.copyWith(playing: false);
    playingController.add(false);
    if (play) await this.play();
  }

  @override
  Future<void> play() async {
    calls.add('play');
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> dispose() async {
    calls.add('dispose');
    try {
      final gate = disposalGate;
      if (gate != null) await gate.future;
      final error = disposalError;
      if (error != null) throw error;
    } finally {
      await super.dispose();
    }
  }
}
