import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/services/playback/playback_http_headers.dart';
import 'package:iptv_flutter/services/playback/playback_video_surface.dart';
import 'package:iptv_flutter/services/playback/video_player_playback.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native playback receives the shared desktop request headers', () async {
    final originalPlatform = VideoPlayerPlatform.instance;
    final platform = _RecordingVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
    final adapter = VideoPlayerPlaybackAdapter();
    addTearDown(() async {
      await adapter.dispose();
      await platform.disposed.future;
      await platform.closeEvents();
      VideoPlayerPlatform.instance = originalPlatform;
    });

    const item = ContentItem(
      id: 'stream',
      title: 'Test stream',
      type: ContentType.live,
      streamUrl: 'https://example.com/live.m3u8',
      group: 'Tests',
    );
    await adapter.load(item);

    expect(platform.source?.uri, item.streamUrl);
    expect(platform.source?.sourceType, DataSourceType.network);
    expect(platform.source?.httpHeaders, playbackHttpHeaders);
    expect(platform.source?.httpHeaders['User-Agent'], 'IPTV-Flutter/0.1');
    expect(
      platform.source?.httpHeaders['Accept'],
      'application/x-mpegURL,application/vnd.apple.mpegurl,*/*',
    );
    expect(platform.playCalls, greaterThan(0));
    expect(adapter.state.status, PlaybackStatus.playing);
  });

  group('native lifecycle', () {
    late VideoPlayerPlatform original;
    late _RecordingVideoPlayerPlatform platform;
    late VideoPlayerPlaybackAdapter adapter;
    late bool disposalFailureExpected;
    const item = ContentItem(
      id: 'native',
      title: 'Native video',
      type: ContentType.vod,
      streamUrl: 'https://example.com/video',
      group: 'Tests',
    );
    setUp(() {
      original = VideoPlayerPlatform.instance;
      platform = _RecordingVideoPlayerPlatform()..autoInitialize = false;
      VideoPlayerPlatform.instance = platform;
      adapter = VideoPlayerPlaybackAdapter();
      disposalFailureExpected = false;
    });
    tearDown(() async {
      if (disposalFailureExpected) {
        await expectLater(adapter.dispose(), throwsStateError);
      } else {
        await adapter.dispose();
      }
      await platform.closeEvents();
      await platform.created.close();
      VideoPlayerPlatform.instance = original;
    });

    test(
      'position and volume updates retain metadata until dimensions change',
      () async {
        platform.autoInitialize = true;
        await adapter.load(item);
        final view =
            adapter.buildVideoView()
                as PlaybackVideoSurface<vp.VideoPlayerValue>;
        final controller = view.values as vp.VideoPlayerController;
        final info = adapter.state.mediaInfo;
        for (var i = 1; i <= 100; i++) {
          controller.value = controller.value.copyWith(
            position: Duration(seconds: i),
          );
          expect(adapter.state.mediaInfo, same(info));
          expect(adapter.state.position, Duration(seconds: i));
        }
        controller.value = controller.value.copyWith(volume: .42);
        expect(adapter.state.volume, 42);
        expect(adapter.state.mediaInfo, same(info));
        controller.value = controller.value.copyWith(
          size: const Size(800, 600),
        );
        final changed = adapter.state.mediaInfo;
        expect(changed.width, 800);
        expect(changed.height, 600);
        expect(changed, isNot(same(info)));
        controller.value = controller.value.copyWith(
          position: const Duration(seconds: 101),
        );
        expect(adapter.state.mediaInfo, same(changed));
      },
    );

    test('stop cancels initialization and ignores detached events', () async {
      final created = platform.created.stream.first;
      final loading = adapter.load(item);
      final id = await created;
      await adapter.stop();
      await loading;
      expect(platform.events[id]!.hasListener, isFalse);
      platform.initialize(id);
      await Future<void>.delayed(Duration.zero);
      expect(adapter.state.status, PlaybackStatus.stopped);
      expect(platform.playCalls, 0);
      expect(platform.disposedIds, [id]);
      final restarted = platform.created.stream.first;
      final playing = adapter.play();
      platform.initialize(await restarted);
      await playing;
      expect(adapter.state.status, PlaybackStatus.playing);
    });

    test(
      'surface is stable per resource and its ratio follows native values',
      () async {
        platform.autoInitialize = true;
        await adapter.load(item);
        final view =
            adapter.buildVideoView()
                as PlaybackVideoSurface<vp.VideoPlayerValue>;
        expect(adapter.buildVideoView(), same(view));
        final controller = view.values as vp.VideoPlayerController;
        controller.value = controller.value.copyWith(
          size: const Size(800, 600),
        );
        expect(view.aspectRatio(view.values.value), 4 / 3);
        expect(adapter.buildVideoView(), same(view));
        await adapter.stop();
        expect(adapter.buildVideoView(), same(view));
        await adapter.play();
        expect(adapter.buildVideoView(), same(view));
        final nextLoad = adapter.load(item);
        expect(adapter.buildVideoView(), isNull);
        await nextLoad;
        expect(adapter.buildVideoView(), isNot(same(view)));
        await adapter.dispose();
        expect(adapter.buildVideoView(), isNull);
      },
    );

    test(
      'native load errors throw safe typed failures matching state',
      () async {
        final created = platform.created.stream.first;
        final loading = adapter.load(item);
        final failure = expectLater(
          loading,
          throwsA(
            isA<PlaybackException>()
                .having(
                  (error) => error.kind,
                  'kind',
                  PlaybackErrorKind.accessDenied,
                )
                .having(
                  (error) => error.toString(),
                  'safe text',
                  isNot(contains('token')),
                ),
          ),
        );
        final id = await created;
        platform.events[id]!.addError(
          PlatformException(
            code: 'VideoError',
            message: 'HTTP 403 https://example.com/video?token=test',
          ),
        );
        await failure;
        expect(adapter.state.errorKind, PlaybackErrorKind.accessDenied);
      },
    );

    test(
      'disposal is idempotent, cancels initialization and awaits native release',
      () async {
        final created = platform.created.stream.first;
        final loading = adapter.load(item);
        final id = await created;
        final cleanup = platform.disposalGate = Completer<void>();
        var done = false;
        final disposal = adapter.dispose();
        final completion = disposal.then((_) => done = true);
        expect(adapter.dispose(), same(disposal));
        await loading;
        await Future<void>.delayed(Duration.zero);
        expect(done, isFalse);
        expect(platform.events[id]!.hasListener, isFalse);
        platform.initialize(id);
        cleanup.complete();
        await completion;
        expect(platform.disposedIds, [id]);
        expect(platform.playCalls, 0);
      },
    );

    test(
      'native disposal failures remain observable without repeated release',
      () async {
        final created = platform.created.stream.first;
        final loading = adapter.load(item);
        final id = await created;
        platform.disposalError = StateError('Native disposal failed');
        disposalFailureExpected = true;
        final disposal = adapter.dispose();
        await expectLater(disposal, throwsStateError);
        await loading;
        expect(adapter.dispose(), same(disposal));
        expect(platform.disposedIds, [id]);
      },
    );
  });
}

