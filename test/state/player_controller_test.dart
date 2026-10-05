import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';
import 'package:iptv_flutter/state/player_controller.dart';

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
