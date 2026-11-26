import 'package:flutter/widgets.dart';

import '../../app/navigation/navigation_controller.dart';
import '../../features/player/player_controller.dart';
import '../../services/metadata/movie_metadata.dart';
import '../../services/metadata/series_metadata.dart';
import '../../state/app_controller.dart';
import '../../state/app_preferences_controller.dart';
import '../../state/playlists_controller.dart';
import '../../state/telemetry_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.appController,
    required this.playerController,
    required this.playlistsController,
    required this.preferencesController,
    required this.navigationController,
    this.telemetryController,
    this.movieMetadataRepository,
    this.seriesMetadataRepository,
    required super.child,
  });

  final AppController appController;
  final PlayerController playerController;
  final PlaylistsController playlistsController;
  final AppPreferencesController preferencesController;
  final NavigationController navigationController;
  final TelemetryController? telemetryController;
  final MovieMetadataRepository? movieMetadataRepository;
  final SeriesMetadataRepository? seriesMetadataRepository;

  static SeriesMetadataRepository? seriesMetadataRepositoryOf(
    BuildContext context,
  ) => _scopeOf(context).seriesMetadataRepository;

  static MovieMetadataRepository? movieMetadataRepositoryOf(
    BuildContext context,
  ) => _scopeOf(context).movieMetadataRepository;

  static TelemetryController? telemetryControllerOf(BuildContext context) =>
      _scopeOf(context).telemetryController;

  static AppController appControllerOf(BuildContext context) =>
      _scopeOf(context).appController;

  static PlayerController playerControllerOf(BuildContext context) =>
      _scopeOf(context).playerController;

  static Future<void> activateItemById(BuildContext context, String itemId) {
    final scope = _scopeOf(context);
    return scope.appController.activateItemById(
      itemId,
      playLive: scope.playerController.openPlayer,
    );
  }

  static PlaylistsController playlistsControllerOf(BuildContext context) =>
      _scopeOf(context).playlistsController;

  static AppPreferencesController preferencesControllerOf(
    BuildContext context,
  ) => _scopeOf(context).preferencesController;

  static NavigationController navigationControllerOf(BuildContext context) =>
      _scopeOf(context).navigationController;

  static AppScope _scopeOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    if (scope != null) return scope;
    throw FlutterError.fromParts([
      ErrorSummary('AppScope not found in the widget tree.'),
      ErrorDescription('A controller accessor was used outside AppScope.'),
    ]);
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      appController != oldWidget.appController ||
      playerController != oldWidget.playerController ||
      playlistsController != oldWidget.playlistsController ||
      preferencesController != oldWidget.preferencesController ||
      navigationController != oldWidget.navigationController ||
      movieMetadataRepository != oldWidget.movieMetadataRepository ||
      seriesMetadataRepository != oldWidget.seriesMetadataRepository ||
      telemetryController != oldWidget.telemetryController;
}
