import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_dependencies.dart';
import 'app/navigation/app_route.dart';
import 'platform/app_environment.dart';
import 'screens/catalog_screen.dart';
import 'screens/details_screen.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_controller.dart';
import 'ui/theme/app_theme.dart';
import 'widgets/app_scope.dart';

class IptvApp extends StatefulWidget {
  const IptvApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<IptvApp> createState() => _IptvAppState();
}

class _IptvAppState extends State<IptvApp> {
  AppController get controller => widget.dependencies.appController;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
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
    unawaited(widget.dependencies.dispose());
    super.dispose();
  }

  void _highlightModeChanged(FocusHighlightMode mode) {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV',
      theme: AppTheme.dark(
        remoteFirst: widget.dependencies.capabilities.isRemoteFirst,
      ),
      builder: (context, child) => Theme(
        data: AppTheme.dark(
          remoteFirst: widget.dependencies.capabilities.isRemoteFirst,
          traditionalFocus:
              FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional,
          disableAnimations: MediaQuery.disableAnimationsOf(context),
        ),
        child: child!,
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
        return Shortcuts(
          shortcuts: {
            SingleActivator(LogicalKeyboardKey.escape): const _BackIntent(),
            SingleActivator(LogicalKeyboardKey.goBack): const _BackIntent(),
          },
          child: Actions(
            actions: {
              _BackIntent: CallbackAction<_BackIntent>(
                onInvoke: (_) {
                  controller.goBack();
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: PopScope(
                canPop: routes.length == 1,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) controller.goBack();
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
          ),
        );
      },
    );
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

class _BackIntent extends Intent {
  const _BackIntent();
}
