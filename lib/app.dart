import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_dependencies.dart';
import 'platform/app_environment.dart';
import 'screens/catalog_screen.dart';
import 'screens/details_screen.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_controller.dart';
import 'widgets/app_scope.dart';

class IptvApp extends StatefulWidget {
  const IptvApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  State<IptvApp> createState() => _IptvAppState();
}

class _IptvAppState extends State<IptvApp> {
  AppController get controller => widget.dependencies.controller;

  @override
  void initState() {
    super.initState();
    unawaited(widget.dependencies.initialize());
    if (widget.dependencies.autoRunPlaybackSpike) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.openPlaybackSpike();
      });
    }
  }

  @override
  void dispose() {
    unawaited(widget.dependencies.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xff071412),
      ),
      home: AppEnvironment(
        capabilities: widget.dependencies.capabilities,
        child: AppScope(controller: controller, child: const AppShell()),
      ),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Shortcuts(
      shortcuts: {
        SingleActivator(LogicalKeyboardKey.escape): _BackIntent(),
        SingleActivator(LogicalKeyboardKey.goBack): _BackIntent(),
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
            canPop: controller.screen == AppScreen.home,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) controller.goBack();
            },
            child: switch (controller.screen) {
              AppScreen.home => const HomeScreen(),
              AppScreen.liveCatalog => const CatalogScreen(),
              AppScreen.movieCatalog => const CatalogScreen(),
              AppScreen.seriesCatalog => const CatalogScreen(),
              AppScreen.seasonCatalog => const CatalogScreen(),
              AppScreen.episodeCatalog => const CatalogScreen(),
              AppScreen.details => const DetailsScreen(),
              AppScreen.player => const PlayerScreen(),
              AppScreen.search => const SearchScreen(),
              AppScreen.settings => const SettingsScreen(),
            },
          ),
        ),
      ),
    );
  }
}

class _BackIntent extends Intent {
  const _BackIntent();
}
