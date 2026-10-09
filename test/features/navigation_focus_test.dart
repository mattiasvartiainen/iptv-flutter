import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app.dart';
import 'package:iptv_flutter/app/app_dependencies.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';

import '../support/in_memory_settings_repository.dart';

typedef _NavigationHarness = ({
  AppController app,
  NavigationController navigation,
  PlayerController player,
  PlaylistsController playlists,
  AppPreferencesController preferences,
  CatalogViewState catalog,
});

void _disposeHarness(_NavigationHarness harness) {
  harness.player.dispose();
  harness.playlists.dispose();
  harness.preferences.dispose();
  harness.catalog.dispose();
  harness.navigation.dispose();
}

Future<_NavigationHarness> _pumpRemoteFirstApp(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final settings = InMemorySettingsRepository();
  const playlistId = 'cross-device-focus-playlist';
  await settings.upsertPlaylist(
    const PlaylistSourceConfig.url(
      playlistId: playlistId,
      name: 'Focus fixture',
      url: 'https://fixture.test/focus.m3u',
    ),
  );
  final catalog = CatalogViewState();
  final navigation = NavigationController();
  final preferences = AppPreferencesController(settingsRepository: settings);
  final playlists = PlaylistsController(
    catalogRepository: const FixtureCatalogRepository(),
    catalogQueryService: InMemoryCatalogQueryService(
      playlistId,
      fixtureCatalog,
    ),
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
    playbackAdapter: FakePlaybackAdapter(),
    navigationController: navigation,
  );
  final harness = (
    app: app,
    navigation: navigation,
    player: player,
    playlists: playlists,
    preferences: preferences,
    catalog: catalog,
  );
  addTearDown(() => _disposeHarness(harness));

  await tester.pumpWidget(
    IptvApp(
      dependencies: AppDependencies.forTesting(
        appController: app,
        playerController: player,
        playlistsController: playlists,
        preferencesController: preferences,
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.remote,
          hasHardwareBack: false,
          supportsHover: false,
        ),
      ),
    ),
  );
  await playlists.refreshPlaylists();
  await playlists.loadPlaylist(playlistId, intent: PlaylistLoadIntent.setup);
  await tester.pumpAndSettle();
  return harness;
}

MediaTile? _focusedTile() => FocusManager.instance.primaryFocus?.context
    ?.findAncestorWidgetOfExactType<MediaTile>();

void main() {
  testWidgets('remote-first navigation adapts across the viewport matrix', (
    tester,
  ) async {
    final harness = await _pumpRemoteFirstApp(tester);
    final matrix = [
      (size: const Size(390, 844), compact: true, extended: false),
      (size: const Size(800, 360), compact: true, extended: false),
      (size: const Size(800, 1000), compact: false, extended: false),
      (size: const Size(1440, 900), compact: false, extended: true),
      (size: const Size(1920, 1080), compact: false, extended: true),
    ];

    for (final viewport in matrix) {
      tester.view.physicalSize = viewport.size;
      await tester.pumpAndSettle();
      expect(
        find.byType(NavigationBar),
        viewport.compact ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(NavigationRail),
        viewport.compact ? findsNothing : findsOneWidget,
      );
      if (!viewport.compact) {
        expect(
          tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
          viewport.extended,
        );
      }
      expect(
        Theme.of(
          tester.element(find.byType(AppShell)),
        ).textTheme.bodyMedium?.fontSize,
        18,
      );
      expect(tester.takeException(), isNull);
    }

    harness.app.openMovies();
    await tester.pumpAndSettle();
    final movie = harness.catalog.items.items.first;
    expect(_focusedTile()?.title, movie.title);
    expect(find.text(movie.title), findsOneWidget);
  });

  testWidgets(
    'rail and bottom navigation move focus into content and Back restores it',
    (tester) async {
      final harness = await _pumpRemoteFirstApp(tester);
      const movieRoute = CatalogRoute(CatalogItemKind.movie);

      tester.view.physicalSize = const Size(1440, 900);
      harness.app.openMovies();
      await tester.pumpAndSettle();
      final movie = harness.catalog.items.items.first;
      final railLiveLabel = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.text('Live'),
      );
      Focus.of(tester.element(railLiveLabel)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_focusedTile(), isNotNull);
      expect(_focusedTile()?.title, movie.title);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(harness.navigation.currentRoute, isA<DetailsRoute>());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(harness.navigation.currentRoute, same(movieRoute));
      expect(_focusedTile()?.title, movie.title);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      final liveDestination = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Live'),
      );
      Focus.of(tester.element(liveDestination)).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(_focusedTile(), isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact touch navigation reaches Search and Settings', (
    tester,
  ) async {
    final harness = await _pumpRemoteFirstApp(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(harness.navigation.currentRoute, isA<SearchRoute>());
    expect(find.byType(EditableText), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(harness.navigation.currentRoute, isA<SettingsRoute>());
    expect(tester.takeException(), isNull);
  });
}
