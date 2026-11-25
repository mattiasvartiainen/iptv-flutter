import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';

import '../support/catalog_fixtures.dart';
import '../support/controlled_playback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NavigationController navigation;
  late PlaybackAdapter adapter;
  late PlayerController player;

  setUp(() {
    _foregroundApp();
    navigation = NavigationController();
    adapter = FakePlaybackAdapter(transitionDelay: Duration.zero);
    player = PlayerController(
      playbackAdapter: adapter,
      navigationController: navigation,
    );
  });

  tearDown(() async {
    player.dispose();
    await player.disposalComplete;
    navigation.dispose();
    _foregroundApp();
  });

  test('opening a player loads the selected item and starts playing', () async {
    final item = fixtureCatalog.first;

    await player.openPlayer(item);

    expect((navigation.currentRoute as PlayerRoute).item, same(item));
    expect(adapter.state.status, PlaybackStatus.playing);
    expect(adapter.state.item, same(item));
    expect(player.playbackState.value, same(adapter.state));
  });

  test('playback state listenable follows adapter transitions', () async {
    final observedStatuses = <PlaybackStatus>[];
    void recordState() =>
        observedStatuses.add(player.playbackState.value.status);
    player.playbackState.addListener(recordState);
    addTearDown(() => player.playbackState.removeListener(recordState));

    await player.openPlayer(fixtureCatalog.first);

    expect(observedStatuses, contains(PlaybackStatus.loading));
    expect(observedStatuses.last, PlaybackStatus.playing);
  });

  test(
    'controller commands toggle playback, clamp seek, and close session',
    () async {
      await player.openPlayer(fixtureCatalog.first);

      await player.togglePlayPause();
      expect(player.playbackState.value.status, PlaybackStatus.paused);
      await player.togglePlayPause();
      expect(player.playbackState.value.status, PlaybackStatus.playing);

      await player.seekBy(const Duration(seconds: -10));
      expect(player.playbackState.value.position, Duration.zero);
      await player.seekBy(const Duration(seconds: 10));
      expect(player.playbackState.value.position, const Duration(seconds: 10));

      await player.close();
      expect(player.playbackState.value.status, PlaybackStatus.stopped);
    },
  );

  test('load failures become error state and are logged', () async {
    player.dispose();
    final logger = _RecordingLogger();
    adapter = _FailingPlaybackAdapter();
    player = PlayerController(
      playbackAdapter: adapter,
      navigationController: navigation,
      logger: logger,
    );

    await player.openPlayer(fixtureCatalog.first);

    expect(player.playbackState.value.status, PlaybackStatus.error);
    expect(logger.errorEvents, ['playback_load_failed']);
  });

  for (final kind in PlaybackErrorKind.values) {
    test(
      'typed load failure $kind survives controller classification',
      () async {
        player.dispose();
        await player.disposalComplete;
        adapter = _TypedFailingPlaybackAdapter(kind);
        player = PlayerController(
          playbackAdapter: adapter,
          navigationController: navigation,
        );
        await player.openPlayer(fixtureCatalog.first);
        expect(player.playbackState.value.status, PlaybackStatus.error);
        expect(player.playbackState.value.errorKind, kind);
        expect(player.playbackState.value.message, isNull);
      },
    );
  }

  test(
    'surface identity can change or disappear within a controller session',
    () async {
      player.dispose();
      await player.disposalComplete;
      final controlled = ControlledPlayback();
      adapter = controlled;
      player = PlayerController(
        playbackAdapter: adapter,
        navigationController: navigation,
      );
      await player.openPlayer(fixtureCatalog.first);
      controlled.view = const SizedBox(key: ValueKey('first-surface'));
      expect(player.videoView, same(controlled.view));
      controlled.view = const SizedBox(key: ValueKey('second-surface'));
      controlled.emit(controlled.state.copyWith());
      expect(player.videoView, same(controlled.view));
      controlled.view = null;
      controlled.emit(controlled.state.copyWith());
      expect(player.videoView, isNull);
    },
  );

  test(
    'explicit play works without pause capability and unsupported controls stay gated',
    () async {
      player.dispose();
      await player.disposalComplete;
      final controlled = ControlledPlayback(
        capabilities: const PlaybackCapabilities(
          supportsSeek: false,
          supportsPause: false,
          supportsVolume: false,
          supportsDrm: false,
          supportsLiveStreams: true,
        ),
      );
      adapter = controlled;
      player = PlayerController(
        playbackAdapter: adapter,
        navigationController: navigation,
      );
      await player.openPlayer(fixtureCatalog.first);
      await player.close();
      await player.play();
      expect(player.playbackState.value.status, PlaybackStatus.playing);
      await player.pause();
      await player.seekTo(Duration.zero);
      await player.setVolume(50);
      expect(await player.selectTrack('off', subtitle: true), isFalse);
      expect(controlled.calls, [
        'load:${fixtureCatalog.first.id}',
        'stop',
        'load:${fixtureCatalog.first.id}',
      ]);
    },
  );

  test(
    'unsupported selected Live item stops old output and reports the requested item',
    () async {
      player.dispose();
      await player.disposalComplete;
      final controlled = ControlledPlayback(
        capabilities: const PlaybackCapabilities(
          supportsSeek: true,
          supportsPause: true,
          supportsVolume: true,
          supportsDrm: false,
          supportsLiveStreams: false,
        ),
      );
      adapter = controlled;
      player = PlayerController(
        playbackAdapter: adapter,
        navigationController: navigation,
      );
      final vod = fixtureCatalog.firstWhere(
        (item) => item.type == ContentType.vod,
      );
      final live = fixtureCatalog.firstWhere(
        (item) => item.type == ContentType.live,
      );
      await player.openPlayer(vod);
      await player.openPlayer(live);
      expect(controlled.calls, ['load:${vod.id}', 'stop', 'stop']);
      expect(controlled.state.status, PlaybackStatus.stopped);
      expect(player.playbackState.value.status, PlaybackStatus.error);
      expect(player.playbackState.value.item, live);
      expect(player.playbackState.value.errorKind, PlaybackErrorKind.unknown);
    },
  );

  test('exiting the player stops playback and returns to details', () async {
    final item = fixtureCatalog.first;
    navigation.push(DetailsRoute(item));
    await player.openPlayer(item);

    navigation.pop();

    expect(navigation.currentRoute, isA<DetailsRoute>());
    expect(player.playbackState.value.status, PlaybackStatus.stopped);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.state.status, PlaybackStatus.stopped);
  });

  test('resetting navigation away from the player stops playback', () async {
    await player.openPlayer(fixtureCatalog.first);

    navigation.resetTo(const HomeRoute());

    expect(player.playbackState.value.status, PlaybackStatus.stopped);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.state.status, PlaybackStatus.stopped);
  });

  test('the playback spike loads the existing public test item', () async {
    await player.openPlaybackSpike();

    expect(adapter.state.item, same(PlayerController.playbackSpikeItem));
    expect(adapter.state.status, PlaybackStatus.playing);
  });

  test(
    'backgrounding pauses VOD and resumes it only when it was playing',
    () async {
      final vod = fixtureCatalog.firstWhere(
        (item) => item.type == ContentType.vod,
      );
      await player.openPlayer(vod);

      _backgroundApp();
      await Future<void>.delayed(Duration.zero);
      expect(adapter.state.status, PlaybackStatus.paused);

      _foregroundApp();
      await Future<void>.delayed(Duration.zero);
      expect(adapter.state.status, PlaybackStatus.playing);

      await player.pause();
      _backgroundApp();
      _foregroundApp();
      await Future<void>.delayed(Duration.zero);
      expect(adapter.state.status, PlaybackStatus.paused);
    },
  );

  test('backgrounding stops live playback and does not resume it', () async {
    await player.openPlayer(fixtureCatalog.first);

    _backgroundApp();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.state.status, PlaybackStatus.stopped);

    _foregroundApp();
    await Future<void>.delayed(Duration.zero);
    expect(adapter.state.status, PlaybackStatus.stopped);
  });

  test('Back cancels initialization and prevents a late autoplay', () async {
    player.dispose();
    await player.disposalComplete;
    final delayedAdapter = ControlledPlayback();
    final initialization = delayedAdapter.loadGate = Completer<void>();
    adapter = delayedAdapter;
    player = PlayerController(
      playbackAdapter: adapter,
      navigationController: navigation,
    );
    final opening = player.openPlayer(fixtureCatalog.first);
    await Future<void>.delayed(Duration.zero);

    navigation.pop();
    expect(player.playbackState.value.status, PlaybackStatus.stopped);
    await opening;
    await Future<void>.delayed(Duration.zero);
    expect(initialization.isCompleted, isFalse);

    initialization.complete();
    await Future<void>.delayed(Duration.zero);

    expect(navigation.currentRoute, isA<HomeRoute>());
    expect(adapter.state.status, PlaybackStatus.stopped);
    expect(delayedAdapter.calls, isNot(contains('play')));
  });

  test('replacement and same-item retry reject obsolete load errors', () async {
    player.dispose();
    await player.disposalComplete;
    final controlled = ControlledPlayback()..cancelLoads = false;
    adapter = controlled;
    player = PlayerController(
      playbackAdapter: adapter,
      navigationController: navigation,
    );
    final item = fixtureCatalog.first;
    final initialization = controlled.loadGate = Completer<void>();
    final opening = player.openPlayer(item);
    await Future<void>.delayed(Duration.zero);
    final retry = player.openPlayer(item);
    initialization.completeError(StateError('Obsolete load failure'));
    await Future.wait([opening, retry]);
    expect(player.playbackState.value.item, item);
    expect(player.playbackState.value.status, PlaybackStatus.playing);
    expect(controlled.calls.last, 'load:${item.id}');
  });

  for (final type in [ContentType.live, ContentType.vod]) {
    test(
      'backgrounding cancels a pending $type load without later autoplay',
      () async {
        player.dispose();
        await player.disposalComplete;
        final controlled = ControlledPlayback();
        adapter = controlled;
        player = PlayerController(
          playbackAdapter: adapter,
          navigationController: navigation,
        );
        final item = fixtureCatalog.firstWhere((item) => item.type == type);
        final initialization = controlled.loadGate = Completer<void>();
        final opening = player.openPlayer(item);
        await Future<void>.delayed(Duration.zero);
        _backgroundApp();
        await opening;
        await Future<void>.delayed(Duration.zero);
        expect(player.playbackState.value.status, PlaybackStatus.stopped);
        _foregroundApp();
        initialization.complete();
        await Future<void>.delayed(Duration.zero);
        expect(player.playbackState.value.status, PlaybackStatus.stopped);
        await player.play();
        expect(player.playbackState.value.status, PlaybackStatus.playing);
      },
    );
  }

  test('opening while backgrounded does not start native playback', () async {
    _backgroundApp();
    await player.openPlayer(fixtureCatalog.first);
    expect(player.playbackState.value.status, PlaybackStatus.stopped);
    _foregroundApp();
    await Future<void>.delayed(Duration.zero);
    expect(player.playbackState.value.status, PlaybackStatus.stopped);
  });

  test(
    'rapid background and foreground serialize VOD pause and resume',
    () async {
      final vod = fixtureCatalog.firstWhere(
        (item) => item.type == ContentType.vod,
      );
      await player.openPlayer(vod);
      _backgroundApp();
      _foregroundApp();
      await Future<void>.delayed(Duration.zero);
      expect(player.playbackState.value.status, PlaybackStatus.playing);
    },
  );

  test('foreground never resumes a replaced VOD session', () async {
    final vod = fixtureCatalog.firstWhere(
      (item) => item.type == ContentType.vod,
    );
    await player.openPlayer(vod);
    _backgroundApp();
    await Future<void>.delayed(Duration.zero);
    await player.openPlayer(fixtureCatalog.first);
    _foregroundApp();
    await Future<void>.delayed(Duration.zero);
    expect(player.playbackState.value.status, PlaybackStatus.stopped);
    expect(player.playbackState.value.item, fixtureCatalog.first);
  });

  test(
    'disposal prevents navigation, commands and registered Back callbacks',
    () async {
      await player.openPlayer(fixtureCatalog.first);
      var backCalled = false;
      player.registerBackRequestHandler(Object(), () => backCalled = true);
      final route = navigation.currentRoute;
      player.dispose();
      final cleanup = player.disposalComplete;
      player.dispose();
      expect(player.disposalComplete, same(cleanup));
      await player.openPlayer(fixtureCatalog.last);
      await player.play();
      await player.pause();
      await player.seekTo(Duration.zero);
      expect(navigation.currentRoute, same(route));
      expect(player.handleBackRequest(), isFalse);
      expect(backCalled, isFalse);
      await cleanup;
    },
  );
  test('controller disposal completion waits for native cleanup', () async {
    player.dispose();
    await player.disposalComplete;
    final controlled = ControlledPlayback();
    final cleanup = controlled.disposalGate = Completer<void>();
    adapter = controlled;
    player = PlayerController(
      playbackAdapter: adapter,
      navigationController: navigation,
    );
    await player.openPlayer(fixtureCatalog.first);
    var done = false;
    player.dispose();
    final completion = player.disposalComplete.then((_) => done = true);
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    expect(player.videoView, isNull);
    cleanup.complete();
    await completion;
    expect(controlled.calls.where((call) => call == 'dispose'), hasLength(1));
  });

  test(
    'controller disposal failures remain observable and are logged',
    () async {
      final controlled = ControlledPlayback()
        ..disposalError = StateError('Cleanup failed');
      final logger = _RecordingLogger();
      final controller = PlayerController(
        playbackAdapter: controlled,
        navigationController: navigation,
        logger: logger,
      );
      controller.dispose();
      await expectLater(controller.disposalComplete, throwsStateError);
      expect(logger.errorEvents, ['playback_dispose_failed']);
      expect(controlled.calls, ['dispose']);
    },
  );
}

