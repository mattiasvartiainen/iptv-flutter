import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app.dart';
import 'package:iptv_flutter/app/app_dependencies.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';

import 'catalog_fixtures.dart';
import 'in_memory_settings_repository.dart';

typedef TestAppControllers = ({
  AppController app,
  PlayerController player,
  PlaylistsController playlists,
  AppPreferencesController preferences,
});

class TestAppHarness {
  const TestAppHarness({
    required this.controllers,
    required this.settings,
    required this.playlistId,
  });

  final TestAppControllers controllers;
  final SettingsRepository settings;
  final String? playlistId;
}

TestAppControllers createTestControllers({
  required CatalogRepository catalogRepository,
  CatalogQueryService? catalogQueryService,
  required SettingsRepository settingsRepository,
  required PlaybackAdapter playbackAdapter,
}) {
  final catalogView = CatalogViewState();
  final navigationController = NavigationController();
  final preferences = AppPreferencesController(
    settingsRepository: settingsRepository,
  );
  final playlists = PlaylistsController(
    catalogRepository: catalogRepository,
    catalogQueryService: catalogQueryService,
    settingsRepository: settingsRepository,
    catalogView: catalogView,
    navigationController: navigationController,
    preferencesController: preferences,
  );
  final app = AppController(
    catalogView: catalogView,
    navigationController: navigationController,
  );
  final player = PlayerController(
    playbackAdapter: playbackAdapter,
    navigationController: navigationController,
  );
  return (
    app: app,
    player: player,
    playlists: playlists,
    preferences: preferences,
  );
}

void disposeTestControllers(TestAppControllers controllers) {
  controllers.player.dispose();
  controllers.playlists.dispose();
  controllers.preferences.dispose();
  controllers.app.catalogView.dispose();
  controllers.app.navigationController.dispose();
}

Future<TestAppHarness> pumpIptvApp(
  WidgetTester tester, {
  SettingsRepository? settingsRepository,
  CatalogRepository? catalogRepository,
  CatalogQueryService? catalogQueryService,
  PlaybackAdapter? playbackAdapter,
  PlatformCapabilities capabilities = const PlatformCapabilities(
    primaryInput: PrimaryInput.touch,
    hasHardwareBack: true,
    supportsHover: false,
  ),
  Map<ShortcutActivator, Intent> extraShortcuts = const {},
  bool loadFixturePlaylist = true,
  ContentItem? initialPlayerItem,
  String playlistId = 'test-fixture-playlist',
  Size? size,
  double textScale = 1,
}) async {
  final settings = settingsRepository ?? InMemorySettingsRepository();
  final playlist = loadFixturePlaylist
      ? await settings.upsertPlaylist(
          PlaylistSourceConfig.url(
            playlistId: playlistId,
            name: 'Fixture',
            url: 'https://fixture.test/playlist.m3u',
          ),
        )
      : null;
  final effectivePlaylistId = playlist?.playlistId;
  final queries =
      catalogQueryService ??
      (effectivePlaylistId == null
          ? null
          : InMemoryCatalogQueryService(effectivePlaylistId, fixtureCatalog));
  final controllers = createTestControllers(
    catalogRepository: catalogRepository ?? const FixtureCatalogRepository(),
    catalogQueryService: queries,
    settingsRepository: settings,
    playbackAdapter: playbackAdapter ?? FakePlaybackAdapter(),
  );
  addTearDown(() => disposeTestControllers(controllers));

  if (size != null) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: IptvApp(
        dependencies: AppDependencies.forTesting(
          appController: controllers.app,
          playerController: controllers.player,
          playlistsController: controllers.playlists,
          preferencesController: controllers.preferences,
          capabilities: capabilities,
          extraShortcuts: extraShortcuts,
        ),
      ),
    ),
  );

  if (playlist != null) {
    await controllers.playlists.loadPlaylist(
      playlist.playlistId,
      intent: PlaylistLoadIntent.setup,
    );
  }
  if (initialPlayerItem != null) {
    await controllers.player.openPlayer(initialPlayerItem);
  }
  await tester.pumpAndSettle();

  return TestAppHarness(
    controllers: controllers,
    settings: settings,
    playlistId: effectivePlaylistId,
  );
}
