import 'dart:async';

import '../platform/platform_capabilities.dart';
import '../platform/platform_profile.dart';
import '../services/catalog/sqlite_catalog_repository.dart';
import '../services/logging/app_logger.dart';
import '../services/settings/settings_repository.dart';
import '../services/storage/database_adapter.dart';
import '../state/app_controller.dart';

class AppDependencies {
  AppDependencies._({
    required this.controller,
    required this.capabilities,
    required this.autoRunPlaybackSpike,
    required SqfliteDatabaseAdapter? databaseAdapter,
    required bool ownsResources,
    required bool initializeOnStart,
  }) : _databaseAdapter = databaseAdapter,
       _ownsResources = ownsResources,
       _initializeOnStart = initializeOnStart;

  factory AppDependencies.create({
    required PlatformProfile profile,
    AppLogger logger = const DebugAppLogger(),
  }) {
    final databaseAdapter = SqfliteDatabaseAdapter();
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
    final controller = AppController(
      catalogRepository: catalogRepository,
      settingsRepository: settingsRepository,
      playbackAdapter: playbackAdapter,
      logger: logger,
      storageInitializer: () async {
        await databaseAdapter.initialize();
        await catalogRepository.recoverAbandonedImports();
        unawaited(catalogRepository.resumeSearchIndexing());
      },
    );

    return AppDependencies._(
      controller: controller,
      capabilities: profile.capabilities,
      autoRunPlaybackSpike: profile.autoRunPlaybackSpike,
      databaseAdapter: databaseAdapter,
      ownsResources: true,
      initializeOnStart: true,
    );
  }

  factory AppDependencies.forTesting({
    required AppController controller,
    PlatformCapabilities capabilities = const PlatformCapabilities(
      primaryInput: PrimaryInput.touch,
      hasHardwareBack: true,
      supportsHover: false,
    ),
  }) => AppDependencies._(
    controller: controller,
    capabilities: capabilities,
    autoRunPlaybackSpike: false,
    databaseAdapter: null,
    ownsResources: false,
    initializeOnStart: false,
  );

  final AppController controller;
  final PlatformCapabilities capabilities;
  final bool autoRunPlaybackSpike;
  final SqfliteDatabaseAdapter? _databaseAdapter;
  final bool _ownsResources;
  final bool _initializeOnStart;

  Future<void> initialize() async {
    if (_initializeOnStart) await controller.initialize();
  }

  Future<void> dispose() async {
    if (!_ownsResources) return;
    controller.dispose();
    await _databaseAdapter!.close();
  }
}
