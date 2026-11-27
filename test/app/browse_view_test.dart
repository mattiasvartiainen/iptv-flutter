import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/ui/theme/app_tokens.dart';
import 'package:iptv_flutter/ui/widgets/media_artwork.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';
import 'package:iptv_flutter/ui/widgets/paged_grid_view.dart';

import '../support/app_harness.dart';
import '../support/catalog_fixtures.dart';

void main() {
  for (final isSeries in [false, true]) {
    testWidgets('${isSeries ? 'Series' : 'Movie'} poster grid remains paged', (
      tester,
    ) async {
      final items = List.generate(
        1000,
        (index) => ContentItem(
          id: 'item-$index',
          title: isSeries ? 'Show $index S01E01' : 'Film $index',
          type: ContentType.vod,
          streamUrl: isSeries
              ? 'https://example.invalid/series/$index.mkv'
              : 'https://example.invalid/movie/$index.mp4',
          group: isSeries ? 'Series' : 'Movies',
          sourceIndex: index,
        ),
      );
      final harness = await pumpIptvApp(
        tester,
        size: const Size(1440, 900),
        catalogQueryService: InMemoryCatalogQueryService(
          'test-fixture-playlist',
          items,
        ),
      );
      final app = harness.controllers.app;
      if (isSeries) {
        app.openSeries();
      } else {
        app.openMovies();
      }
      await tester.pumpAndSettle();
      final before = isSeries
          ? app.catalogView.series.items.length
          : app.catalogView.items.items.length;
      expect(before, kCatalogPageSize);
      final grid = tester.widget<GridView>(find.byType(GridView));
      grid.controller!.jumpTo(grid.controller!.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final after = isSeries
          ? app.catalogView.series.items.length
          : app.catalogView.items.items.length;
      expect(after, greaterThan(before));
      expect(after, lessThan(items.length));
      expect(tester.takeException(), isNull);
    });
  }

  for (final size in [
    const Size(390, 844),
    const Size(800, 600),
    const Size(1440, 900),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('movie and series poster grids fit $size at $textScale', (
        tester,
      ) async {
        final harness = await pumpIptvApp(
          tester,
          size: size,
          textScale: textScale,
          catalogQueryService: InMemoryCatalogQueryService(
            'test-fixture-playlist',
            [
              ...fixtureCatalog,
              const ContentItem(
                id: 'long-movie',
                title: 'An exceptionally long movie title that spans two lines',
                type: ContentType.vod,
                streamUrl: 'https://example.invalid/movie/long.mp4',
                group: 'Movies',
              ),
              const ContentItem(
                id: 'episode',
                title: 'Fixture Series S01E01',
                type: ContentType.vod,
                streamUrl: 'https://example.invalid/series/episode.m3u8',
                group: 'Series',
              ),
            ],
          ),
        );
        final app = harness.controllers.app;
        expect(
          tester.widget<MediaTile>(find.byType(MediaTile).first).presentation,
          MediaTilePresentation.standard,
        );
        app.openMovies();
        await tester.pumpAndSettle();
        final movies = find.byType(MediaTile);
        expect(
          tester.widget<MediaTile>(movies.first).presentation,
          MediaTilePresentation.poster,
        );
        expect(
          tester.getRect(movies.at(1)).top,
          tester.getRect(movies.first).top,
        );
        final firstArtwork = find.descendant(
          of: movies.first,
          matching: find.byType(MediaArtwork),
        );
        final secondArtwork = find.descendant(
          of: movies.at(1),
          matching: find.byType(MediaArtwork),
        );
        expect(
          tester.getRect(firstArtwork).bottom,
          tester.getRect(secondArtwork).bottom,
        );
        expect(
          tester.getSize(movies.first).width,
          lessThanOrEqualTo(AppTokens.posterTileWidth + AppTokens.gridGap),
        );
        expect(tester.takeException(), isNull);
        app.openSeries();
        await tester.pumpAndSettle();
        expect(
          tester.widget<MediaTile>(find.byType(MediaTile).first).presentation,
          MediaTilePresentation.poster,
        );
        expect(tester.takeException(), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          app.navigationController.currentRoute,
          isA<SeriesDetailsRoute>(),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(app.navigationController.currentRoute, isA<SeriesRoute>());
      });
    }
  }

  for (final (label, size, activation) in [
    ('compact', const Size(390, 844), LogicalKeyboardKey.enter),
    ('wide', const Size(1440, 900), LogicalKeyboardKey.select),
  ]) {
    testWidgets('Live rows navigate and play directly on $label', (
      tester,
    ) async {
      final harness = await pumpIptvApp(
        tester,
        size: size,
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.remote,
          hasHardwareBack: true,
          supportsHover: false,
        ),
      );
      final app = harness.controllers.app;
      app.openLiveTv();
      await tester.pumpAndSettle();
      MediaTile? focusedTile() => FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<MediaTile>();
      expect(focusedTile()?.title, 'News 24');
      expect(app.navigationController.currentRoute, isA<CatalogRoute>());
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedTile()?.title, 'City Radio');
      expect(app.navigationController.currentRoute, isA<CatalogRoute>());
      await tester.sendKeyEvent(activation);
      await tester.pumpAndSettle();
      final route = app.navigationController.currentRoute;
      expect(route, isA<PlayerRoute>());
      expect((route as PlayerRoute).item.id, 'city-radio');
      expect(
        app.navigationController.stack.whereType<PlayerRoute>(),
        hasLength(1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<PlayerRoute>());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<CatalogRoute>());
      expect(focusedTile()?.title, 'City Radio');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('resizing Live browsing preserves group and focused channel', (
    tester,
  ) async {
    final harness = await pumpIptvApp(
      tester,
      size: const Size(390, 844),
      capabilities: const PlatformCapabilities(
        primaryInput: PrimaryInput.remote,
        hasHardwareBack: true,
        supportsHover: false,
      ),
    );
    final app = harness.controllers.app;
    app.openLiveTv();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final group = app.catalogView.selectedGroupId;
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(app.catalogView.selectedGroupId, group);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<MediaTile>()
          ?.title,
      'City Radio',
    );
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(app.catalogView.selectedGroupId, group);
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<MediaTile>()
          ?.title,
      'City Radio',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('resizing a scrolled Live list retains its page and position', (
    tester,
  ) async {
    final items = List.generate(
      200,
      (index) => ContentItem(
        id: 'channel-$index',
        title: 'Channel $index',
        type: ContentType.live,
        streamUrl: 'https://example.invalid/live/channel-$index',
        group: 'News',
        sourceIndex: index,
      ),
    );
    final harness = await pumpIptvApp(
      tester,
      size: const Size(390, 844),
      catalogQueryService: InMemoryCatalogQueryService(
        'test-fixture-playlist',
        items,
      ),
    );
    final app = harness.controllers.app;
    app.openLiveTv();
    await tester.pumpAndSettle();
    final grid = find.byType(GridView);
    final controller = tester.widget<GridView>(grid).controller!;
    controller.jumpTo(1200);
    await tester.pumpAndSettle();
    final offset = controller.offset;
    final loaded = app.catalogView.items.items.length;
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(tester.widget<GridView>(grid).controller, same(controller));
    expect(controller.offset, offset);
    expect(app.catalogView.items.items.length, greaterThanOrEqualTo(loaded));
    expect(app.catalogView.items.items.length, lessThan(items.length));
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.widget<GridView>(grid).controller, same(controller));
    expect(controller.offset, offset);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Live defaults to rows and its toggle is independent', (
    tester,
  ) async {
    final harness = await pumpIptvApp(
      tester,
      size: const Size(1440, 900),
      catalogQueryService: InMemoryCatalogQueryService(
        'test-fixture-playlist',
        fixtureCatalog,
      ),
    );
    final app = harness.controllers.app;
    app.openLiveTv();
    await tester.pumpAndSettle();
    var tile = tester.widget<MediaTile>(find.byType(MediaTile).first);
    expect(tile.listView, isTrue);
    expect(tile.showListArtwork, isTrue);
    expect(find.byTooltip('Show card view'), findsOneWidget);
    await tester.tap(find.byTooltip('Show card view'));
    await tester.pumpAndSettle();
    tile = tester.widget<MediaTile>(find.byType(MediaTile).first);
    expect(tile.listView, isFalse);
    expect(harness.controllers.preferences.useListView, isFalse);
    app.openMovies();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show list view'), findsOneWidget);
    await tester.tap(find.byTooltip('Show list view'));
    await tester.pumpAndSettle();
    expect(harness.controllers.preferences.useListView, isTrue);
    app.openLiveTv();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Show list view'), findsOneWidget);
    expect(
      tester.widget<MediaTile>(find.byType(MediaTile).first).listView,
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  test('Home widths fit two compact cards and use smaller landscape cards', () {
    for (final width in [288.0, 328.0, 358.0, 752.0]) {
      final cardWidth = AppTokens.homeTileWidthFor(width);
      expect(cardWidth * 2 + AppTokens.homeStripGap, lessThanOrEqualTo(width));
      expect(cardWidth, lessThan(300));
    }
  });

  for (final size in [
    const Size(360, 800),
    const Size(800, 360),
    const Size(1440, 900),
  ]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'browse view toggles across screens at $size scale $textScale',
        (tester) async {
          final harness = await pumpIptvApp(
            tester,
            size: size,
            textScale: textScale,
            catalogQueryService:
                InMemoryCatalogQueryService('test-fixture-playlist', [
                  ...fixtureCatalog,
                  const ContentItem(
                    id: 'episode',
                    title: 'Fixture Series S01E01',
                    type: ContentType.vod,
                    streamUrl: 'https://example.invalid/series/episode.m3u8',
                    group: 'Series',
                  ),
                ]),
          );
          final app = harness.controllers.app;
          final firstTile = tester.widget<MediaTile>(
            find.byType(MediaTile).first,
          );
          expect(firstTile.listView, isFalse);
          expect(
            tester.getSize(find.byType(MediaTile).first).width,
            lessThan(300),
          );
          final firstCard = tester.getRect(find.byType(MediaTile).at(0));
          final secondCard = tester.getRect(find.byType(MediaTile).at(1));
          expect(secondCard.top, firstCard.top);
          expect(secondCard.right, lessThanOrEqualTo(size.width));
          final toggle = find.byTooltip('Show list view');
          expect(toggle, findsOneWidget);
          if (size.height < 520 || size.width < 600) {
            expect(
              tester.getTopLeft(toggle).dx,
              lessThan(tester.getTopLeft(find.byTooltip('Search')).dx),
            );
          }
          Focus.of(
            tester.element(find.byIcon(Icons.view_list_outlined).first),
          ).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(harness.controllers.preferences.useListView, isTrue);
          expect(
            tester.widget<MediaTile>(find.byType(MediaTile).first).listView,
            isTrue,
          );

          app.openMovies();
          await tester.pumpAndSettle();
          final items = app.catalogView.items.items.toList();
          final grid = tester.widget<GridView>(find.byType(GridView).first);
          expect(
            (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
                .crossAxisCount,
            1,
          );
          final tile = find.byType(MediaTile).first;
          expect(
            tester.takeException(),
            isNull,
            reason: 'Home and movie list layouts',
          );
          if (textScale == 1) {
            await tester.tap(tile);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: 'Existing Details screen',
            );
            expect(app.navigationController.currentRoute, isA<DetailsRoute>());
            expect(find.byTooltip('Show card view'), findsNothing);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(app.navigationController.currentRoute, isA<CatalogRoute>());
            expect(app.catalogView.items.items, items);
          }
          await tester.tap(find.byTooltip('Show card view'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<MediaTile>(find.byType(MediaTile).first).listView,
            isFalse,
          );
          expect(
            find.byType(PagedGridView<CatalogItemSummary>),
            findsOneWidget,
          );

          await harness.controllers.preferences.setUseListView(true);
          app.openLiveTv();
          await tester.pumpAndSettle();
          expect(
            tester.widget<MediaTile>(find.byType(MediaTile).first).listView,
            isTrue,
          );
          app.openSeries();
          await tester.pumpAndSettle();
          expect(
            tester.widget<MediaTile>(find.byType(MediaTile).first).listView,
            isTrue,
          );
          await tester.tap(find.byType(MediaTile).first);
          await tester.pumpAndSettle();
          expect(
            app.navigationController.currentRoute,
            isA<SeriesDetailsRoute>(),
          );
          await tester.ensureVisible(find.text('Season 1'));
          await tester.pumpAndSettle();
          expect(find.text('Select a season to see episodes.'), findsOneWidget);
          await tester.ensureVisible(find.text('Season 1'));
          await tester.tap(find.text('Season 1'));
          await tester.pumpAndSettle();
          expect(
            app.navigationController.currentRoute,
            isA<SeriesDetailsRoute>(),
          );
          expect(
            tester.widget<MediaTile>(find.byType(MediaTile).first).listView,
            isTrue,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
