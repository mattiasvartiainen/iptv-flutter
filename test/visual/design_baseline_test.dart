import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:path/path.dart' as p;

import '../support/app_harness.dart';
import '../support/visual_fixture_http.dart';

const _playlistId = 'test-fixture-playlist';
const _movie = ContentItem(
  id: 'movie',
  title: 'The Very Long Movie Title Across the Northern Horizon',
  type: ContentType.vod,
  streamUrl: 'https://example.invalid/movie/one',
  group: 'Movies',
  posterUrl: 'https://example.invalid/artwork.png',
  description: 'A locally supplied description for the visual baseline.',
  sourceIndex: 2,
);
const _fixtures = <ContentItem>[
  ContentItem(
    id: 'channel-one',
    title: 'A Very Long Channel Name for Remote Browsing',
    type: ContentType.live,
    streamUrl: 'https://example.invalid/live/one',
    group: 'Sweden',
    logoUrl: 'https://example.invalid/artwork.png',
  ),
  ContentItem(
    id: 'channel-two',
    title: 'Second Channel',
    type: ContentType.live,
    streamUrl: 'https://example.invalid/live/two',
    group: 'Sweden',
    logoUrl: 'https://example.invalid/missing.png',
    sourceIndex: 1,
  ),
  _movie,
  ContentItem(
    id: 'movie-two',
    title: 'Movie Without Artwork',
    type: ContentType.vod,
    streamUrl: 'https://example.invalid/movie/two',
    group: 'Movies',
    sourceIndex: 3,
  ),
  ContentItem(
    id: 'episode-one',
    title: 'Harbour Stories S01 E01',
    type: ContentType.vod,
    streamUrl: 'https://example.invalid/series/one',
    group: 'Series',
    sourceIndex: 4,
  ),
  ContentItem(
    id: 'episode-two',
    title: 'Harbour Stories S01 E02',
    type: ContentType.vod,
    streamUrl: 'https://example.invalid/series/two',
    group: 'Series',
    sourceIndex: 5,
  ),
];

Future<void> _waitForArtwork(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsWidgets);
  await tester.pumpAndSettle();
}

Finder _loadedArtwork() => find.byWidgetPredicate(
  (widget) => widget is RawImage && widget.image != null,
);

void main() {
  setUpAll(() async {
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot == null) {
      throw StateError('FLUTTER_ROOT is required to load the SDK test fonts.');
    }
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      final path = p.join(
        flutterRoot,
        'bin',
        'cache',
        'artifacts',
        'material_fonts',
        'roboto-$weight.ttf',
      );
      final bytes = await File(path).readAsBytes();
      roboto.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await roboto.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    installVisualFixtureHttp();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
  tearDown(() {
    uninstallVisualFixtureHttp();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  for (final (label, size) in [
    ('compact', const Size(390, 844)),
    ('wide', const Size(1440, 900)),
  ]) {
    testWidgets('catalog visual baseline $label', (tester) async {
      try {
        final harness = await pumpIptvApp(
          tester,
          size: size,
          capabilities: const PlatformCapabilities(
            primaryInput: PrimaryInput.remote,
            hasHardwareBack: true,
            supportsHover: false,
          ),
          catalogQueryService: InMemoryCatalogQueryService(
            _playlistId,
            _fixtures,
          ),
        );
        final app = harness.controllers.app;

        Future<void> capture(String name) async {
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/${label}_$name.png'),
          );
        }

        await _waitForArtwork(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey('channel-one')),
            matching: _loadedArtwork(),
          ),
        );
        await capture('home');
        app.openLiveTv();
        await tester.pumpAndSettle();
        final logo = find.descendant(
          of: find.byKey(const ValueKey('channel-one')),
          matching: _loadedArtwork(),
        );
        final failedLogo = find.descendant(
          of: find.byKey(const ValueKey('channel-two')),
          matching: find.byIcon(Icons.live_tv),
        );
        await _waitForArtwork(tester, logo);
        expect(logo, findsOneWidget);
        expect(failedLogo, findsOneWidget);
        await capture('live');
        app.openMovies();
        await tester.pumpAndSettle();
        await _waitForArtwork(
          tester,
          find.descendant(
            of: find.byKey(const ValueKey('movie')),
            matching: _loadedArtwork(),
          ),
        );
        await capture('movies');
        app.openDetails(_movie);
        await tester.pumpAndSettle();
        await _waitForArtwork(tester, _loadedArtwork());
        await capture('details');
        expect(app.navigationController.currentRoute, isA<DetailsRoute>());
        app.openSeries();
        await capture('series');
        expect(app.catalogView.series.items, hasLength(1));
        final series = app.catalogView.series.items.single;
        await app.catalogView.showSeasons(series);
        app.openSeriesEpisodes(series, app.catalogView.seasons.single);
        await capture('episodes');
        expect(app.navigationController.currentRoute, isA<EpisodesRoute>());
      } finally {
        uninstallVisualFixtureHttp();
      }
    });
  }

  testWidgets('compact large-text, empty and error visual states', (
    tester,
  ) async {
    try {
      final harness = await pumpIptvApp(
        tester,
        size: const Size(390, 844),
        textScale: 2,
        catalogQueryService: InMemoryCatalogQueryService(
          _playlistId,
          _fixtures,
        ),
      );
      final app = harness.controllers.app;
      app.openLiveTv();
      await tester.pumpAndSettle();
      await _waitForArtwork(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('channel-one')),
          matching: _loadedArtwork(),
        ),
      );
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/compact_live_large_text.png'),
      );
      app.catalogView.items.clear();
      await tester.pumpAndSettle();
      expect(find.text('No live channels found yet.'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/compact_live_empty.png'),
      );
      await app.catalogView.items.load((_, _) async {
        throw StateError('Synthetic catalog failure');
      });
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/compact_live_error.png'),
      );
    } finally {
      uninstallVisualFixtureHttp();
    }
  });
}
