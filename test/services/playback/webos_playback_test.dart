import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/platform/app_platform.dart';
import 'package:iptv_flutter/platform/platform_profile.dart';
import 'package:iptv_flutter/platform/webos_playback_adapter.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/services/playback/playback_video_surface.dart';
import 'package:video_player_drm/video_player.dart' as video;
import 'package:video_player_drm/video_player_platform_interface.dart' as lg;

const item = ContentItem(
  id: '1',
  title: 'Channel',
  type: ContentType.live,
  streamUrl: 'https://user:pass@example.com/live/user/pass/1?token=secret',
  group: 'TV',
);

class FakeLgPlatform extends lg.VideoPlayerPlatform {
  final events = <int, StreamController<lg.VideoEvent>>{};
  final created = StreamController<int>.broadcast(sync: true);
  final calls = <String>[];
  lg.DataSource? source;
  var nextId = 0;
  Completer<void>? disposalGate;
  Object? disposalError;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(lg.DataSource dataSource) async {
    source = dataSource;
    final id = ++nextId;
    events[id] = StreamController<lg.VideoEvent>.broadcast(sync: true);
    return id;
  }

  @override
  Stream<lg.VideoEvent> videoEventsFor(int playerId) {
    scheduleMicrotask(() => created.add(playerId));
    return events[playerId]!.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    calls.add('dispose:$playerId');
    final gate = disposalGate;
    if (gate != null) await gate.future;
    final error = disposalError;
    if (error != null) throw error;
  }

  @override
  Future<void> play(int playerId) async => calls.add('play:$playerId');
  @override
  Future<void> pause(int playerId) async => calls.add('pause:$playerId');
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      calls.add('seek:${position.inMilliseconds}');
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Future<void> selectTrack(int playerId, String type, int index) async =>
      calls.add('$type:$index');
  @override
  Future<void> setSubtitleEnable(int playerId, bool enable) async =>
      calls.add('subtitle:$enable');
  @override
  Widget buildView(int playerId) => const SizedBox();

