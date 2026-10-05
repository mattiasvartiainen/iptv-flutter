import 'dart:async';

import '../platform/platform_capabilities.dart';
import '../platform/platform_profile.dart';
import '../services/catalog/sqlite_catalog_repository.dart';
import '../services/logging/app_logger.dart';
import '../services/settings/settings_repository.dart';
import '../services/storage/database_adapter.dart';
import '../state/app_controller.dart';
import '../state/app_preferences_controller.dart';
import '../state/app_startup.dart';
import '../state/catalog_view_state.dart';
import '../state/player_controller.dart';
import '../state/playlists_controller.dart';
import 'navigation/navigation_controller.dart';

class AppDependencies {
  AppDependencies._({
    required this.appController,
    required this.playerController,
    required this.playlistsController,
    required this.preferencesController,
    required AppStartup? startup,
    required this.capabilities,
    required this.autoRunPlaybackSpike,
    required SqfliteDatabaseAdapter? databaseAdapter,
    required bool ownsResources,
    required bool initializeOnStart,
  }) : _startup = startup,
       _databaseAdapter = databaseAdapter,
       _ownsResources = ownsResources,
       _initializeOnStart = initializeOnStart;

  factory AppDependencies.create({
    required PlatformProfile profile,
    AppLogger logger = const DebugAppLogger(),
  }) {
    final databaseFactory = profile.createDatabaseFactory();
    final databaseAdapter = SqfliteDatabaseAdapter(
      databaseFactory: databaseFactory,
      databaseDirectoryProvider: () =>
          profile.getDatabaseDirectory(databaseFactory),
    );
    final secretStore = profile.createSecretStore();
    final catalogRepository = SqliteCatalogRepository(
      databaseAdapter: databaseAdapter,
      secretStore: secretStore,
      useCatalogImporterV9: true,
    );
    final settingsRepository = SqliteSettingsRepository(
      databaseAdapter: databaseAdapter,
      secretStore: secretStore,
    );
    final playbackAdapter = profile.createPlaybackAdapter();
    final catalogView = CatalogViewState();
    final navigationController = NavigationController();
    final preferencesController = AppPreferencesController(
      settingsRepository: settingsRepository,
    );
    final playlistsController = PlaylistsController(
      catalogRepository: catalogRepository,
      settingsRepository: settingsRepository,
      catalogView: catalogView,
      navigationController: navigationController,
      preferencesController: preferencesController,
      logger: logger,
    );
    final appController = AppController(
      catalogView: catalogView,
      navigationController: navigationController,
    );
    final playerController = PlayerController(
      playbackAdapter: playbackAdapter,
      navigationController: navigationController,
      logger: logger,
    );
    final startup = AppStartup(
      storageInitializer: () async {
        await databaseAdapter.initialize();
        await catalogRepository.recoverAbandonedImports();
        unawaited(catalogRepository.resumeSearchIndexing());
      },
      preferencesController: preferencesController,
      playlistsController: playlistsController,
    );

    return AppDependencies._(
      appController: appController,
      playerController: playerController,
      playlistsController: playlistsController,
      preferencesController: preferencesController,
      startup: startup,
      capabilities: profile.capabilities,
      autoRunPlaybackSpike: profile.autoRunPlaybackSpike,
      databaseAdapter: databaseAdapter,
      ownsResources: true,
      initializeOnStart: true,
    );
  }

  factory AppDependencies.forTesting({
    required AppController appController,
    required PlayerController playerController,
    required PlaylistsController playlistsController,
    required AppPreferencesController preferencesController,
    PlatformCapabilities capabilities = const PlatformCapabilities(
      primaryInput: PrimaryInput.touch,
      hasHardwareBack: true,
      supportsHover: false,
    ),
  }) => AppDependencies._(
    appController: appController,
    playerController: playerController,
    playlistsController: playlistsController,
    preferencesController: preferencesController,
    startup: null,
    capabilities: capabilities,
    autoRunPlaybackSpike: false,
    databaseAdapter: null,
    ownsResources: false,
    initializeOnStart: false,
  );

  final AppController appController;
  final PlayerController playerController;
  final PlaylistsController playlistsController;
  final AppPreferencesController preferencesController;
  final AppStartup? _startup;
  final PlatformCapabilities capabilities;
  final bool autoRunPlaybackSpike;
  final SqfliteDatabaseAdapter? _databaseAdapter;
  final bool _ownsResources;
  final bool _initializeOnStart;
  Future<void>? _disposeFuture;

  Future<void> initialize() async {
    if (_initializeOnStart) await _startup!.initialize();
  }

  Future<void> dispose() {
    if (!_ownsResources) return Future<void>.value();
    return _disposeFuture ??= _disposeOwnedResources();
  }

  Future<void> _disposeOwnedResources() async {
    playerController.dispose();
    playlistsController.dispose();
    preferencesController.dispose();
    appController.catalogView.dispose();
    appController.navigationController.dispose();
    await _databaseAdapter!.close();
  }
}
