import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';

void main() {
  late NavigationController navigation;
  late FakePlaybackAdapter adapter;
  late PlayerController player;

  setUp(() {
    navigation = NavigationController();
    adapter = FakePlaybackAdapter(transitionDelay: Duration.zero);
    player = PlayerController(
      playbackAdapter: adapter,
      navigationController: navigation,
    );
  });

  tearDown(() {
    player.dispose();
    navigation.dispose();
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

  test('exiting the player stops playback and returns to details', () async {
    final item = fixtureCatalog.first;
    navigation.push(DetailsRoute(item));
    await player.openPlayer(item);

    navigation.pop();

    expect(navigation.currentRoute, isA<DetailsRoute>());
    expect(adapter.state.status, PlaybackStatus.stopped);
  });

  test('resetting navigation away from the player stops playback', () async {
    await player.openPlayer(fixtureCatalog.first);

    navigation.resetTo(const HomeRoute());

    expect(adapter.state.status, PlaybackStatus.stopped);
  });

  test('the playback spike loads the existing public test item', () async {
    await player.openPlaybackSpike();

    expect(adapter.state.item, same(PlayerController.playbackSpikeItem));
    expect(adapter.state.status, PlaybackStatus.playing);
  });

  test('a late load completion after exit is stopped again', () async {
    player.dispose();
    final delayedAdapter = _DelayedPlaybackAdapter();
    adapter = delayedAdapter;
    player = PlayerController(
      playbackAdapter: adapter,
      navigationController: navigation,
    );
    final opening = player.openPlayer(fixtureCatalog.first);

    navigation.pop();
    expect(adapter.state.status, PlaybackStatus.stopped);
    expect(delayedAdapter.stopCount, 1);

    delayedAdapter.completeLoad.complete();
    await opening;

    expect(navigation.currentRoute, isA<HomeRoute>());
    expect(adapter.state.status, PlaybackStatus.stopped);
    expect(delayedAdapter.stopCount, 2);
  });
}

class _DelayedPlaybackAdapter extends FakePlaybackAdapter {
  _DelayedPlaybackAdapter() : super(transitionDelay: Duration.zero);

  final completeLoad = Completer<void>();
  int stopCount = 0;

  @override
  Future<void> load(ContentItem item) async {
    await completeLoad.future;
    await super.load(item);
  }

  @override
  Future<void> stop() {
    stopCount++;
    return super.stop();
  }
}

class _FailingPlaybackAdapter extends FakePlaybackAdapter {
  @override
  Future<void> load(ContentItem item) async {
    throw StateError('Playback unavailable');
  }
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
