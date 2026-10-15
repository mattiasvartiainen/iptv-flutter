import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/ui/theme/app_tokens.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';
import 'package:iptv_flutter/ui/widgets/paged_grid_view.dart';

import '../support/app_harness.dart';
import '../support/catalog_fixtures.dart';

void main() {
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
          expect(app.navigationController.currentRoute, isA<SeasonsRoute>());
          expect(
            tester.widget<MediaTile>(find.byType(MediaTile).first).listView,
            isTrue,
          );
          await tester.tap(find.byType(MediaTile).first);
          await tester.pumpAndSettle();
          expect(app.navigationController.currentRoute, isA<EpisodesRoute>());
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
