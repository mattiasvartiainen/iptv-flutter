import 'dart:async';

import 'package:flutter/widgets.dart';

import '../features/player/player_controller.dart';
import '../platform/platform_capabilities.dart';
import '../platform/platform_profile.dart';
import '../platform/telemetry_settings_store.dart';
import '../services/catalog/sqlite_catalog_repository.dart';
import '../services/diagnostics/startup_preflight.dart';
import '../services/logging/app_logger.dart';
import '../services/metadata/movie_metadata.dart';
import '../services/metadata/series_metadata.dart';
import '../services/metadata/sqlite_movie_metadata_repository.dart';
import '../services/metadata/sqlite_series_metadata_repository.dart';
import '../services/security/url_redaction.dart';
import '../services/settings/app_preferences.dart';
import '../services/settings/settings_repository.dart';
import '../services/storage/database_adapter.dart';
import '../services/telemetry/app_telemetry.dart';
import '../services/telemetry/otlp_app_telemetry.dart';
import '../services/xtream/stored_xtream_credentials.dart';
import '../services/xtream/xtream_api_client.dart';
import '../services/xtream/xtream_movie_metadata_provider.dart';
import '../services/xtream/xtream_source_verifier.dart';
import '../state/app_controller.dart';
import '../state/app_preferences_controller.dart';
import '../state/app_startup.dart';
import '../state/catalog_view_state.dart';
import '../state/playlists_controller.dart';
import '../state/telemetry_controller.dart';
import 'navigation/navigation_controller.dart';

