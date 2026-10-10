import 'dart:async';

import '../services/catalog/catalog_maintenance.dart';
import 'app_preferences_controller.dart';
import 'playlists_controller.dart';

class AppStartup {
  AppStartup({
    required Future<void> Function() storageInitializer,
    required CatalogMaintenance catalogMaintenance,
    required AppPreferencesController preferencesController,
    required PlaylistsController playlistsController,
  }) : _storageInitializer = storageInitializer,
       _catalogMaintenance = catalogMaintenance,
       _preferencesController = preferencesController,
       _playlistsController = playlistsController;

  final Future<void> Function() _storageInitializer;
  final CatalogMaintenance _catalogMaintenance;
  final AppPreferencesController _preferencesController;
  final PlaylistsController _playlistsController;

  Future<void> initialize() async {
    await _storageInitializer();
    await _catalogMaintenance.recoverAbandonedImports();
    unawaited(_catalogMaintenance.resumeSearchIndexing());
    await _preferencesController.initialize();
    await _playlistsController.initialize();
  }
}