  void initialize(int id) {
    events[id]!.add(
      lg.VideoEvent(
        eventType: lg.VideoEventType.initialized,
        duration: const Duration(minutes: 5),
        size: const Size(1920, 1080),
        audioTracks: [
          {'language': 'en'},
          {'language': 'https://example.com/live/user/pass'},
          {'language': 'user'},
        ],
        subtitleTracks: [
          {'language': 'fr'},
        ],
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeLgPlatform platform;
  late lg.VideoPlayerPlatform original;
  late WebOsPlaybackAdapter adapter;
  late bool disposalFailureExpected;

  setUp(() {
    original = lg.VideoPlayerPlatform.instance;
    platform = FakeLgPlatform();
    lg.VideoPlayerPlatform.instance = platform;
    adapter = WebOsPlaybackAdapter.forTesting();
    disposalFailureExpected = false;
  });

  tearDown(() async {
    if (disposalFailureExpected) {
      await expectLater(adapter.dispose(), throwsStateError);
    } else {
      await adapter.dispose();
    }
    await Future<void>.delayed(Duration.zero);
    for (final event in platform.events.values) {
      await event.close();
    }
    await platform.created.close();
    lg.VideoPlayerPlatform.instance = original;
  });

  Future<int> beginLoad() async {
    final created = platform.created.stream.first;
    unawaited(adapter.load(item));
    return created;
  }

  test('webOS profile selects dedicated backend and honest capabilities', () {
    final selected = platformProfileFor(
      AppPlatform.webos,
    ).createPlaybackAdapter();
    expect(selected, isA<WebOsPlaybackAdapter>());
    expect(selected.capabilities.usesPlatformVideoPlane, isTrue);
    expect(selected.capabilities.supportsAudioTracks, isTrue);
    expect(selected.capabilities.supportsSubtitleTracks, isTrue);
    expect(selected.capabilities.supportsVolume, isFalse);
    expect(selected.capabilities.supportsDrm, isFalse);
    addTearDown(selected.dispose);
  });

  test('production adapter requires the verified build marker', () async {
    final selected = WebOsPlaybackAdapter();
    if (const bool.fromEnvironment('IPTV_WEBOS_SAFE_NATIVE_LOGS')) {
      final created = platform.created.stream.first;
      final loading = selected.load(item);
      platform.initialize(await created);
      await loading;
      expect(selected.state.status, PlaybackStatus.playing);
    } else {
      await expectLater(selected.load(item), throwsStateError);
      expect(platform.source, isNull);
      expect(selected.state.status, PlaybackStatus.error);
    }
    await selected.dispose();
  });

  test(
    'LG native failure classification survives the controller boundary',
    () async {
      final navigation = NavigationController();
      final player = PlayerController(
        playbackAdapter: adapter,
        navigationController: navigation,
      );
      addTearDown(() async {
        player.dispose();
        await player.disposalComplete;
        navigation.dispose();
      });
      final created = platform.created.stream.first;
      final loading = player.openPlayer(item);
      final id = await created;
      platform.events[id]!.addError(
        PlatformException(
          code: 'VideoError',
          message: 'HTTP 404 https://example.com/live/user/pass?token=test',
        ),
      );
      await loading;
      expect(adapter.state.errorKind, PlaybackErrorKind.notFound);
      expect(player.playbackState.value.errorKind, PlaybackErrorKind.notFound);
      expect(player.playbackState.value.message, isNull);
    },
  );

  test('LG load failure is typed and contains no native URL', () async {
    final created = platform.created.stream.first;
    final loading = adapter.load(item);
    final failure = expectLater(
      loading,
      throwsA(
        isA<PlaybackException>()
            .having((error) => error.kind, 'kind', PlaybackErrorKind.network)
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
        message: 'Connection failed https://example.com/video?token=test',
      ),
    );
    await failure;
    expect(adapter.state.errorKind, PlaybackErrorKind.network);
  });

  test(
    'LG surface is stable while retained and replaced with its native controller',
    () async {
      final created = platform.created.stream.first;
      final loading = adapter.load(item);
      platform.initialize(await created);
      await loading;
      final view =
          adapter.buildVideoView()
              as PlaybackVideoSurface<video.VideoPlayerValue>;
      expect(adapter.buildVideoView(), same(view));
      final controller = view.values as video.VideoPlayerController;
      controller.value = controller.value.copyWith(size: const Size(800, 600));
      expect(view.aspectRatio(view.values.value), 4 / 3);
      expect(adapter.buildVideoView(), same(view));
      await adapter.stop();
      await adapter.play();
      expect(adapter.buildVideoView(), same(view));
      final replacementCreated = platform.created.stream.first;
      final replacing = adapter.load(item);
      expect(adapter.buildVideoView(), isNull);
      platform.initialize(await replacementCreated);
      await replacing;
      expect(adapter.buildVideoView(), isNot(same(view)));
      await adapter.dispose();
      expect(adapter.buildVideoView(), isNull);
    },
  );

  test(
    'loads native video, exposes safe tracks and selects by index',
    () async {
      final id = await beginLoad();
      expect(adapter.state.status, PlaybackStatus.loading);
      platform.initialize(id);
      await Future<void>.delayed(Duration.zero);
      expect(platform.source!.uri, item.streamUrl);
      expect(platform.source!.httpHeaders, isEmpty);
      expect(platform.source!.drmConfigs, isNull);
      expect(adapter.state.status, PlaybackStatus.playing);
      final info = adapter.state.mediaInfo;
      expect(info.width, 1920);
      expect(info.height, 1080);
      expect(info.fps, isNull);
      expect(info.videoCodec, isNull);
      expect(info.audioTracks.map((t) => t.label), [
        'en',
        'Audio track 2',
        'Audio track 3',
      ]);
      expect(info.selectedAudioId, isNull);
      expect(info.selectedSubtitleId, isNull);
      expect(info.subtitleTracks.map((t) => t.id), ['off', '0']);
      await adapter.selectAudioTrack('1');
      expect(platform.calls, contains('audio:1'));
      expect(adapter.state.mediaInfo.selectedAudioId, isNull);
      platform.events[id]!.add(
        lg.VideoEvent(
          eventType: lg.VideoEventType.trackSelected,
          trackSelectedType: 'audio',
          trackSelectedIndex: 1,
        ),
      );
      expect(adapter.state.mediaInfo.selectedAudioId, '1');
      await adapter.selectSubtitleTrack('0');
      expect(platform.calls, containsAllInOrder(['text:0', 'subtitle:true']));
      expect(adapter.state.mediaInfo.selectedSubtitleId, isNull);
      await adapter.selectSubtitleTrack('off');
      expect(platform.calls.last, 'subtitle:false');
      expect(adapter.state.mediaInfo.selectedSubtitleId, isNull);
      await expectLater(adapter.selectAudioTrack('99'), throwsStateError);
      await expectLater(adapter.selectSubtitleTrack('-1'), throwsStateError);
      await expectLater(adapter.setVolume(10), throwsUnsupportedError);
    },
  );

  test('stop during initialization suppresses stale playback', () async {
    final createdLoad = platform.created.stream.first;
    final loading = adapter.load(item);
    final id = await createdLoad;
    await adapter.stop();
    await loading;
    expect(platform.events[id]!.hasListener, isFalse);
    platform.initialize(id);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.state.status, PlaybackStatus.stopped);
    expect(platform.calls, isNot(contains('play:$id')));
    expect(platform.calls, contains('dispose:$id'));
    final created = platform.created.stream.first;
    final resuming = adapter.play();
    final resumedId = await created;
    platform.initialize(resumedId);
    await resuming;
    expect(adapter.state.status, PlaybackStatus.playing);
  });

  test(
    'disposal cancels initialization, is idempotent and awaits native release',
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
      expect(
        platform.calls.where((call) => call == 'dispose:$id'),
        hasLength(1),
      );
      expect(platform.calls, isNot(contains('play:$id')));
    },
  );

  test(
    'native disposal failures are observable and release is not repeated',
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
      expect(
        platform.calls.where((call) => call == 'dispose:$id'),
        hasLength(1),
      );
    },
  );

  test('a new load clears the old native surface until initialized', () async {
    final first = await beginLoad();
    expect(adapter.buildVideoView(), isNull);
    platform.initialize(first);
    await Future<void>.delayed(Duration.zero);
    final oldView = adapter.buildVideoView();
    expect(oldView, isNotNull);

    final second = await beginLoad();
    expect(adapter.buildVideoView(), isNull);
    platform.initialize(second);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.buildVideoView(), isNotNull);
    expect(adapter.buildVideoView(), isNot(same(oldView)));
  });

  test('pause, seek and stop update playback state', () async {
    final id = await beginLoad();
    platform.initialize(id);
    await Future<void>.delayed(Duration.zero);
    await adapter.pause();
    expect(adapter.state.status, PlaybackStatus.paused);
    await adapter.seek(const Duration(seconds: 10));
    expect(adapter.state.position, const Duration(seconds: 10));
    await adapter.stop();
    expect(adapter.state.status, PlaybackStatus.stopped);
    expect(adapter.state.position, Duration.zero);
    expect(platform.calls, isNot(contains('dispose:$id')));
    await adapter.play();
    expect(platform.nextId, id);
    expect(adapter.state.status, PlaybackStatus.playing);
  });
}