void _sendLifecycleState(AppLifecycleState state) {
  TestWidgetsFlutterBinding.ensureInitialized().handleAppLifecycleStateChanged(
    state,
  );
}

void _backgroundApp() {
  _sendLifecycleState(AppLifecycleState.inactive);
  _sendLifecycleState(AppLifecycleState.hidden);
  _sendLifecycleState(AppLifecycleState.paused);
}

void _foregroundApp() {
  final lifecycleState = WidgetsBinding.instance.lifecycleState;
  if (lifecycleState == AppLifecycleState.paused) {
    _sendLifecycleState(AppLifecycleState.hidden);
  }
  final stateAfterHidden = WidgetsBinding.instance.lifecycleState;
  if (stateAfterHidden == AppLifecycleState.hidden) {
    _sendLifecycleState(AppLifecycleState.inactive);
  }
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    _sendLifecycleState(AppLifecycleState.resumed);
  }
}

class _FailingPlaybackAdapter extends FakePlaybackAdapter {
  @override
  Future<void> load(ContentItem item) async {
    throw StateError('Playback unavailable');
  }
}

class _TypedFailingPlaybackAdapter extends FakePlaybackAdapter {
  _TypedFailingPlaybackAdapter(this.kind);
  final PlaybackErrorKind kind;
  @override
  Future<void> load(ContentItem item) async => throw PlaybackException(kind);
}

class _RecordingLogger implements AppLogger {
  final List<String> errorEvents = [];

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {
    errorEvents.add(message);
  }

  @override
  void info(String message, {Map<String, Object?> context = const {}}) {}

  @override
  void warning(String message, {Map<String, Object?> context = const {}}) {}
}