class _RecordingVideoPlayerPlatform extends VideoPlayerPlatform {
  DataSource? source;
  int playCalls = 0;
  final disposed = Completer<void>();
  final created = StreamController<int>.broadcast(sync: true);
  final events = <int, StreamController<VideoEvent>>{};
  final disposedIds = <int>[];
  bool autoInitialize = true;
  int nextId = 0;
  Completer<void>? disposalGate;
  Object? disposalError;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    source = options.dataSource;
    final id = ++nextId;
    events[id] = StreamController<VideoEvent>.broadcast(sync: true);
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    scheduleMicrotask(() {
      created.add(playerId);
      if (autoInitialize) initialize(playerId);
    });
    return events[playerId]!.stream;
  }

  void initialize(int id) => events[id]!.add(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(minutes: 1),
      size: const Size(1280, 720),
    ),
  );

  @override
  Future<void> play(int playerId) async {
    playCalls++;
  }

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> dispose(int playerId) async {
    disposedIds.add(playerId);
    final gate = disposalGate;
    if (gate != null) await gate.future;
    final error = disposalError;
    if (error != null) throw error;
    if (!disposed.isCompleted) disposed.complete();
  }

  Future<void> closeEvents() async {
    for (final event in events.values) {
      await event.close();
    }
  }
}
