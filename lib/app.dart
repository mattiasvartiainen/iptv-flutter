import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'widgets/app_scope.dart';
import 'screens/home_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/details_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'services/storage/storage_bootstrap.dart';

class IptvApp extends StatefulWidget {
  const IptvApp({super.key, this.controller});
  static const bool autoRunPlaybackSpike = bool.fromEnvironment(
    'PLAYBACK_SPIKE_AUTORUN',
    defaultValue: false,
  );
  final AppController? controller;
  @override
  State<IptvApp> createState() => _IptvAppState();
}

class _IptvAppState extends State<IptvApp> {
  late final AppController controller = widget.controller ?? AppController();

  @override
  void initState() {
    super.initState();
    controller.initialize();
    if (IptvApp.autoRunPlaybackSpike) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.openPlaybackSpike();
      });
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      controller.dispose();
      AppStorageBootstrap.instance.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IPTV',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xff071412),
      ),
      home: AppScope(controller: controller, child: const AppShell()),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return switch (controller.screen) {
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
    };
  }
}
