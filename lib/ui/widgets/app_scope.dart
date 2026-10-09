import 'package:flutter/widgets.dart';

import '../../app/navigation/navigation_controller.dart';
import '../../features/player/player_controller.dart';
import '../../state/app_controller.dart';
import '../../state/app_preferences_controller.dart';
import '../../state/playlists_controller.dart';

class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.appController,
    required this.playerController,
    required this.playlistsController,
    required this.preferencesController,
    required this.navigationController,
    required super.child,
  });

  final AppController appController;
  final PlayerController playerController;
  final PlaylistsController playlistsController;
  final AppPreferencesController preferencesController;
  final NavigationController navigationController;

  static AppController appControllerOf(BuildContext context) =>
      _scopeOf(context).appController;

  static PlayerController playerControllerOf(BuildContext context) =>
      _scopeOf(context).playerController;

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
      navigationController != oldWidget.navigationController;
}
