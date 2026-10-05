import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/app_startup.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';

import '../support/in_memory_settings_repository.dart';

void main() {
  test(
    'initializes storage before preferences and playlist restoration',
    () async {
      final settings = InMemorySettingsRepository();
      final preferences = AppPreferencesController(
        settingsRepository: settings,
      );
      final catalogView = CatalogViewState();
      final navigationController = NavigationController();
      final playlists = PlaylistsController(
        catalogRepository: const FixtureCatalogRepository(),
        catalogQueryService: InMemoryCatalogQueryService('unused', const []),
        settingsRepository: settings,
        catalogView: catalogView,
        navigationController: navigationController,
        preferencesController: preferences,
      );
      addTearDown(playlists.dispose);
      addTearDown(preferences.dispose);
      addTearDown(catalogView.dispose);
      addTearDown(navigationController.dispose);
      final startup = AppStartup(
        storageInitializer: () async => settings.calls.add('storage'),
        preferencesController: preferences,
        playlistsController: playlists,
      );

      await startup.initialize();
      final events = settings.calls;

      expect(events.first, 'storage');
      expect(events.indexOf('get:show_home_live_tv'), greaterThan(0));
      expect(
        events.indexOf('listPlaylists'),
        greaterThan(events.indexOf('get:verbose_refresh_info')),
      );
      expect(events.last, 'get:active_playlist_id');
    },
  );

  test(
    'restores the saved active playlist after storage initialization',
    () async {
      final settings = InMemorySettingsRepository();
      await settings.upsertPlaylist(
        const PlaylistSourceConfig.url(
          playlistId: 'saved',
          name: 'Saved playlist',
          url: 'https://fixture.test/saved.m3u',
        ),
      );
      settings.appSettings['active_playlist_id'] = 'saved';
      final preferences = AppPreferencesController(
        settingsRepository: settings,
      );
      final view = CatalogViewState();
      final navigation = NavigationController();
      final playlists = PlaylistsController(
        catalogRepository: const FixtureCatalogRepository(),
        catalogQueryService: InMemoryCatalogQueryService(
          'saved',
          fixtureCatalog,
        ),
        settingsRepository: settings,
        catalogView: view,
        navigationController: navigation,
        preferencesController: preferences,
      );
      addTearDown(playlists.dispose);
      addTearDown(preferences.dispose);
      addTearDown(view.dispose);
      addTearDown(navigation.dispose);
      final startup = AppStartup(
        storageInitializer: () async {},
        preferencesController: preferences,
        playlistsController: playlists,
      );

      await startup.initialize();
      expect(playlists.activePlaylistId, 'saved');
      expect(view.itemCount, fixtureCatalog.length);
      expect(view.homeLive, hasLength(3));
    },
  );

  test('storage failure stops startup before reading settings', () async {
    final settings = InMemorySettingsRepository();
    final preferences = AppPreferencesController(settingsRepository: settings);
    final view = CatalogViewState();
    final navigation = NavigationController();
    final playlists = PlaylistsController(
      catalogRepository: const FixtureCatalogRepository(),
      settingsRepository: settings,
      catalogView: view,
      navigationController: navigation,
      preferencesController: preferences,
    );
    addTearDown(playlists.dispose);
    addTearDown(preferences.dispose);
    addTearDown(view.dispose);
    addTearDown(navigation.dispose);
    final startup = AppStartup(
      storageInitializer: () async => throw StateError('Storage unavailable'),
      preferencesController: preferences,
      playlistsController: playlists,
    );

    await expectLater(startup.initialize(), throwsStateError);
    expect(settings.calls, isEmpty);
  });
}
