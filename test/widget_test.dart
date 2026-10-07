import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app.dart';
import 'package:iptv_flutter/app/app_dependencies.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/screens/catalog_screen.dart';
import 'package:iptv_flutter/screens/search_screen.dart';
import 'package:iptv_flutter/services/catalog/catalog_import_worker.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/errors/app_issue.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/player_controller.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';
import 'package:iptv_flutter/ui/theme/app_tokens.dart';
import 'package:iptv_flutter/widgets/app_scope.dart';

typedef _TestControllers = ({
  AppController app,
  PlayerController player,
  PlaylistsController playlists,
  AppPreferencesController preferences,
});

_TestControllers _createTestControllers({
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

void _disposeTestControllers(_TestControllers controllers) {
  controllers.player.dispose();
  controllers.playlists.dispose();
  controllers.preferences.dispose();
  controllers.app.catalogView.dispose();
  controllers.app.navigationController.dispose();
}

void main() {
  Future<(_TestControllers, String)> pumpLoadedApp(WidgetTester tester) async {
    final settings = _TestSettingsRepository();
    final playlist = await settings.upsertPlaylist(
      const PlaylistSourceConfig.url(
        name: 'Fixture',
        url: 'https://fixture.test/playlist.m3u',
      ),
    );
    final controllers = _createTestControllers(
      catalogRepository: const FixtureCatalogRepository(),
      catalogQueryService: InMemoryCatalogQueryService(
        playlist.playlistId,
        fixtureCatalog,
      ),
      settingsRepository: settings,
      playbackAdapter: FakePlaybackAdapter(
        transitionDelay: const Duration(milliseconds: 1),
      ),
    );
    addTearDown(() => _disposeTestControllers(controllers));

    await tester.pumpWidget(
      IptvApp(
        dependencies: AppDependencies.forTesting(
          appController: controllers.app,
          playerController: controllers.player,
          playlistsController: controllers.playlists,
          preferencesController: controllers.preferences,
        ),
      ),
    );
    await controllers.playlists.loadPlaylist(
      playlist.playlistId,
      intent: PlaylistLoadIntent.setup,
    );
    await tester.pumpAndSettle();
    return (controllers, playlist.playlistId);
  }

  for (final input in PrimaryInput.values) {
    testWidgets(
      'app theme uses injected $input density independently of width',
      (tester) async {
        tester.view.physicalSize = input == PrimaryInput.touch
            ? const Size(390, 844)
            : const Size(1440, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controllers = _createTestControllers(
          catalogRepository: const FixtureCatalogRepository(),
          settingsRepository: _TestSettingsRepository(),
          playbackAdapter: FakePlaybackAdapter(),
        );
        addTearDown(() => _disposeTestControllers(controllers));
        await tester.pumpWidget(
          IptvApp(
            dependencies: AppDependencies.forTesting(
              appController: controllers.app,
              playerController: controllers.player,
              playlistsController: controllers.playlists,
              preferencesController: controllers.preferences,
              capabilities: PlatformCapabilities(
                primaryInput: input,
                hasHardwareBack: true,
                supportsHover: input == PrimaryInput.pointer,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(find.byType(AppShell)));
        expect(
          theme.textTheme.bodyMedium?.fontSize,
          input == PrimaryInput.remote ? 18 : 16,
        );
        expect(theme.scaffoldBackgroundColor, AppTokens.background);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'app theme follows focus highlight mode without changing routes',
    (tester) async {
      final (controllers, _) = await pumpLoadedApp(tester);
      final manager = FocusManager.instance;
      final previousStrategy = manager.highlightStrategy;
      addTearDown(() => manager.highlightStrategy = previousStrategy);
      controllers.app.openMovies();
      await tester.pumpAndSettle();
      final route = controllers.app.navigationController.currentRoute;

      manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      await tester.pumpAndSettle();
      var theme = Theme.of(tester.element(find.byType(AppShell)));
      expect(
        theme.textButtonTheme.style?.side?.resolve({WidgetState.focused}),
        const BorderSide(color: Colors.white, width: 3),
      );

      manager.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      await tester.pumpAndSettle();
      theme = Theme.of(tester.element(find.byType(AppShell)));
      expect(
        theme.textButtonTheme.style?.side?.resolve({WidgetState.focused}),
        isNull,
      );
      expect(controllers.app.navigationController.currentRoute, same(route));
      expect(theme.textTheme.bodyMedium?.fontSize, 16);
      expect(tester.takeException(), isNull);
    },
  );

  test('worker timeout is not reported as a playlist parse error', () async {
    final settings = _TestSettingsRepository();
    final playlist = await settings.upsertPlaylist(
      const PlaylistSourceConfig.url(
        name: 'Slow provider',
        url: 'https://provider.test/playlist.m3u',
      ),
    );
    final controllers = _createTestControllers(
      catalogRepository: _FailingCatalogRepository(
        const CatalogImportWorkerException(
          errorType: 'TimeoutException',
          message: 'Request timed out',
          workerStackTrace: '',
        ),
      ),
      settingsRepository: settings,
      playbackAdapter: FakePlaybackAdapter(),
    );
    addTearDown(() => _disposeTestControllers(controllers));

    expect(
      await controllers.playlists.loadPlaylist(
        playlist.playlistId,
        intent: PlaylistLoadIntent.setup,
      ),
      isFalse,
    );
    expect(controllers.playlists.activeIssue?.kind, AppIssueKind.timeout);
    expect(controllers.playlists.errorMessage, isNot(contains('parsed')));
  });

  testWidgets('home rows render preview pages from the query service', (
    tester,
  ) async {
    final (controllers, _) = await pumpLoadedApp(tester);

    expect(controllers.app.catalogItemCount, 5);
    expect(controllers.app.catalogView.homeLive, hasLength(3));
    expect(controllers.app.catalogView.homeMovies, hasLength(2));
    expect(find.text('News 24'), findsOneWidget);
    expect(find.text('Northbound'), findsOneWidget);
  });

  testWidgets(
    'playlist notifications do not rebuild unrelated scope consumers',
    (tester) async {
      final controllers = _createTestControllers(
        catalogRepository: const FixtureCatalogRepository(),
        settingsRepository: _TestSettingsRepository(),
        playbackAdapter: FakePlaybackAdapter(),
      );
      addTearDown(() => _disposeTestControllers(controllers));
      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            appController: controllers.app,
            playerController: controllers.player,
            playlistsController: controllers.playlists,
            preferencesController: controllers.preferences,
            navigationController: controllers.app.navigationController,
            child: Builder(
              builder: (context) {
                AppScope.appControllerOf(context);
                builds++;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      final initialBuilds = builds;
      await controllers.playlists.savePlaylistUrl(
        name: 'Fixture',
        url: 'https://fixture.test/list.m3u',
      );
      await tester.pump();
      expect(builds, initialBuilds);
    },
  );

  testWidgets('Home reacts to independent preference updates', (tester) async {
    final (controllers, _) = await pumpLoadedApp(tester);
    expect(find.text('News 24'), findsOneWidget);
    await controllers.preferences.setShowHomeLiveTv(false);
    await tester.pumpAndSettle();
    expect(find.text('News 24'), findsNothing);
    expect(find.text('Northbound'), findsOneWidget);
  });

  testWidgets('See all opens a paged grid backed by a catalog query', (
    tester,
  ) async {
    final (controllers, _) = await pumpLoadedApp(tester);

    await tester.tap(find.widgetWithText(TextButton, 'See all').first);
    await tester.pumpAndSettle();

    expect(
      controllers.app.navigationController.currentRoute,
      isA<CatalogRoute>(),
    );
    expect(controllers.app.catalogView.items.items, hasLength(3));
    expect(controllers.app.catalogView.items.hasMore, isFalse);
    expect(find.text('News 24'), findsOneWidget);
    expect(find.text('World Sports'), findsOneWidget);
    expect(find.text('Northbound'), findsNothing);
  });

  testWidgets('system Back returns from catalog without exiting the app', (
    tester,
  ) async {
    final (controllers, _) = await pumpLoadedApp(tester);
    var appDisposed = false;
    addTearDown(() => appDisposed = true);

    controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    expect(
      controllers.app.navigationController.currentRoute,
      isA<CatalogRoute>(),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(controllers.app.navigationController.currentRoute, isA<HomeRoute>());
    expect(find.byType(IptvApp), findsOneWidget);
    expect(appDisposed, isFalse);
  });

  testWidgets('Escape returns from catalog to Home', (tester) async {
    final (controllers, _) = await pumpLoadedApp(tester);
    controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    expect(
      controllers.app.navigationController.currentRoute,
      isA<CatalogRoute>(),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(controllers.app.navigationController.currentRoute, isA<HomeRoute>());
    expect(find.byType(IptvApp), findsOneWidget);
  });

  testWidgets('selecting a grid tile loads the full item for details', (
    tester,
  ) async {
    final (controllers, _) = await pumpLoadedApp(tester);

    await tester.tap(find.widgetWithText(TextButton, 'See all').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('News 24'));
    await tester.pumpAndSettle();

    final route = controllers.app.navigationController.currentRoute;
    expect(route, isA<DetailsRoute>());
    expect((route as DetailsRoute).item.id, 'news-24');
    expect((route).item.streamUrl, 'https://example.invalid/live/news-24.m3u8');
    expect(
      find.text('https://example.invalid/live/news-24.m3u8'),
      findsNothing,
    );
  });

  testWidgets('catalog scroll position is preserved after Details Back', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(600, 500);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const playlistId = 'scroll-playlist';
    final items = List.generate(
      40,
      (index) => ContentItem(
        id: 'channel-$index',
        title: 'Channel $index',
        type: ContentType.live,
        streamUrl: 'https://example.invalid/channel-$index.m3u8',
        group: 'News',
        sourceIndex: index,
      ),
    );
    final service = InMemoryCatalogQueryService(playlistId, items);
    final controllers = _createTestControllers(
      catalogRepository: const FixtureCatalogRepository(),
      catalogQueryService: service,
      settingsRepository: _TestSettingsRepository(),
      playbackAdapter: FakePlaybackAdapter(),
    );
    addTearDown(() => _disposeTestControllers(controllers));
    await controllers.app.catalogView.bind(
      service: service,
      playlistId: playlistId,
    );
    await controllers.app.catalogView.showItems(CatalogItemKind.live);
    controllers.app.navigationController.resetTo(
      const CatalogRoute(CatalogItemKind.live),
    );

    await tester.pumpWidget(
      IptvApp(
        dependencies: AppDependencies.forTesting(
          appController: controllers.app,
          playerController: controllers.player,
          playlistsController: controllers.playlists,
          preferencesController: controllers.preferences,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final grid = find.byType(GridView).first;
    await tester.drag(grid, const Offset(0, -500));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: grid,
      matching: find.byType(Scrollable),
    );
    final scrollOffset = tester
        .state<ScrollableState>(scrollable.first)
        .position
        .pixels;
    expect(scrollOffset, greaterThan(0));

    controllers.app.openDetails(items.first);
    await tester.pumpAndSettle();
    controllers.app.goBack();
    await tester.pumpAndSettle();

    expect(
      tester.state<ScrollableState>(scrollable.first).position.pixels,
      closeTo(scrollOffset, 0.1),
    );
  });

  testWidgets('leaving the player stops playback', (tester) async {
    final (controllers, _) = await pumpLoadedApp(tester);
    controllers.app.openDetails(fixtureCatalog.first);
    final openingPlayer = controllers.player.openPlayer(fixtureCatalog.first);
    await tester.pump(const Duration(milliseconds: 1));
    await openingPlayer;
    expect(
      controllers.player.playbackAdapter.state.status,
      PlaybackStatus.playing,
    );
    expect(find.text(fixtureCatalog.first.streamUrl), findsNothing);

    controllers.app.goBack();
    await tester.pumpAndSettle();

    expect(
      controllers.app.navigationController.currentRoute,
      isA<DetailsRoute>(),
    );
    expect(
      controllers.player.playbackAdapter.state.status,
      PlaybackStatus.stopped,
    );
  });

  testWidgets('search filters results and opens the selected item', (
    tester,
  ) async {
    const playlistId = 'search-playlist';
    final service = InMemoryCatalogQueryService(playlistId, fixtureCatalog);
    final controllers = _createTestControllers(
      catalogRepository: const FixtureCatalogRepository(),
      catalogQueryService: service,
      settingsRepository: _TestSettingsRepository(),
      playbackAdapter: FakePlaybackAdapter(),
    );
    addTearDown(() => _disposeTestControllers(controllers));
    controllers.app.navigationController.resetTo(const SearchRoute());
    await controllers.app.catalogView.bind(
      service: service,
      playlistId: playlistId,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          appController: controllers.app,
          playerController: controllers.player,
          playlistsController: controllers.playlists,
          preferencesController: controllers.preferences,
          navigationController: controllers.app.navigationController,
          child: const SearchScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'News');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text('News 24'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Movies'));
    await tester.pumpAndSettle();
    expect(find.text('No matching titles.'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Live'));
    await tester.pumpAndSettle();
    expect(find.text('News 24'), findsOneWidget);
    await tester.tap(find.text('News 24'));
    await tester.pumpAndSettle();
    final route = controllers.app.navigationController.currentRoute;
    expect(route, isA<DetailsRoute>());
    expect((route as DetailsRoute).item.id, 'news-24');
  });

  testWidgets(
    'wide group sidebar filters with pointer and keyboard and hides when narrow',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = _TestSettingsRepository();
      final service = InMemoryCatalogQueryService(
        'desktop-playlist',
        fixtureCatalog,
      );
      final controllers = _createTestControllers(
        catalogRepository: const FixtureCatalogRepository(),
        catalogQueryService: service,
        settingsRepository: settings,
        playbackAdapter: FakePlaybackAdapter(),
      );
      addTearDown(() => _disposeTestControllers(controllers));
      controllers.app.navigationController.resetTo(
        const CatalogRoute(CatalogItemKind.live),
      );
      await controllers.app.catalogView.bind(
        service: service,
        playlistId: 'desktop-playlist',
      );
      await controllers.app.catalogView.showItems(CatalogItemKind.live);

      await tester.pumpWidget(
        MaterialApp(
          home: AppScope(
            appController: controllers.app,
            playerController: controllers.player,
            playlistsController: controllers.playlists,
            preferencesController: controllers.preferences,
            navigationController: controllers.app.navigationController,
            child: const CatalogScreen(
              route: CatalogRoute(CatalogItemKind.live),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GROUPS'), findsOneWidget);
      expect(find.text('All groups'), findsOneWidget);
      expect(controllers.app.catalogView.selectedGroupId, isNull);
      expect(controllers.app.catalogView.items.total, 3);

      await tester.tap(find.widgetWithText(ListTile, 'Sports'));
      await tester.pumpAndSettle();
      expect(controllers.app.catalogView.selectedGroupId, isNotNull);
      expect(controllers.app.catalogView.items.total, 1);
      expect(
        controllers.app.catalogView.items.items.single.title,
        'World Sports',
      );

      await tester.tap(find.widgetWithText(ListTile, 'All groups'));
      await tester.pumpAndSettle();
      expect(controllers.app.catalogView.selectedGroupId, isNull);
      expect(controllers.app.catalogView.items.total, 3);

      var sportsFocused = false;
      for (var attempt = 0; attempt < 30 && !sportsFocused; attempt++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final tile = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<ListTile>();
        sportsFocused =
            tile?.title is Text && (tile!.title! as Text).data == 'Sports';
      }
      expect(sportsFocused, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      final previousTile = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ListTile>();
      expect((previousTile?.title as Text?)?.data, 'News');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      final selectedTile = FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<ListTile>();
      expect((selectedTile?.title as Text?)?.data, 'Sports');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(controllers.app.catalogView.items.total, 1);
      expect(
        controllers.app.catalogView.items.items.single.title,
        'World Sports',
      );

      tester.view.physicalSize = const Size(1000, 900);
      await tester.pumpAndSettle();
      expect(find.text('GROUPS'), findsNothing);
      expect(find.text('All groups'), findsNothing);
      expect(find.text('World Sports'), findsOneWidget);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(find.text('GROUPS'), findsOneWidget);
      expect(controllers.app.catalogView.items.total, 1);
    },
  );
}

class _FailingCatalogRepository implements CatalogRepository {
  const _FailingCatalogRepository(this.error);

  final Object error;

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) async {
    throw error;
  }
}

class _TestSettingsRepository implements SettingsRepository {
  final Map<String, String> _appSettings = {};
  final Map<String, ManagedPlaylist> _playlists = {};
  final Map<String, String> _urls = {};

  @override
  Future<String?> getAppSetting(String key) async => _appSettings[key];

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
  Future<bool> isGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    String? profileId,
  }) async => false;

  @override
  Future<void> setGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    required bool hidden,
    String? profileId,
  }) async {}

  @override
  Future<void> upsertPlaylistRefreshSettings(
    PlaylistRefreshSettings settings,
  ) async {}
}
