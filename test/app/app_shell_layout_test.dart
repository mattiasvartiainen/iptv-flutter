import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app.dart';
import 'package:iptv_flutter/app/app_dependencies.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/catalog_repository.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';
import 'package:iptv_flutter/ui/theme/app_tokens.dart';

import '../support/in_memory_settings_repository.dart';

void main() {
  test('responsive page insets follow the approved width classes', () {
    expect(AppTokens.pageInsetFor(390), 16);
    expect(AppTokens.pageInsetFor(800), 24);
    expect(AppTokens.pageInsetFor(1440), 40);
    expect(AppTokens.searchPaddingFor(390).left, 16);
  });

  testWidgets(
    'shell adapts navigation and preserves the current route and loaded page',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = InMemorySettingsRepository();
      final catalogView = CatalogViewState();
      final navigation = NavigationController();
      final preferences = AppPreferencesController(
        settingsRepository: settings,
      );
      final playlists = PlaylistsController(
        catalogRepository: const FixtureCatalogRepository(),
        settingsRepository: settings,
        catalogView: catalogView,
        navigationController: navigation,
        preferencesController: preferences,
      );
      final app = AppController(
        catalogView: catalogView,
        navigationController: navigation,
      );
      final player = PlayerController(
        playbackAdapter: FakePlaybackAdapter(),
        navigationController: navigation,
      );
      addTearDown(() {
        player.dispose();
        playlists.dispose();
        preferences.dispose();
        catalogView.dispose();
        navigation.dispose();
      });

      const playlistId = 'adaptive-layout-playlist';
      final queryService = InMemoryCatalogQueryService(
        playlistId,
        fixtureCatalog,
      );
      await catalogView.bind(service: queryService, playlistId: playlistId);
      await catalogView.showItems(CatalogItemKind.movie);
      const movieRoute = CatalogRoute(CatalogItemKind.movie);
      navigation.resetTo(movieRoute);
      final displayedIds = catalogView.items.items
          .map((item) => item.id)
          .toList();

      await tester.pumpWidget(
        IptvApp(
          dependencies: AppDependencies.forTesting(
            appController: app,
            playerController: player,
            playlistsController: playlists,
            preferencesController: preferences,
            capabilities: const PlatformCapabilities(
              primaryInput: PrimaryInput.touch,
              hasHardwareBack: true,
              supportsHover: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byTooltip('Search'), findsOneWidget);
      expect(find.byTooltip('Settings'), findsOneWidget);

      tester.view.physicalSize = const Size(800, 1000);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        false,
      );
      expect(navigation.currentRoute, same(movieRoute));
      expect(catalogView.items.items.map((item) => item.id), displayedIds);

      tester.view.physicalSize = const Size(1440, 900);
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationRail>(find.byType(NavigationRail)).extended,
        true,
      );
      expect(navigation.currentRoute, same(movieRoute));

      tester.view.physicalSize = const Size(1440, 480);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
      expect(navigation.currentRoute, same(movieRoute));
      expect(catalogView.items.items.map((item) => item.id), displayedIds);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      expect(navigation.currentRoute, isA<SearchRoute>());
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(navigation.currentRoute, isA<SettingsRoute>());
    },
  );
}
