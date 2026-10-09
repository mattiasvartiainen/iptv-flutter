import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app.dart';
import 'package:iptv_flutter/app/app_dependencies.dart';
import 'package:iptv_flutter/app/app_shortcuts.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/player_controller.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';

import '../support/in_memory_settings_repository.dart';

typedef _Controllers = ({
  AppController app,
  PlayerController player,
  PlaylistsController playlists,
  AppPreferencesController preferences,
});

_Controllers _createControllers({
  required SettingsRepository settings,
  required PlaybackAdapter playbackAdapter,
  required CatalogQueryService catalogQueryService,
}) {
  final catalogView = CatalogViewState();
  final navigation = NavigationController();
  final preferences = AppPreferencesController(settingsRepository: settings);
  final playlists = PlaylistsController(
    catalogRepository: const FixtureCatalogRepository(),
    catalogQueryService: catalogQueryService,
    settingsRepository: settings,
    catalogView: catalogView,
    navigationController: navigation,
    preferencesController: preferences,
  );
  final app = AppController(
    catalogView: catalogView,
    navigationController: navigation,
  );
  final player = PlayerController(
    playbackAdapter: playbackAdapter,
    navigationController: navigation,
  );
  return (
    app: app,
    player: player,
    playlists: playlists,
    preferences: preferences,
  );
}

void _disposeControllers(_Controllers controllers) {
  controllers.player.dispose();
  controllers.playlists.dispose();
  controllers.preferences.dispose();
  controllers.app.catalogView.dispose();
  controllers.app.navigationController.dispose();
}

Future<_Controllers> _pumpLoadedApp(
  WidgetTester tester, {
  PlaybackAdapter? playbackAdapter,
  Map<ShortcutActivator, Intent> extraShortcuts = const {},
}) async {
  final settings = InMemorySettingsRepository();
  final playlist = await settings.upsertPlaylist(
    const PlaylistSourceConfig.url(
      name: 'Fixture',
      url: 'https://fixture.test/playlist.m3u',
    ),
  );
  final queryService = InMemoryCatalogQueryService(
    playlist.playlistId,
    fixtureCatalog,
  );
  final adapter =
      playbackAdapter ??
      FakePlaybackAdapter(transitionDelay: const Duration(milliseconds: 1));
  final controllers = _createControllers(
    settings: settings,
    playbackAdapter: adapter,
    catalogQueryService: queryService,
  );
  addTearDown(() => _disposeControllers(controllers));

  await tester.pumpWidget(
    IptvApp(
      dependencies: AppDependencies.forTesting(
        appController: controllers.app,
        playerController: controllers.player,
        playlistsController: controllers.playlists,
        preferencesController: controllers.preferences,
        extraShortcuts: extraShortcuts,
      ),
    ),
  );
  await controllers.playlists.loadPlaylist(
    playlist.playlistId,
    intent: PlaylistLoadIntent.setup,
  );
  await tester.pumpAndSettle();
  return controllers;
}

