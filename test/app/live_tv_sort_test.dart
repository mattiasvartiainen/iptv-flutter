import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';
import 'package:iptv_flutter/ui/widgets/paged_grid_view.dart';

import '../support/app_harness.dart';
import '../support/catalog_fixtures.dart';
import '../support/in_memory_settings_repository.dart';

void main() {
  testWidgets('default Live rows load large groups in bounded pages', (
    tester,
  ) async {
    final names = List.generate(1000, (index) => 'Channel $index');
    final harness = await pumpIptvApp(
      tester,
      size: const Size(1440, 900),
      catalogQueryService: InMemoryCatalogQueryService(
        'test-fixture-playlist',
        const M3uParser().parse(swedishPlaylistText(names)),
      ),
    );
    harness.controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    final collection = harness.controllers.app.catalogView.items;
    expect(collection.items.length, kCatalogPageSize);
    final grid = find.descendant(
      of: find.byType(PagedGridView<CatalogItemSummary>),
      matching: find.byType(GridView),
    );
    final scroll = tester.widget<GridView>(grid).controller!;
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(collection.items.length, greaterThan(kCatalogPageSize));
    expect(collection.items.length, lessThan(names.length));
    expect(collection.items.first.title, names.first);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets(
        'Live TV sort toggles with keyboard at $size scale $textScale',
        (tester) async {
          final harness = await pumpIptvApp(
            tester,
            size: size,
            textScale: textScale,
            capabilities: const PlatformCapabilities(
              primaryInput: PrimaryInput.remote,
              hasHardwareBack: true,
              supportsHover: false,
            ),
            catalogQueryService: InMemoryCatalogQueryService(
              'test-fixture-playlist',
              const M3uParser().parse(swedishPlaylistText(swedishChannelNames)),
            ),
          );
          final app = harness.controllers.app;
          app.openLiveTv();
          await tester.pumpAndSettle();
          expect(
            app.catalogView.items.items.map((item) => item.title),
            swedishChannelNames,
          );

          final sort = find.byTooltip(
            'Playlist order: Sort alphabetically (A-Z)',
          );
          expect(sort, findsOneWidget);
          final sortFocus = tester
              .widget<IconButton>(
                find.ancestor(of: sort, matching: find.byType(IconButton)),
              )
              .focusNode!;
          sortFocus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.text('Sort channels'), findsNothing);
          expect(app.navigationController.currentRoute, isA<CatalogRoute>());
          expect(sortFocus.hasFocus, isTrue);
          expect(app.catalogView.liveTvSort, CatalogSort.title);
          final alphabetical = [...swedishChannelNames]..sort();
          expect(
            app.catalogView.items.items.map((item) => item.title),
            alphabetical,
          );
          expect(
            find.byTooltip('Alphabetical (A-Z): Use playlist order'),
            findsOneWidget,
          );
          expect(
            (harness.settings as InMemorySettingsRepository)
                .appSettings['live_tv_sort:test-fixture-playlist'],
            'title',
          );

          expect(find.byIcon(Icons.sort_by_alpha), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pumpAndSettle();
          expect(app.catalogView.liveTvSort, CatalogSort.playlistOrder);
          expect(
            app.catalogView.items.items.map((item) => item.title),
            swedishChannelNames,
          );
          expect(sortFocus.hasFocus, isTrue);
          expect(find.byIcon(Icons.format_list_numbered), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(app.navigationController.currentRoute, isA<HomeRoute>());

          app.openMovies();
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.sort_by_alpha), findsOneWidget);
          expect(find.byIcon(Icons.format_list_numbered), findsNothing);
          app.openSeries();
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.sort_by_alpha), findsOneWidget);
          expect(find.byIcon(Icons.format_list_numbered), findsNothing);
        },
      );
    }
  }

  for (final kind in [CatalogGroupKind.movie, CatalogGroupKind.series]) {
    for (final size in [const Size(390, 844), const Size(1440, 900)]) {
      testWidgets('$kind icon-only toggle works in All and groups at $size', (
        tester,
      ) async {
        final harness = await pumpIptvApp(
          tester,
          size: size,
          textScale: 2,
          capabilities: const PlatformCapabilities(
            primaryInput: PrimaryInput.remote,
            hasHardwareBack: true,
            supportsHover: false,
          ),
          catalogQueryService: InMemoryCatalogQueryService(
            'test-fixture-playlist',
            const M3uParser().parse(movieSeriesPlaylistText),
          ),
        );
        final app = harness.controllers.app;
        void open() => kind == CatalogGroupKind.series
            ? app.openSeries()
            : app.openMovies();
        Iterable<String> titles() => kind == CatalogGroupKind.series
            ? app.catalogView.series.items.map((item) => item.title)
            : app.catalogView.items.items.map((item) => item.title);
        final suffix = kind == CatalogGroupKind.series ? 'Show' : 'Movie';
        final original = ['Zebra $suffix', 'Alpha $suffix', 'Middle $suffix'];
        final alphabetical = [...original]..sort();
        open();
        await tester.pumpAndSettle();
        expect(titles(), alphabetical);
        expect(find.text('Alphabetical (A-Z)'), findsNothing);
        expect(find.text('Playlist order'), findsNothing);
        final sort = find.byTooltip('Alphabetical (A-Z): Use playlist order');
        final button = find.ancestor(
          of: sort,
          matching: find.byType(IconButton),
        );
        final focus = tester.widget<IconButton>(button).focusNode!;
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(titles(), original);
        expect(focus.hasFocus, isTrue);
        expect(find.byIcon(Icons.format_list_numbered), findsOneWidget);
        expect(find.text('Playlist order'), findsNothing);

        await app.catalogView.selectBrowseGroup(
          app.catalogView.browseGroups.single.id,
        );
        await tester.pumpAndSettle();
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        expect(titles(), alphabetical);
        expect(focus.hasFocus, isTrue);
        await tester.tap(
          find.byTooltip('Alphabetical (A-Z): Use playlist order'),
        );
        await tester.pumpAndSettle();
        expect(titles(), original);

        app.openLiveTv();
        await tester.pumpAndSettle();
        expect(app.catalogView.liveTvSort, CatalogSort.playlistOrder);
        open();
        await tester.pumpAndSettle();
        expect(titles(), original);
        if (kind == CatalogGroupKind.series) {
          app.openSeriesSeasons(app.catalogView.series.items.first);
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.sort_by_alpha), findsNothing);
          expect(find.byIcon(Icons.format_list_numbered), findsNothing);
          await tester.ensureVisible(find.text('Season 2'));
          await tester.tap(find.text('Season 2'));
          await tester.pumpAndSettle();
          expect(find.byIcon(Icons.format_list_numbered), findsNothing);
        }
        tester.view.physicalSize = const Size(1440, 900);
        await tester.pumpAndSettle();
        app.openSearch();
        await tester.pumpAndSettle();
        expect(find.byIcon(Icons.sort_by_alpha), findsNothing);
        expect(find.byIcon(Icons.format_list_numbered), findsNothing);
      });
    }
  }

  for (final kind in [CatalogGroupKind.movie, CatalogGroupKind.series]) {
    testWidgets('$kind resets scrolling when toggled', (tester) async {
      final text =
          '#EXTM3U\n${List.generate(220, (index) => '#EXTINF:-1 group-title="${kind == CatalogGroupKind.series ? 'Series' : 'Movies'}",'
              'Title ${220 - index}${kind == CatalogGroupKind.series ? ' S01 E01' : ''}\n'
              'https://example.invalid/${kind.name}/$index.${kind == CatalogGroupKind.series ? 'mkv' : 'mp4'}\n').join()}';
      final harness = await pumpIptvApp(
        tester,
        size: const Size(1440, 900),
        catalogQueryService: InMemoryCatalogQueryService(
          'test-fixture-playlist',
          const M3uParser().parse(text),
        ),
      );
      await harness.controllers.preferences.setUseListView(true);
      final app = harness.controllers.app;
      if (kind == CatalogGroupKind.series) {
        app.openSeries();
      } else {
        app.openMovies();
      }
      await tester.pumpAndSettle();
      final grid = find.byType(GridView);
      tester.widget<GridView>(grid).controller!.jumpTo(1000);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byTooltip('Alphabetical (A-Z): Use playlist order'),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<GridView>(grid).controller!.offset, 0);
      expect(
        kind == CatalogGroupKind.series
            ? app.catalogView.series.items.first.title
            : app.catalogView.items.items.first.title,
        'Title 220',
      );
    });
  }

  for (final kind in CatalogGroupKind.values) {
    testWidgets(
      '$kind failed writes show an inline error only in the owning section',
      (tester) async {
        final settings = _FailSortSettings();
        final harness = await pumpIptvApp(tester, settingsRepository: settings);
        final app = harness.controllers.app;
        void open() {
          switch (kind) {
            case CatalogGroupKind.live:
              app.openLiveTv();
            case CatalogGroupKind.movie:
              app.openMovies();
            case CatalogGroupKind.series:
              app.openSeries();
          }
        }

        final originalSort = kind == CatalogGroupKind.live
            ? CatalogSort.playlistOrder
            : CatalogSort.title;
        final nextSort = originalSort == CatalogSort.title
            ? CatalogSort.playlistOrder
            : CatalogSort.title;
        open();
        await tester.pumpAndSettle();
        Future<void> toggle() async {
          await tester.tap(
            find.byTooltip(
              kind == CatalogGroupKind.live
                  ? 'Playlist order: Sort alphabetically (A-Z)'
                  : 'Alphabetical (A-Z): Use playlist order',
            ),
          );
          await tester.pumpAndSettle();
        }

        await toggle();
        expect(find.textContaining('Could not save sorting.'), findsOneWidget);
        expect(app.catalogView.sortFor(kind), originalSort);
        if (kind == CatalogGroupKind.live) {
          app.openMovies();
        } else {
          app.openLiveTv();
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not save sorting.'), findsNothing);
        open();
        await tester.pumpAndSettle();
        expect(find.textContaining('Could not save sorting.'), findsOneWidget);
        settings.fail = false;
        await toggle();
        expect(find.textContaining('Could not save sorting.'), findsNothing);
        expect(app.catalogView.sortFor(kind), nextSort);
      },
    );
  }

  testWidgets('changing Live TV sorting resets a scrolled list to page one', (
    tester,
  ) async {
    final names = List.generate(220, (index) => 'Channel ${220 - index}');
    final harness = await pumpIptvApp(
      tester,
      size: const Size(1440, 900),
      catalogQueryService: InMemoryCatalogQueryService(
        'test-fixture-playlist',
        const M3uParser().parse(swedishPlaylistText(names)),
      ),
    );
    await harness.controllers.preferences.setUseListView(true);
    harness.controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    final grid = find.descendant(
      of: find.byType(PagedGridView<CatalogItemSummary>),
      matching: find.byType(GridView),
    );
    tester.widget<GridView>(grid).controller!.jumpTo(1000);
    await tester.pumpAndSettle();
    expect(tester.widget<GridView>(grid).controller!.offset, 1000);
    await tester.tap(
      find.byTooltip('Playlist order: Sort alphabetically (A-Z)'),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<GridView>(grid).controller!.offset, 0);
    expect(
      harness.controllers.app.catalogView.items.items.first.title,
      'Channel 1',
    );
  });
}

class _FailSortSettings extends InMemorySettingsRepository {
  bool fail = true;

  @override
  Future<void> setAppSetting(String key, String value) async {
    if (fail && key.contains('_sort:')) {
      throw StateError('Storage unavailable');
    }
    await super.setAppSetting(key, value);
  }
}
