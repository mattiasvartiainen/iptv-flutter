import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app.dart';
import 'package:iptv_flutter/app/app_dependencies.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
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

typedef _FocusHarness = ({
  AppController app,
  PlayerController player,
  PlaylistsController playlists,
  AppPreferencesController preferences,
  CatalogViewState catalog,
});

void _disposeHarness(_FocusHarness harness) {
  harness.player.dispose();
  harness.playlists.dispose();
  harness.preferences.dispose();
  harness.catalog.dispose();
  harness.app.navigationController.dispose();
}

Future<_FocusHarness> _pumpLoadedApp(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 900);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final settings = InMemorySettingsRepository();
  const playlistId = 'navigation-focus-playlist';
  await settings.upsertPlaylist(
    const PlaylistSourceConfig.url(
      playlistId: playlistId,
      name: 'Fixture',
      url: 'https://fixture.test/playlist.m3u',
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
  testWidgets('Home and Catalog focus their first available tile', (
    tester,
  ) async {
    final harness = await _pumpLoadedApp(tester);
    expect(_focusedTile()?.title, harness.catalog.homeLive.first.title);

    harness.app.openMovies();
    await tester.pumpAndSettle();
    final firstMovie = harness.catalog.items.items.first;
    expect(_focusedTile()?.title, firstMovie.title);

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(_focusedTile()?.title, firstMovie.title);
  });

  testWidgets('Home falls back to its next populated section after removal', (
    tester,
  ) async {
    final harness = await _pumpLoadedApp(tester);
    expect(_focusedTile()?.title, harness.catalog.homeLive.first.title);

    await harness.preferences.setShowHomeLiveTv(false);
    await tester.pumpAndSettle();

    expect(_focusedTile()?.title, harness.catalog.homeMovies.first.title);
  });

  testWidgets('Details focuses Play and Back restores the prior catalog tile', (
    tester,
  ) async {
    final harness = await _pumpLoadedApp(tester);
    harness.app.openMovies();
    await tester.pumpAndSettle();
    final focusedItem = harness.catalog.items.items.first;
    expect(_focusedTile()?.title, focusedItem.title);

    await harness.app.openDetailsById(focusedItem.id);
    await tester.pumpAndSettle();
    final playLabel = find.text('Play selected stream');
    expect(playLabel, findsOneWidget);
    expect(Focus.of(tester.element(playLabel)).hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(harness.app.navigationController.currentRoute, isA<CatalogRoute>());
    expect(_focusedTile()?.title, focusedItem.title);
  });

  testWidgets(
    'Search focuses its field and settings dialogs focus their entry action',
    (tester) async {
      final harness = await _pumpLoadedApp(tester);
      harness.app.openSearch();
      await tester.pumpAndSettle();
      final searchField = find.byType(EditableText);
      expect(
        identical(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>(),
          tester.widget<EditableText>(searchField),
        ),
        isTrue,
      );

      harness.app.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add playlist'));
      await tester.pumpAndSettle();
      final nameField = find
          .descendant(
            of: find.byType(AlertDialog).last,
            matching: find.byType(EditableText),
          )
          .first;
      expect(
        identical(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<EditableText>(),
          tester.widget<EditableText>(nameField),
        ),
        isTrue,
        reason:
            'Primary focus is ${FocusManager.instance.primaryFocus}; '
            'context widget is '
            '${FocusManager.instance.primaryFocus?.context?.widget.runtimeType}.',
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Add playlist'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(harness.app.navigationController.currentRoute, isA<SearchRoute>());

      harness.app.openSettings();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();
      final deleteAction = find.text('Delete').last;
      expect(Focus.of(tester.element(deleteAction)).hasPrimaryFocus, isTrue);
    },
  );
}
