import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/models/library_identity.dart';
import 'package:iptv_flutter/services/playback/playback_progress_foundation.dart';

const identity = LibraryIdentity(playlistId: 'p', profileId: 'a', itemKey: 1);
const other = LibraryIdentity(playlistId: 'p', profileId: 'b', itemKey: 1);

void main() {
  late _Store store;
  late PlaybackProgressCoordinator coordinator;
  setUp(() {
    store = _Store();
    coordinator = PlaybackProgressCoordinator(store);
  });

  test('live and unidentified playback never create a writer', () {
    expect(
      coordinator.begin(type: ContentType.live, identity: identity),
      isNull,
    );
    expect(coordinator.begin(type: ContentType.vod, identity: null), isNull);
    expect(store.writers, isEmpty);
  });

  test(
    'credits playback only and checkpoints at 30 and every 15 seconds',
    () async {
      final session = coordinator.begin(
        type: ContentType.vod,
        identity: identity,
      )!;
      await sample(session, 0, 0);
      await sample(session, 20, 20);
      await session.checkpoint();
      expect(store.values, isEmpty);
      await sample(session, 30, 30);
      expect(store.values.map((c) => c.position.inSeconds), [30]);
      await sample(session, 44, 44);
      expect(store.values, hasLength(1));
      await sample(session, 45, 45);
      expect(store.values.map((c) => c.position.inSeconds), [30, 45]);
      await sample(session, 50, 50, playing: false);
      await session.checkpoint();
      expect(store.values.last.position.inSeconds, 50);
      await sample(session, 100, 50, playing: false);
      expect(session.played.inSeconds, 50);
    },
  );

  test(
    'seek, buffering and position discontinuities do not earn playback',
    () async {
      final session = coordinator.begin(
        type: ContentType.vod,
        identity: identity,
      )!;
      await sample(session, 0, 0);
      await sample(session, 10, 10);
      session.seekStarted();
      await sample(session, 11, 90);
      session.seekFinished();
      await sample(session, 12, 90);
      expect(session.completed, isFalse);
      await sample(session, 13, 91);
      expect(session.completed, isTrue);
      await sample(session, 14, 92, buffering: true);
      await sample(session, 24, 92, buffering: true);
      await sample(session, 25, 95);
      expect(session.played.inSeconds, 12);
      await sample(session, 26, 500);
      expect(session.played.inSeconds, 12);
    },
  );

  test(
    'unknown duration and seeking to the end alone do not complete',
    () async {
      final session = coordinator.begin(
        type: ContentType.vod,
        identity: identity,
      )!;
      await sample(session, 0, 0, duration: null);
      await sample(session, 30, 30, duration: null);
      expect(session.completed, isFalse);
      session.seekStarted();
      await sample(session, 31, 100, playing: false);
      session.seekFinished();
      await sample(session, 32, 100, playing: false);
      await session.checkpoint();
      expect(store.values.last.completed, isFalse);
    },
  );

  test('90 percent requires observed playback after a seek', () async {
    final session = coordinator.begin(
      type: ContentType.vod,
      identity: identity,
    )!;
    await sample(session, 0, 0);
    await sample(session, 30, 30);
    session.seekStarted();
    await sample(session, 31, 89, playing: false);
    session.seekFinished();
    await sample(session, 32, 89, playing: false);
    await session.checkpoint();
    expect(store.values.last.completed, isFalse);
    await sample(session, 33, 89);
    await sample(session, 34, 90);
    expect(session.completed, isTrue);
    await session.finish();
    expect(store.values.last.completed, isTrue);
  });

  test(
    'late old-session writes are ignored and accepted writes stay ordered',
    () async {
      final gate = Completer<void>();
      store.gate = gate;
      final first = coordinator.begin(
        type: ContentType.vod,
        identity: identity,
      )!;
      await sample(first, 0, 0);
      final firstWrite = sample(first, 30, 30);
      final second = coordinator.begin(type: ContentType.vod, identity: other)!;
      await first.checkpoint();
      await sample(second, 0, 0);
      final secondWrite = sample(second, 30, 30);
      await Future<void>.delayed(Duration.zero);
      expect(store.values, isEmpty);
      gate.complete();
      await Future.wait([firstWrite, secondWrite]);
      expect(store.values.map((c) => c.identity), [identity, other]);
      await first.finish();
      expect(store.values, hasLength(2));
    },
  );

  test(
    'same-item replacement cannot be overwritten by an older session',
    () async {
      final gate = Completer<void>();
      store.gate = gate;
      final first = coordinator.begin(
        type: ContentType.vod,
        identity: identity,
      )!;
      await sample(first, 0, 0);
      final oldWrite = sample(first, 30, 30);
      final second = coordinator.begin(
        type: ContentType.vod,
        identity: identity,
      )!;
      await sample(second, 0, 10);
      final newWrite = sample(second, 30, 40);
      await sample(first, 50, 50);
      gate.complete();
      await Future.wait([oldWrite, newWrite]);
      expect(store.values.map((c) => c.position.inSeconds), [30, 40]);
      expect(store.writers, hasLength(2));
    },
  );

  test('failed writes are observable and do not poison the queue', () async {
    final session = coordinator.begin(
      type: ContentType.vod,
      identity: identity,
    )!;
    await sample(session, 0, 0);
    store.failNext = true;
    await expectLater(sample(session, 30, 30), throwsStateError);
    await sample(session, 31, 31);
    expect(store.values.single.position.inSeconds, 31);
  });

  test('rejects invalid or out-of-order samples', () async {
    final session = coordinator.begin(
      type: ContentType.vod,
      identity: identity,
    )!;
    await sample(session, 10, 0);
    expect(() => sample(session, 9, 0), throwsArgumentError);
    expect(() => sample(session, 11, -1), throwsArgumentError);
    session.seekStarted();
    expect(() => sample(session, 9, 0), throwsArgumentError);
  });
}

Future<void> sample(
  PlaybackProgressSession session,
  int seconds,
  int position, {
  int? duration = 100,
  bool playing = true,
  bool buffering = false,
}) => session.observe(
  elapsed: Duration(seconds: seconds),
  position: Duration(seconds: position),
  duration: duration == null ? null : Duration(seconds: duration),
  playing: playing,
  buffering: buffering,
);

class _Store implements PlaybackCheckpointStore {
  final writers = <_Writer>[];
  final values = <PlaybackCheckpoint>[];
  Completer<void>? gate;
  bool failNext = false;

  @override
  PlaybackCheckpointWriter newSession() {
    final writer = _Writer(this);
    writers.add(writer);
    return writer;
  }
}

class _Writer implements PlaybackCheckpointWriter {
  _Writer(this.store);
  final _Store store;

  @override
  Future<void> write(PlaybackCheckpoint checkpoint) async {
    if (store.failNext) {
      store.failNext = false;
      throw StateError('failed');
    }
    final gate = store.gate;
    if (gate != null) await gate.future;
    store.values.add(checkpoint);
  }
}
