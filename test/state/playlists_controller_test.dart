import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/errors/app_issue.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';

import '../support/in_memory_settings_repository.dart';

void main() {
  test(
    'loading a playlist activates it and binds the catalog query view',
    () async {
      const playlistId = 'active-playlist';
      final settings = InMemorySettingsRepository();
      await settings.upsertPlaylist(
        const PlaylistSourceConfig.url(
          playlistId: playlistId,
          name: 'Fixture',
          url: 'https://fixture.test/list.m3u',
        ),
      );
      final queryService = InMemoryCatalogQueryService(
        playlistId,
        fixtureCatalog,
      );
      final catalogView = CatalogViewState();
      final navigation = NavigationController();
      final preferences = AppPreferencesController(
        settingsRepository: settings,
      );
      final playlists = PlaylistsController(
        catalogRepository: const FixtureCatalogRepository(),
        catalogQueryService: queryService,
        settingsRepository: settings,
        catalogView: catalogView,
        navigationController: navigation,
        preferencesController: preferences,
      );
      final app = AppController(
        catalogView: catalogView,
        navigationController: navigation,
      );
      addTearDown(navigation.dispose);
      addTearDown(catalogView.dispose);
      addTearDown(playlists.dispose);
      addTearDown(preferences.dispose);

      await preferences.initialize();
      final loaded = await playlists.loadPlaylist(
        playlistId,
        intent: PlaylistLoadIntent.setup,
      );

      expect(loaded, isTrue);
      expect(playlists.activePlaylistId, playlistId);
      expect(app.catalogItemCount, fixtureCatalog.length);
      expect(catalogView.homeLive, hasLength(3));
      expect(settings.appSettings['active_playlist_id'], playlistId);
    },
  );

  test('inactive refresh preserves the active catalog and route', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.playlists.selectPlaylist('first');
    fixture.navigation.resetToHomeAndPush(const SearchRoute());
    final route = fixture.navigation.currentRoute;
    final firstItem = fixture.view.homeLive.first;

    expect(await fixture.playlists.refreshPlaylist('second'), isTrue);

    expect(fixture.playlists.activePlaylistId, 'first');
    expect(fixture.view.homeLive.first, same(firstItem));
    expect(fixture.navigation.currentRoute, same(route));
    expect(fixture.repository.calls.last, (
      'second',
      CatalogLoadPolicy.networkOnly,
    ));
    expect(fixture.playlists.refreshingPlaylistId, isNull);
  });

  test(
    'concurrent refresh is rejected and progress clears on completion',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.preferences.setVerboseRefreshInfo(true);
      fixture.repository.gate = Completer<void>();
      fixture.repository.started = Completer<void>();
      final refreshing = fixture.playlists.refreshPlaylist('first');
      await fixture.repository.started!.future;

      expect(fixture.playlists.importProgress, isNotNull);
      expect(await fixture.playlists.refreshPlaylist('second'), isFalse);
      expect(fixture.repository.calls, hasLength(1));
      fixture.repository.gate!.complete();
      expect(await refreshing, isTrue);
      expect(fixture.playlists.importProgress, isNull);
      expect(fixture.playlists.refreshingPlaylistId, isNull);
    },
  );

  test(
    'deleting the active playlist activates the next using cache-first',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.playlists.selectPlaylist('first');

      expect(await fixture.playlists.deletePlaylist('first'), isTrue);
      expect(fixture.playlists.activePlaylistId, 'second');
      expect(fixture.settings.appSettings['active_playlist_id'], 'second');
      expect(fixture.repository.calls.last, (
        'second',
        CatalogLoadPolicy.cacheFirst,
      ));
      expect(fixture.playlists.playlists.single.playlistId, 'second');

      await fixture.playlists.deletePlaylist('second');
      expect(fixture.playlists.activePlaylistId, isNull);
      expect(fixture.playlists.playlistUrl, isNull);
      expect(fixture.settings.appSettings['active_playlist_id'], '');
      expect(fixture.view.hasContent, isFalse);
      expect(fixture.navigation.currentRoute, isA<HomeRoute>());
    },
  );

  test(
    'active refresh updates the catalog without replacing its route',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.playlists.selectPlaylist('first');
      fixture.navigation.resetToHomeAndPush(const SeriesRoute());
      final route = fixture.navigation.currentRoute;

      expect(await fixture.playlists.refreshPlaylist('first'), isTrue);
      expect(fixture.navigation.currentRoute, same(route));
      expect(fixture.repository.calls.last, (
        'first',
        CatalogLoadPolicy.networkOnly,
      ));
      expect(fixture.playlists.playlistStatus, LoadStatus.ready);
    },
  );

  test(
    'failed refresh keeps the last good catalog and reports a safe issue',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.playlists.selectPlaylist('first');
      final firstItem = fixture.view.homeLive.first;
      fixture.repository.failure = const FormatException('Invalid playlist');

      expect(await fixture.playlists.refreshPlaylist('first'), isFalse);
      expect(fixture.view.homeLive.first, same(firstItem));
      expect(
        fixture.playlists.activeIssue?.kind,
        AppIssueKind.playlistFormatInvalid,
      );
      expect(fixture.playlists.playlistStatus, LoadStatus.error);
      expect(fixture.playlists.refreshingPlaylistId, isNull);
    },
  );
}

class _Fixture {
  _Fixture(
    this.settings,
    this.repository,
    this.view,
    this.navigation,
    this.preferences,
    this.playlists,
  );

  final InMemorySettingsRepository settings;
  final _RecordingRepository repository;
  final CatalogViewState view;
  final NavigationController navigation;
  final AppPreferencesController preferences;
  final PlaylistsController playlists;

  static Future<_Fixture> create() async {
    final settings = InMemorySettingsRepository();
    for (final id in ['first', 'second']) {
      await settings.upsertPlaylist(
        PlaylistSourceConfig.url(
          playlistId: id,
          name: id,
          url: 'https://fixture.test/$id.m3u',
        ),
      );
    }
    final repository = _RecordingRepository();
    final view = CatalogViewState();
    final navigation = NavigationController();
    final preferences = AppPreferencesController(settingsRepository: settings);
    final playlists = PlaylistsController(
      catalogRepository: repository,
      catalogQueryService: InMemoryCatalogQueryService('first', fixtureCatalog),
      settingsRepository: settings,
      catalogView: view,
      navigationController: navigation,
      preferencesController: preferences,
    );
    return _Fixture(
      settings,
      repository,
      view,
      navigation,
      preferences,
      playlists,
    );
  }

  void dispose() {
    playlists.dispose();
    preferences.dispose();
    view.dispose();
    navigation.dispose();
  }
}

class _RecordingRepository implements CatalogRepository {
  final List<(String?, CatalogLoadPolicy)> calls = [];
  Completer<void>? gate;
  Completer<void>? started;
  Object? failure;

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) async {
    calls.add((playlistId, policy));
    onProgress?.call(
      CatalogImportProgress(
        phase: CatalogImportPhase.downloading,
        startedAt: DateTime.now(),
        current: 1,
        total: 2,
      ),
    );
    started?.complete();
    if (gate != null) await gate!.future;
    if (failure != null) throw failure!;
    return CatalogLoadResult(
      playlistId: playlistId,
      itemCount: fixtureCatalog.length,
    );
  }
}
