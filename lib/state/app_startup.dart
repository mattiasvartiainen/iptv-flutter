import 'app_preferences_controller.dart';
import 'playlists_controller.dart';

class AppStartup {
  AppStartup({
    required Future<void> Function() storageInitializer,
    required AppPreferencesController preferencesController,
    required PlaylistsController playlistsController,
  }) : _storageInitializer = storageInitializer,
       _preferencesController = preferencesController,
       _playlistsController = playlistsController;

  final Future<void> Function() _storageInitializer;
  final AppPreferencesController _preferencesController;
  final PlaylistsController _playlistsController;

  Future<void> initialize() async {
    await _storageInitializer();
    await _preferencesController.initialize();
    await _playlistsController.initialize();
  }
}