class AppDependencies {
  AppDependencies._({
    required this.appController,
    required this.playerController,
    required this.playlistsController,
    required this.preferencesController,
    required this.logger,
    this.movieMetadataRepository,
    this.seriesMetadataRepository,
    this.telemetryController,
    required AppStartup? startup,
    required this.capabilities,
    required this.extraShortcuts,
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
    final localLogger = logger;
    final telemetry = OtlpAppTelemetry();
    logger = TelemetryAppLogger(localLogger, telemetry);
    final secretStore = profile.createSecretStore();
    final telemetryController = TelemetryController(
      telemetry: telemetry,
      defaults: telemetryBuildConfig(),
      store: FileTelemetrySettingsStore(
        secretStore,
        directoryProvider: profile.getTelemetrySettingsDirectory,
      ),
      localLogger: localLogger,
    );
    final databaseFactory = profile.createDatabaseFactory();
    final databaseAdapter = SqfliteDatabaseAdapter(
      databaseFactory: databaseFactory,
      telemetry: telemetry,
      databaseDirectoryProvider: () =>
          profile.getDatabaseDirectory(databaseFactory),
    );
    final catalogRepository = SqliteCatalogRepository(
      databaseAdapter: databaseAdapter,
      logger: logger,
      telemetry: telemetry,
    );
    final settingsRepository = SqliteSettingsRepository(
      databaseAdapter: databaseAdapter,
      secretStore: secretStore,
    );
    final playbackAdapter = profile.createPlaybackAdapter(logger: logger);
    final credentials = StoredXtreamCredentials(settingsRepository);
    final movieMetadata = SqliteMovieMetadataRepository(
      database: databaseAdapter,
      resolveCredentials: credentials.resolve,
      providers: [
        XtreamMovieMetadataProvider(
          XtreamApiClient(
            resolveCredentials: credentials.resolve,
            logger: logger,
          ),
        ),
      ],
      logger: logger,
    );
    final seriesMetadata = SqliteSeriesMetadataRepository(
      database: databaseAdapter,
      resolveCredentials: credentials.resolve,
      client: XtreamApiClient(
        resolveCredentials: credentials.resolve,
        logger: logger,
      ),
      logger: logger,
    );
    final catalogView = CatalogViewState(
      logger: logger,
      preferences: AppPreferences(settingsRepository: settingsRepository),
    );
    final navigationController = NavigationController();
    final preferencesController = AppPreferencesController(
      settingsRepository: settingsRepository,
    );
    final playlistsController = PlaylistsController(
      sourceVerifier: XtreamSourceVerifier(
        createClient: (resolver) =>
            XtreamApiClient(resolveCredentials: resolver, logger: logger),
      ),
      catalogRepository: catalogRepository,
      settingsRepository: settingsRepository,
      catalogView: catalogView,
      navigationController: navigationController,
      preferencesController: preferencesController,
      logger: logger,
    );
    final appController = AppController(
      logger: logger,
      catalogView: catalogView,
      navigationController: navigationController,
    );
    final userLibrary = catalogRepository.userLibrary;
    final playerController = PlayerController(
      favorites: userLibrary,
      userLibrary: userLibrary,
      onFavoriteChanged: catalogView.favoriteChanged,
      playbackAdapter: playbackAdapter,
      navigationController: navigationController,
      logger: logger,
    );
    final startup = AppStartup(
      preflight: StartupPreflight(
        checks: [SqlitePreflightCheck(databaseFactory: databaseFactory)],
        logger: logger,
        telemetry: telemetry,
      ),
      storageInitializer: databaseAdapter.initialize,
      catalogMaintenance: catalogRepository,
      preferencesController: preferencesController,
      playlistsController: playlistsController,
    );

    return AppDependencies._(
      appController: appController,
      playerController: playerController,
      playlistsController: playlistsController,
      preferencesController: preferencesController,
      logger: logger,
      telemetryController: telemetryController,
      movieMetadataRepository: movieMetadata,
      seriesMetadataRepository: seriesMetadata,
      startup: startup,
      capabilities: profile.capabilities,
      extraShortcuts: profile.extraShortcuts,
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
    AppLogger logger = const DebugAppLogger(),
    MovieMetadataRepository? movieMetadataRepository,
    SeriesMetadataRepository? seriesMetadataRepository,
    PlatformCapabilities capabilities = const PlatformCapabilities(
      primaryInput: PrimaryInput.touch,
      hasHardwareBack: true,
      supportsHover: false,
    ),
    Map<ShortcutActivator, Intent> extraShortcuts = const {},
  }) => AppDependencies._(
    appController: appController,
    playerController: playerController,
    playlistsController: playlistsController,
    preferencesController: preferencesController,
    logger: logger,
    movieMetadataRepository: movieMetadataRepository,
    seriesMetadataRepository: seriesMetadataRepository,
    startup: null,
    capabilities: capabilities,
    extraShortcuts: extraShortcuts,
    autoRunPlaybackSpike: false,
    databaseAdapter: null,
    ownsResources: false,
    initializeOnStart: false,
  );

  final AppController appController;
  final PlayerController playerController;
  final PlaylistsController playlistsController;
  final AppPreferencesController preferencesController;
  final AppLogger logger;
  final MovieMetadataRepository? movieMetadataRepository;
  final SeriesMetadataRepository? seriesMetadataRepository;
  final TelemetryController? telemetryController;
  final AppStartup? _startup;
  final PlatformCapabilities capabilities;
  final Map<ShortcutActivator, Intent> extraShortcuts;
  final bool autoRunPlaybackSpike;
  final SqfliteDatabaseAdapter? _databaseAdapter;
  final bool _ownsResources;
  final bool _initializeOnStart;
  Future<void>? _disposeFuture;

  Future<void> initialize() async {
    if (_initializeOnStart) {
      await telemetryController?.initialize();
      final telemetry =
          telemetryController?.telemetry ?? const NoopAppTelemetry();
      await telemetry.measure('app.startup', _startup!.initialize);
    }
  }

  Future<void> dispose() {
    if (!_ownsResources) return Future<void>.value();
    if (_disposeFuture != null) return _disposeFuture!;
    final disposal = _disposeFuture = _disposeOwnedResources();
    unawaited(
      disposal.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          logger.error(
            'app_dispose_failed',
            error: redactSensitiveText(error.toString()),
            stackTrace: StackTrace.fromString(
              redactSensitiveText(stack.toString()),
            ),
          );
        },
      ),
    );
    return disposal;
  }

  Future<void> _disposeOwnedResources() async {
    playerController.dispose();
    try {
      await playerController.disposalComplete;
    } finally {
      playlistsController.dispose();
      preferencesController.dispose();
      appController.catalogView.dispose();
      appController.navigationController.dispose();
      try {
        await _databaseAdapter!.close();
      } finally {
        try {
          await telemetryController?.telemetry.close();
        } finally {
          telemetryController?.dispose();
        }
      }
    }
  }
}
