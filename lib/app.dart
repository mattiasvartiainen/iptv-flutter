import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_dependencies.dart';
import 'app/app_shortcuts.dart';
import 'app/navigation/app_route.dart';
import 'app/navigation/navigation_controller.dart';
import 'features/catalog/catalog_screen.dart';
import 'features/details/details_screen.dart';
import 'features/home/home_screen.dart';
import 'features/player/player_controller.dart';
import 'features/player/player_screen.dart';
import 'features/search/search_screen.dart';
import 'features/settings/settings_screen.dart';
import 'platform/app_environment.dart';
import 'services/playback/playback_adapter.dart';
import 'state/app_controller.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/app_scope.dart';

class IptvApp extends StatefulWidget {
  const IptvApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<IptvApp> createState() => _IptvAppState();
}

class _IptvAppState extends State<IptvApp> {
  final GlobalKey<NavigatorState> _rootNavigatorKey =
      GlobalKey<NavigatorState>();
  AppController get controller => widget.dependencies.appController;
  bool _keyLoggerRegistered = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
    widget.dependencies.preferencesController.addListener(_syncDebugKeyLogger);
    _syncDebugKeyLogger();
    unawaited(widget.dependencies.initialize());
    if (widget.dependencies.autoRunPlaybackSpike) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.dependencies.playerController.openPlaybackSpike();
      });
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    widget.dependencies.preferencesController.removeListener(
      _syncDebugKeyLogger,
    );
    if (_keyLoggerRegistered) {
      HardwareKeyboard.instance.removeHandler(_logHardwareKey);
    }
    unawaited(widget.dependencies.dispose());
    super.dispose();
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    if (mounted) setState(() {});
  }

  void _syncDebugKeyLogger() {
    final shouldRegister =
        kDebugMode &&
        widget.dependencies.preferencesController.verboseRefreshInfo;
    if (shouldRegister == _keyLoggerRegistered) return;
    _keyLoggerRegistered = shouldRegister;
    if (shouldRegister) {
      HardwareKeyboard.instance.addHandler(_logHardwareKey);
    } else {
      HardwareKeyboard.instance.removeHandler(_logHardwareKey);
    }
  }

  bool _logHardwareKey(KeyEvent event) {
    debugPrint(
      'Hardware key ${event.runtimeType}: '
      'logical=0x${event.logicalKey.keyId.toRadixString(16)} '
      'physical=0x${event.physicalKey.usbHidUsage.toRadixString(16)}',
    );
    return false;
  }

  Future<void> _handleBack(AppController appController) async {
    final rootNavigator = _rootNavigatorKey.currentState;
    if (rootNavigator?.canPop() ?? false) {
      await rootNavigator!.maybePop();
      return;
    }
    if (appController.navigationController.currentRoute is PlayerRoute &&
        widget.dependencies.playerController.handleBackRequest()) {
      return;
    }
    appController.goBack();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV',
      navigatorKey: _rootNavigatorKey,
      shortcuts: buildAppShortcuts(
        extraShortcuts: widget.dependencies.extraShortcuts,
      ),
      theme: AppTheme.dark(
        remoteFirst: widget.dependencies.capabilities.isRemoteFirst,
      ),
      builder: (context, child) => Actions(
        actions: {
          BackIntent: CallbackAction<BackIntent>(
            onInvoke: (_) {
              unawaited(_handleBack(controller));
              return null;
            },
          ),
        },
        child: Theme(
          data: AppTheme.dark(
            remoteFirst: widget.dependencies.capabilities.isRemoteFirst,
            traditionalFocus:
                FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional,
            disableAnimations: MediaQuery.disableAnimationsOf(context),
          ),
          child: child!,
        ),
      ),
      home: AppEnvironment(
        capabilities: widget.dependencies.capabilities,
        child: AppScope(
          appController: controller,
          playerController: widget.dependencies.playerController,
          playlistsController: widget.dependencies.playlistsController,
          preferencesController: widget.dependencies.preferencesController,
          navigationController: controller.navigationController,
          child: const AppShell(),
        ),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.appControllerOf(context);
    final navigation = AppScope.navigationControllerOf(context);
    return ListenableBuilder(
      listenable: navigation,
      builder: (context, _) {
        final routes = navigation.stack;
        final playerController = AppScope.playerControllerOf(context);
        return Actions(
          actions: _playerActions(navigation, playerController),
          child: Focus(
            autofocus: true,
            child: PopScope(
              canPop: routes.length == 1,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop) {
                  final player = AppScope.playerControllerOf(context);
                  final handled =
                      navigation.currentRoute is PlayerRoute &&
                      player.handleBackRequest();
                  if (!handled) controller.goBack();
                }
              },
              child: Navigator(
                pages: [
                  for (final route in routes)
                    MaterialPage<void>(
                      key: ValueKey<AppRoute>(route),
                      arguments: route,
                      child: _screenForRoute(route),
                    ),
                ],
                onDidRemovePage: (page) {
                  final route = page.arguments;
                  if (route is AppRoute) navigation.popIfCurrent(route);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Map<Type, Action<Intent>> _playerActions(
    NavigationController navigation,
    PlayerController player,
  ) {
    final capabilities = player.capabilities;
    bool isPlayerActive() => navigation.currentRoute is PlayerRoute;

    return {
      PlayPauseIntent: CallbackAction<PlayPauseIntent>(
        onInvoke: (_) {
          if (!isPlayerActive() || !capabilities.supportsPause) return null;
          unawaited(player.togglePlayPause());
          return null;
        },
      ),
      PlayIntent: CallbackAction<PlayIntent>(
        onInvoke: (_) {
          if (isPlayerActive() &&
              capabilities.supportsPause &&
              player.playbackState.value.status != PlaybackStatus.playing) {
            unawaited(player.play());
          }
          return null;
        },
      ),
      PauseIntent: CallbackAction<PauseIntent>(
        onInvoke: (_) {
          if (isPlayerActive() &&
              capabilities.supportsPause &&
              player.playbackState.value.status == PlaybackStatus.playing) {
            unawaited(player.pause());
          }
          return null;
        },
      ),
      SeekIntent: CallbackAction<SeekIntent>(
        onInvoke: (intent) {
          if (!isPlayerActive() || !capabilities.supportsSeek) return null;
          unawaited(player.seekBy(intent.offset));
          return null;
        },
      ),
      ChannelStepIntent: CallbackAction<ChannelStepIntent>(
        onInvoke: (_) => null,
      ),
    };
  }

  Widget _screenForRoute(AppRoute route) => switch (route) {
    HomeRoute() => const HomeScreen(),
    CatalogRoute() ||
    SeriesRoute() ||
    SeasonsRoute() ||
    EpisodesRoute() => CatalogScreen(route: route),
    DetailsRoute(:final item) => DetailsScreen(item: item),
    PlayerRoute(:final item) => PlayerScreen(item: item),
    SearchRoute() => const SearchScreen(),
    SettingsRoute() => const SettingsScreen(),
  };
}
