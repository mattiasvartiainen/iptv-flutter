import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/features/catalog/widgets/catalog_focus_context.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';

import '../../support/app_harness.dart';
import '../../support/catalog_fixtures.dart';

const _series = [
  ContentItem(
    id: 's1',
    title: 'Harbour Show S01E01',
    type: ContentType.vod,
    streamUrl: 'https://example.invalid/series/1',
    group: 'Shows',
  ),
  ContentItem(
    id: 's2',
    title: 'Harbour Show S02E01',
    type: ContentType.vod,
    streamUrl: 'https://example.invalid/series/2',
    group: 'Shows',
  ),
];

const _remote = PlatformCapabilities(
  primaryInput: PrimaryInput.remote,
  hasHardwareBack: true,
  supportsHover: false,
);

void main() {
  testWidgets('context clears when focused item is removed', (tester) async {
    final queries = _CountingQueries([...fixtureCatalog, ..._series]);
    final harness = await pumpIptvApp(
      tester,
      size: const Size(1440, 900),
      capabilities: _remote,
      catalogQueryService: queries,
    );
    harness.controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CatalogContextPanel>(find.byType(CatalogContextPanel))
          .summary
          ?.title,
      'News 24',
    );
    await harness.controllers.app.catalogView.items.load(
      (offset, limit) async => const CatalogPage<CatalogItemSummary>.empty(),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CatalogContextPanel>(find.byType(CatalogContextPanel))
          .summary,
      isNull,
    );
    expect(queries.lookups, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pointer hover does not activate and touch still opens movie details',
    (tester) async {
      final queries = _CountingQueries([...fixtureCatalog, ..._series]);
      final harness = await pumpIptvApp(
        tester,
        size: const Size(1440, 900),
        catalogQueryService: queries,
      );
      final app = harness.controllers.app;
      app.openMovies();
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey<String>('northbound'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(tile));
      await tester.pumpAndSettle();
      expect(queries.lookups, 0);
      expect(app.navigationController.currentRoute, isA<CatalogRoute>());
      await mouse.removePointer();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(queries.lookups, 1);
      expect(app.navigationController.currentRoute, isA<DetailsRoute>());
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<CatalogRoute>());
    },
  );

  testWidgets('focus updates live context without playback or item lookup', (
    tester,
  ) async {
    final queries = _CountingQueries([...fixtureCatalog, ..._series]);
    final harness = await pumpIptvApp(
      tester,
      size: const Size(1440, 900),
      capabilities: _remote,
      catalogQueryService: queries,
    );
    final app = harness.controllers.app;
    app.openLiveTv();
    await tester.pumpAndSettle();
    var panel = tester.widget<CatalogContextPanel>(
      find.byType(CatalogContextPanel),
    );
    expect(panel.summary?.title, 'News 24');
    expect(panel.summary?.group, 'News');
    final grid = tester.widget<GridView>(find.byType(GridView));
    final offset = grid.controller!.offset;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    panel = tester.widget<CatalogContextPanel>(
      find.byType(CatalogContextPanel),
    );
    expect(panel.summary?.title, 'City Radio');
    expect(grid.controller!.offset, offset);
    expect(queries.lookups, 0);
    expect(app.navigationController.currentRoute, isA<CatalogRoute>());
    final sports = app.catalogView.browseGroups.singleWhere(
      (group) => group.title == 'Sports',
    );
    await app.catalogView.selectBrowseGroup(sports.id);
    await tester.pumpAndSettle();
    panel = tester.widget<CatalogContextPanel>(
      find.byType(CatalogContextPanel),
    );
    expect(panel.summary?.title, isNot('City Radio'));
    expect(queries.lookups, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('movie and series context reflects summary without lookup', (
    tester,
  ) async {
    final queries = _CountingQueries([...fixtureCatalog, ..._series]);
    final harness = await pumpIptvApp(
      tester,
      size: const Size(1440, 900),
      capabilities: _remote,
      catalogQueryService: queries,
    );
    final app = harness.controllers.app;
    app.openMovies();
    await tester.pumpAndSettle();
    var panel = tester.widget<CatalogContextPanel>(
      find.byType(CatalogContextPanel),
    );
    expect(panel.summary?.group, 'Movies');
    expect(panel.summary?.title, isNotEmpty);
    app.openSeries();
    await tester.pumpAndSettle();
    panel = tester.widget<CatalogContextPanel>(
      find.byType(CatalogContextPanel),
    );
    expect(panel.summary?.title, 'Harbour Show');
    expect(panel.summary?.group, 'Shows');
    expect(panel.summary?.counts, '2 seasons · 2 episodes');
    final tile = tester.widget<MediaTile>(find.byType(MediaTile).first);
    expect(tile.subtitle, contains('Shows'));
    expect(queries.lookups, 0);
    expect(tester.takeException(), isNull);
  });

  for (final isMovie in [false, true]) {
    testWidgets(
      'deep ${isMovie ? 'movie' : 'live'} focus survives context panel resize',
      (tester) async {
        final items = List.generate(
          600,
          (index) => ContentItem(
            id: 'entry-$index',
            title: 'Entry ${index.toString().padLeft(3, '0')}',
            type: isMovie ? ContentType.vod : ContentType.live,
            streamUrl:
                'https://example.invalid/${isMovie ? 'movie' : 'live'}/$index',
            group: 'Fixture',
            sourceIndex: index,
          ),
        );
        final queries = _CountingQueries(items);
        final harness = await pumpIptvApp(
          tester,
          size: const Size(1440, 900),
          capabilities: _remote,
          catalogQueryService: queries,
        );
        if (isMovie) {
          harness.controllers.app.openMovies();
        } else {
          harness.controllers.app.openLiveTv();
        }
        await tester.pumpAndSettle();
        final tile = find.byKey(const ValueKey<String>('entry-40'));
        await tester.scrollUntilVisible(
          tile,
          450,
          scrollable: find
              .descendant(
                of: find.byType(GridView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        final detector = tester.widget<FocusableActionDetector>(
          find
              .descendant(
                of: tile,
                matching: find.byType(FocusableActionDetector),
              )
              .first,
        );
        detector.focusNode!.requestFocus();
        await tester.pumpAndSettle();
        final controller = tester
            .widget<GridView>(find.byType(GridView))
            .controller;
        final loaded = harness.controllers.app.catalogView.items.items.length;
        tester.view.physicalSize = const Size(390, 844);
        await tester.pumpAndSettle();
        expect(find.byType(CatalogContextPanel), findsNothing);
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<MediaTile>()
              ?.title,
          'Entry 040',
        );
        expect(tester.getRect(tile).top, greaterThanOrEqualTo(0));
        expect(tester.getRect(tile).bottom, lessThanOrEqualTo(844));
        expect(
          tester.widget<GridView>(find.byType(GridView)).controller,
          same(controller),
        );
        expect(
          harness.controllers.app.catalogView.items.items.length,
          greaterThanOrEqualTo(loaded),
        );
        expect(
          harness.controllers.app.catalogView.items.items.length,
          lessThan(600),
        );
        tester.view.physicalSize = const Size(1440, 900);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CatalogContextPanel>(find.byType(CatalogContextPanel))
              .summary
              ?.title,
          'Entry 040',
        );
        expect(
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<MediaTile>()
              ?.title,
          'Entry 040',
        );
        expect(tester.getRect(tile).bottom, lessThanOrEqualTo(900));
        expect(queries.lookups, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _CountingQueries extends InMemoryCatalogQueryService {
  _CountingQueries(List<ContentItem> items)
    : super('test-fixture-playlist', items);
  int lookups = 0;
  @override
  Future<ContentItem?> itemById(String itemId) {
    lookups++;
    return super.itemById(itemId);
  }
}
