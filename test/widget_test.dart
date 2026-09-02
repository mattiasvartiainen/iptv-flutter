import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/state/app_controller.dart';

void main() {
  Future<(AppController, String)> pumpLoadedApp(WidgetTester tester) async {
    final settings = _TestSettingsRepository();
    final playlist = await settings.upsertPlaylist(
      const PlaylistSourceConfig.url(
        name: 'Fixture',
        url: 'https://fixture.test/playlist.m3u',
      ),
    );
    final controller = AppController(
      catalogRepository: const FixtureCatalogRepository(),
      catalogQueryService: InMemoryCatalogQueryService(
        playlist.playlistId,
        fixtureCatalog,
      ),
      settingsRepository: settings,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(IptvApp(controller: controller));
    await controller.loadPlaylist(
      playlist.playlistId,
      policy: CatalogLoadPolicy.networkOnly,
    );
    await tester.pumpAndSettle();
    return (controller, playlist.playlistId);
  }

  testWidgets('home rows render preview pages from the query service', (
    tester,
  ) async {
    final (controller, _) = await pumpLoadedApp(tester);

    expect(controller.catalogItemCount, 5);
    expect(controller.catalogView.homeLive, hasLength(3));
    expect(controller.catalogView.homeMovies, hasLength(2));
    expect(find.text('News 24'), findsOneWidget);
    expect(find.text('Northbound'), findsOneWidget);
  });

  testWidgets('See all opens a paged grid backed by a catalog query', (
    tester,
  ) async {
    final (controller, _) = await pumpLoadedApp(tester);

    await tester.tap(find.widgetWithText(TextButton, 'See all').first);
    await tester.pumpAndSettle();

    expect(controller.screen, AppScreen.liveCatalog);
    expect(controller.catalogView.items.items, hasLength(3));
    expect(controller.catalogView.items.hasMore, isFalse);
    expect(find.text('News 24'), findsOneWidget);
    expect(find.text('World Sports'), findsOneWidget);
    expect(find.text('Northbound'), findsNothing);
  });

  testWidgets('selecting a grid tile loads the full item for details', (
    tester,
  ) async {
    final (controller, _) = await pumpLoadedApp(tester);

    await tester.tap(find.widgetWithText(TextButton, 'See all').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('News 24'));
    await tester.pumpAndSettle();

    expect(controller.screen, AppScreen.details);
    expect(controller.selectedItem?.id, 'news-24');
    expect(
      controller.selectedItem?.streamUrl,
      'https://example.invalid/live/news-24.m3u8',
    );
  });
}

class _TestSettingsRepository implements SettingsRepository {
  final Map<String, String> _appSettings = {};
  final Map<String, ManagedPlaylist> _playlists = {};
  final Map<String, String> _urls = {};

  @override
  Future<String?> getAppSetting(String key) async {
    return switch (key) {
      'show_home_live_tv' => 'true',
      'show_home_movies' => 'true',
      'show_home_series' => 'true',
      _ => _appSettings[key],
    };
  }

  @override
  Future<void> setAppSetting(String key, String value) async {
    _appSettings[key] = value;
  }

  @override
  Future<List<ManagedPlaylist>> listPlaylists() async =>
      _playlists.values.toList(growable: false);

  @override
  Future<ManagedPlaylist?> getPlaylist(String playlistId) async =>
      _playlists[playlistId];

  @override
  Future<ManagedPlaylist> upsertPlaylist(PlaylistSourceConfig config) async {
    final id = config.playlistId ?? 'playlist-${_playlists.length + 1}';
    final playlist = ManagedPlaylist(
      playlistId: id,
      name: config.name,
      enabled: true,
      sourceConfig: config,
      sourceKind: config.kind,
      sourceSummary: config.summary,
      resolvedUrl: config.resolvedUrl,
      sourceUrlRedacted: null,
      lastImportStatus: null,
      lastImportWarning: null,
      lastImportCompletedAt: null,
      refreshSettings: null,
    );
    _playlists[id] = playlist;
    _urls[id] = config.resolvedUrl;
    return playlist;
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _playlists.remove(playlistId);
    _urls.remove(playlistId);
  }

  @override
  Future<String?> resolvePlaylistUrl(String playlistId) async =>
      _urls[playlistId];

  @override
  Future<PlaylistRefreshSettings?> getPlaylistRefreshSettings(
    String playlistId,
  ) async => null;

  @override
  Future<bool> isCategoryHidden({
    required String playlistId,
    required String categoryId,
    String? profileId,
  }) async => false;

  @override
  Future<void> setCategoryHidden({
    required String playlistId,
    required String categoryId,
    required bool hidden,
    String? profileId,
  }) async {}

  @override
  Future<void> upsertPlaylistRefreshSettings(
    PlaylistRefreshSettings settings,
  ) async {}
}