void main() {
  testWidgets('Select and gamepad-A activate the focused Home tile', (
    tester,
  ) async {
    final controllers = await _pumpLoadedApp(tester);
    Focus.of(tester.element(find.text('News 24'))).requestFocus();
    await tester.pumpAndSettle();
    expect(controllers.app.navigationController.currentRoute, isA<HomeRoute>());

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(
      (controllers.app.navigationController.currentRoute as DetailsRoute)
          .item
          .id,
      'news-24',
    );

    controllers.app.goBack();
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Northbound'))).requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.gameButtonA);
    await tester.pumpAndSettle();
    expect(
      (controllers.app.navigationController.currentRoute as DetailsRoute)
          .item
          .id,
      'northbound',
    );
  });

  testWidgets('Back dismisses a modal before popping the app route', (
    tester,
  ) async {
    final controllers = await _pumpLoadedApp(tester);
    controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(AppShell));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Modal')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Modal'), findsNothing);
    expect(
      controllers.app.navigationController.currentRoute,
      isA<CatalogRoute>(),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controllers.app.navigationController.currentRoute, isA<HomeRoute>());
  });

  testWidgets('root permits exit while nested routes retain the app', (
    tester,
  ) async {
    final controllers = await _pumpLoadedApp(tester);
    final popScope = find.byWidgetPredicate((widget) => widget is PopScope);
    expect((tester.widget(popScope) as PopScope).canPop, isTrue);

    controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    expect((tester.widget(popScope) as PopScope).canPop, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controllers.app.navigationController.currentRoute, isA<HomeRoute>());
    expect(find.byType(IptvApp), findsOneWidget);
  });

  testWidgets('profile shortcut overrides are installed at the app root', (
    tester,
  ) async {
    final controllers = await _pumpLoadedApp(
      tester,
      extraShortcuts: {
        const SingleActivator(LogicalKeyboardKey.f12): const BackIntent(),
      },
    );
    controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pumpAndSettle();

    expect(controllers.app.navigationController.currentRoute, isA<HomeRoute>());
  });

  testWidgets('unmapped keys do not change routes or playback', (tester) async {
    final controllers = await _pumpLoadedApp(tester);
    final route = controllers.app.navigationController.currentRoute;
    await tester.sendKeyEvent(LogicalKeyboardKey.f12);
    await tester.pumpAndSettle();

    expect(controllers.app.navigationController.currentRoute, same(route));
    expect(
      controllers.player.playbackAdapter.state.status,
      PlaybackStatus.idle,
    );
  });

  testWidgets('media keys are handled only on the active player route', (
    tester,
  ) async {
    final controllers = await _pumpLoadedApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(
      controllers.player.playbackAdapter.state.status,
      PlaybackStatus.idle,
    );

    final openingPlayer = controllers.player.openPlayer(fixtureCatalog.first);
    await tester.pump(const Duration(milliseconds: 1));
    await openingPlayer;
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
    await tester.pumpAndSettle();
    expect(
      controllers.player.playbackAdapter.state.status,
      PlaybackStatus.paused,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
    await tester.pumpAndSettle();
    expect(
      controllers.player.playbackAdapter.state.status,
      PlaybackStatus.playing,
    );
  });

  testWidgets('unsupported player commands are safe no-ops', (tester) async {
    final adapter = _PlaybackAdapterWithoutMediaControls();
    final controllers = await _pumpLoadedApp(tester, playbackAdapter: adapter);
    final openingPlayer = controllers.player.openPlayer(fixtureCatalog.first);
    await tester.pump(const Duration(milliseconds: 1));
    await openingPlayer;
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
    await tester.pumpAndSettle();

    expect(adapter.state.status, PlaybackStatus.playing);
    expect(adapter.pauseCalls, 0);
    expect(adapter.seekCalls, 0);
  });
}

class _PlaybackAdapterWithoutMediaControls implements PlaybackAdapter {
  final FakePlaybackAdapter _delegate = FakePlaybackAdapter(
    transitionDelay: const Duration(milliseconds: 1),
  );
  int pauseCalls = 0;
  int seekCalls = 0;

  @override
  PlaybackCapabilities get capabilities => const PlaybackCapabilities(
    supportsSeek: false,
    supportsPause: false,
    supportsVolume: false,
    supportsDrm: false,
    supportsLiveStreams: true,
  );

  @override
  PlaybackState get state => _delegate.state;

  @override
  Stream<PlaybackState> get states => _delegate.states;

  @override
  Widget? buildVideoView() => _delegate.buildVideoView();

  @override
  Future<void> load(ContentItem item) => _delegate.load(item);

  @override
  Future<void> play() => _delegate.play();

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() => _delegate.stop();

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
  }

  @override
  Future<void> setVolume(double volume) => _delegate.setVolume(volume);

  @override
  void dispose() => _delegate.dispose();
}
