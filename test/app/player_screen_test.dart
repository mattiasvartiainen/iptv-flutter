import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app.dart';
import 'package:iptv_flutter/app/app_dependencies.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';

import '../support/in_memory_settings_repository.dart';

typedef _PlayerHarness = ({
  NavigationController navigation,
  PlayerController player,
  PlaylistsController playlists,
  AppPreferencesController preferences,
  CatalogViewState catalog,
});

void _disposeHarness(_PlayerHarness harness) {
  harness.player.dispose();
  harness.playlists.dispose();
  harness.preferences.dispose();
  harness.catalog.dispose();
  harness.navigation.dispose();
}

Future<_PlayerHarness> _pumpPlayerApp(
  WidgetTester tester, {
  Size size = const Size(1280, 720),
  double textScale = 1,
  PlaybackAdapter? playbackAdapter,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final settings = InMemorySettingsRepository();
  final catalog = CatalogViewState();
  final navigation = NavigationController();
  final preferences = AppPreferencesController(settingsRepository: settings);
  final playlists = PlaylistsController(
    catalogRepository: const FixtureCatalogRepository(),
    settingsRepository: settings,
    catalogView: catalog,
    navigationController: navigation,
    preferencesController: preferences,
  );
  final app = AppController(
    catalogView: catalog,
    navigationController: navigation,
  );
  final player = PlayerController(
    playbackAdapter:
        playbackAdapter ??
        FakePlaybackAdapter(transitionDelay: const Duration(milliseconds: 1)),
    navigationController: navigation,
  );
  final harness = (
    navigation: navigation,
    player: player,
    playlists: playlists,
    preferences: preferences,
    catalog: catalog,
  );
  addTearDown(() => _disposeHarness(harness));

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: IptvApp(
        dependencies: AppDependencies.forTesting(
          appController: app,
          playerController: player,
          playlistsController: playlists,
          preferencesController: preferences,
        ),
      ),
    ),
  );
  final opening = player.openPlayer(fixtureCatalog.first);
  await tester.pump(const Duration(milliseconds: 1));
  await opening;
  await tester.pumpAndSettle();
  return harness;
}

bool _controlsAreIgnoringInput(WidgetTester tester) => tester
    .widget<IgnorePointer>(
      find.byKey(const ValueKey<String>('player-controls')),
    )
    .ignoring;

void main() {
  testWidgets('player renders fullscreen video surface and readable overlay', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(Scaffold), findsWidgets);
    expect(find.text(fixtureCatalog.first.title), findsOneWidget);
    expect(find.text('Playing'), findsOneWidget);
    expect(find.byIcon(Icons.ondemand_video), findsOneWidget);
    expect(_controlsAreIgnoringInput(tester), isFalse);
    expect(harness.navigation.currentRoute, isA<PlayerRoute>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('controls auto-hide and a media key reveals and pauses', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(tester);
    expect(_controlsAreIgnoringInput(tester), isFalse);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsAreIgnoringInput(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(_controlsAreIgnoringInput(tester), isFalse);
    expect(harness.player.playbackState.value.status, PlaybackStatus.paused);
  });

  testWidgets('player Back hides controls before closing playback', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_controlsAreIgnoringInput(tester), isTrue);
    expect(harness.navigation.currentRoute, isA<PlayerRoute>());
    expect(harness.player.playbackState.value.status, PlaybackStatus.playing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(harness.navigation.currentRoute, isA<HomeRoute>());
    expect(harness.player.playbackState.value.status, PlaybackStatus.stopped);
  });

  testWidgets('system Back hides the overlay before leaving the player', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_controlsAreIgnoringInput(tester), isTrue);
    expect(harness.navigation.currentRoute, isA<PlayerRoute>());

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(harness.navigation.currentRoute, isA<HomeRoute>());
    expect(harness.player.playbackState.value.status, PlaybackStatus.stopped);
  });

  testWidgets('playback error panel retries through the player controller', (
    tester,
  ) async {
    final adapter = _RecoveringPlaybackAdapter();
    final harness = await _pumpPlayerApp(tester, playbackAdapter: adapter);
    expect(harness.player.playbackState.value.status, PlaybackStatus.error);
    expect(find.text('Playback failed.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(harness.player.playbackState.value.status, PlaybackStatus.playing);
    expect(find.text('Playback failed.'), findsNothing);
  });

  testWidgets('focused controls stay visible and compact large text fits', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(
      tester,
      size: const Size(390, 844),
      textScale: 2,
    );
    final pause = find.byTooltip('Pause');
    Focus.of(tester.element(pause)).requestFocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(_controlsAreIgnoringInput(tester), isFalse);
    expect(harness.navigation.currentRoute, isA<PlayerRoute>());
    expect(tester.takeException(), isNull);
  });
}

class _RecoveringPlaybackAdapter extends FakePlaybackAdapter {
  _RecoveringPlaybackAdapter()
    : super(transitionDelay: const Duration(milliseconds: 1));

  int _loadCount = 0;

  @override
  Future<void> load(ContentItem item) async {
    if (_loadCount++ == 0) throw StateError('temporary playback failure');
    await super.load(item);
  }
}
