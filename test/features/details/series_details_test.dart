import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/features/details/series_details_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/metadata/series_metadata.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';

import '../../support/app_harness.dart';

const entries = [
  ContentItem(id: 'episode1', title: 'Fixture Show S01E01', type: ContentType.vod,
    streamUrl: 'https://fixture.test/series/1.mkv', group: 'Series'),
  ContentItem(id: 'episode2', title: 'Fixture Show S02E01', type: ContentType.vod,
    streamUrl: 'https://fixture.test/series/2.mkv', group: 'Series'),
];

void main() {
  for (final size in [const Size(360, 800), const Size(390, 844), const Size(800, 360),
    const Size(1440, 900), const Size(1920, 1080)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('plain playlist inline overview fits $size scale $scale', (tester) async {
        final queries = InMemoryCatalogQueryService('test-fixture-playlist', entries);
        final harness = await pumpIptvApp(tester, size: size, textScale: scale, catalogQueryService: queries);
        final series = (await queries.querySeries('test-fixture-playlist', offset: 0, limit: 10)).items.single;
        harness.controllers.app.openSeriesSeasons(series);
        await tester.pumpAndSettle();
        expect(find.text('Select a season to see episodes.'), findsOneWidget);
        expect(find.byType(MediaTile), findsNothing);
        expect(Focus.of(tester.element(find.text('Season 1'))).hasFocus, isTrue);
        await tester.ensureVisible(find.text('Season 1'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(harness.controllers.app.navigationController.currentRoute, isA<SeriesDetailsRoute>());
        expect(find.text('Episodes - Season 1'), findsOneWidget);
        await tester.ensureVisible(find.text('Season 2'));
        await tester.tap(find.text('Season 2'));
        await tester.pumpAndSettle();
        expect(find.text('Episodes - Season 2'), findsOneWidget);
        expect(find.text('Fixture Show S02E01'), findsOneWidget);
        expect(find.text('Fixture Show S01E01'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('metadata arrival preserves season focus; Down/Up and Back restore inline selection', (tester) async {
    final repository = _Repository();
    addTearDown(repository.close);
    final queries = InMemoryCatalogQueryService('test-fixture-playlist', entries);
    final harness = await pumpIptvApp(tester, size: const Size(1440, 900),
      catalogQueryService: queries, seriesMetadataRepository: repository);
    harness.controllers.app.openSeries();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MediaTile).first);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final seasonFocus = Focus.of(tester.element(find.text('Season 1')));
    expect(seasonFocus.hasFocus, isTrue);
    repository.streams.single.add(SeriesMetadataResult(metadata: ContentMetadata(fields: {
      ContentMetadataField.plot: 'Enriched show synopsis.', ContentMetadataField.genres: 'Drama',
    })));
    await tester.pumpAndSettle();
    expect(find.text('Enriched show synopsis.'), findsOneWidget);
    expect(seasonFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.widget<MediaTile>(find.byType(MediaTile).first).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(seasonFocus.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(harness.controllers.app.navigationController.currentRoute, isA<DetailsRoute>());
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(harness.controllers.app.navigationController.currentRoute, isA<SeriesDetailsRoute>());
    expect(find.text('Episodes - Season 1'), findsOneWidget);
    expect(tester.widget<MediaTile>(find.byType(MediaTile).first).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(harness.controllers.app.navigationController.currentRoute, isA<SeriesRoute>());
    expect(repository.tokens.single.isCancelled, isTrue);
  });
  testWidgets('metadata errors/retry do not prevent season/episode browsing', (tester) async {
    final repository = _Repository();
    addTearDown(repository.close);
    final queries = InMemoryCatalogQueryService('test-fixture-playlist', entries);
    final harness = await pumpIptvApp(tester, catalogQueryService: queries, seriesMetadataRepository: repository);
    harness.controllers.app.openSeriesSeasons((await queries.querySeries('test-fixture-playlist', offset: 0, limit: 10)).items.single);
    await tester.pumpAndSettle();
    repository.streams.single.add(const SeriesMetadataResult(failure: MetadataFailure.network));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Retry series information'));
    await tester.tap(find.text('Retry series information'));
    await tester.pumpAndSettle();
    expect(repository.force.last, isTrue);
    await tester.ensureVisible(find.text('Season 1'));
    await tester.tap(find.text('Season 1'));
    await tester.pumpAndSettle();
    expect(find.text('Fixture Show S01E01'), findsOneWidget);
  });
  test('late season pages cannot replace the newly selected season', () async {
    final queries = _DelayedQueries();
    final controller = SeriesDetailsController(queries: queries,
      subject: const SeriesMetadataSubject(playlistId: 'p', seriesId: 's'));
    addTearDown(controller.dispose);
    await controller.loadSeasons();
    final first = controller.selectSeason(controller.seasons.first);
    final second = controller.selectSeason(controller.seasons.last);
    queries.second.complete(const CatalogPage(items: [
      CatalogItemSummary(id: '2', title: 'Second', sortTitle: 'second', kind: CatalogItemKind.episode),
    ], offset: 0, total: 1));
    await second;
    queries.first.complete(const CatalogPage(items: [
      CatalogItemSummary(id: '1', title: 'First', sortTitle: 'first', kind: CatalogItemKind.episode),
    ], offset: 0, total: 1));
    await first;
    expect(controller.selectedSeason!.id, '2');
    expect(controller.episodes.items.single.id, '2');
  });
  testWidgets('large seasons use lazy bounded paging and error/Up/retry stays remote accessible', (tester) async {
    final queries = _ManyQueries();
    final harness = await pumpIptvApp(tester, size: const Size(1440, 900), catalogQueryService: queries);
    harness.controllers.app.openSeriesSeasons((await queries.querySeries('test-fixture-playlist')).items.single);
    await tester.pumpAndSettle();
    expect(queries.calls, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Could not load episodes. Retry'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Could not load episodes. Retry'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Season 1'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    queries.fail = false;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(queries.calls.every((call) => call.$2 == 0 && call.$3 == kCatalogPageSize), isTrue);
    expect(queries.calls.map((call) => call.$1).toSet(), hasLength(1));
    expect(find.byType(MediaTile).evaluate().length, lessThan(100));
    expect(Focus.of(tester.element(find.text('Season 1'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test('season failure can retry and disposed controllers ignore completion', () async {
    final queries = _SeasonQueries();
    final controller = SeriesDetailsController(queries: queries,
      subject: const SeriesMetadataSubject(playlistId: 'p', seriesId: 's'));
    await controller.loadSeasons();
    expect(controller.seasonsFailed, isTrue);
    queries.fail = false;
    final loading = controller.loadSeasons();
    controller.dispose();
    queries.result.complete(const []);
    await loading;
    expect(controller.seasons, isEmpty);
  });
  testWidgets('long metadata keeps season focus visible and Down reaches lazy episodes', (tester) async {
    final repository = _Repository();
    addTearDown(repository.close);
    final queries = InMemoryCatalogQueryService('test-fixture-playlist', entries);
    final harness = await pumpIptvApp(tester, size: const Size(360, 800), textScale: 2,
      catalogQueryService: queries, seriesMetadataRepository: repository);
    harness.controllers.app.openSeriesSeasons((await queries.querySeries('test-fixture-playlist')).items.single);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    repository.streams.single.add(SeriesMetadataResult(metadata: ContentMetadata(fields: {
      ContentMetadataField.plot: List.filled(100, 'A long show description.').join(' '),
      ContentMetadataField.cast: List.filled(100, 'A cast member').join(', '),
    })));
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Season 1'))).hasFocus, isTrue);
    expect(tester.getRect(find.text('Season 1')).bottom, lessThan(800));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final tile = find.byType(MediaTile).first;
    expect(tester.widget<MediaTile>(tile).focusNode!.hasFocus, isTrue);
    expect(tester.getRect(tile).top, lessThan(800));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(Focus.of(tester.element(find.text('Season 1'))).hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}

class _Repository implements SeriesMetadataRepository {
  final streams = <StreamController<SeriesMetadataResult>>[];
  final tokens = <MetadataCancellation>[];
  final force = <bool>[];
  @override
  Stream<SeriesMetadataResult> resolve(SeriesMetadataSubject subject, {
    required MetadataCancellation cancellation, bool forceRefresh = false}) {
    final stream = StreamController<SeriesMetadataResult>();
    streams.add(stream); tokens.add(cancellation); force.add(forceRefresh);
    return stream.stream;
  }
  void close() { for (final stream in streams) { unawaited(stream.close()); } }
}

class _DelayedQueries extends InMemoryCatalogQueryService {
  _DelayedQueries() : super('p', entries);
  final first = Completer<CatalogPage<CatalogItemSummary>>();
  final second = Completer<CatalogPage<CatalogItemSummary>>();
  @override
  Future<List<SeasonSummary>> seasons(String seriesId) async => [
    const SeasonSummary(id: '1', seriesId: 's', seasonNumber: 1, episodeCount: 1),
    const SeasonSummary(id: '2', seriesId: 's', seasonNumber: 2, episodeCount: 1),
  ];
  @override
  Future<CatalogPage<CatalogItemSummary>> episodes(String seasonId, {int offset = 0, int limit = 100}) =>
    seasonId == '1' ? first.future : second.future;
}

class _ManyQueries extends InMemoryCatalogQueryService {
  _ManyQueries() : super('test-fixture-playlist', entries);
  bool fail = true;
  final calls = <(String, int, int)>[];
  @override
  Future<CatalogPage<CatalogItemSummary>> episodes(String seasonId, {int offset = 0, int limit = kCatalogPageSize}) async {
    calls.add((seasonId, offset, limit));
    if (fail) throw StateError('Fixture query failure');
    return CatalogPage(items: List.generate(limit, (index) => CatalogItemSummary(
      id: '$seasonId-${offset + index}', title: 'Episode ${offset + index + 1}', sortTitle: '',
      kind: CatalogItemKind.episode, episodeNumber: offset + index + 1)), offset: offset, total: 1000);
  }
}

class _SeasonQueries extends InMemoryCatalogQueryService {
  _SeasonQueries() : super('p', entries);
  bool fail = true;
  final result = Completer<List<SeasonSummary>>();
  @override
  Future<List<SeasonSummary>> seasons(String seriesId) {
    if (fail) throw StateError('Fixture season failure');
    return result.future;
  }
}
