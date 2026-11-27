import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';

import '../support/app_harness.dart';
import '../support/controlled_playback.dart';

const _playlist = 'test-fixture-playlist';
const _selected = ContentItem(
  id: 'new-row',
  title: 'Movie',
  type: ContentType.vod,
  streamUrl: 'https://fixture.invalid/movie',
  group: 'Movies',
  catalogPlaylistId: _playlist,
  catalogItemKey: 42,
);
const _stale = CatalogItemSummary(
  id: 'old-row',
  title: 'Movie',
  sortTitle: 'movie',
  kind: CatalogItemKind.movie,
  playlistId: _playlist,
  itemKey: 42,
);

void main() {
  test('disposal invalidates an in-flight stable lookup', () async {
    final queries = _DelayedQueries();
    final view = CatalogViewState();
    final navigation = NavigationController();
    final app = AppController(
      catalogView: view,
      navigationController: navigation,
    );
    await view.bind(service: queries, playlistId: _playlist);
    final pending = app.activateSummary(_stale, playLive: (_) async {});
    view.dispose();
    queries.result.complete(_selected);
    await pending;
    expect(navigation.currentRoute, isA<HomeRoute>());
    navigation.dispose();
  });

  testWidgets('activation resolves stable key rather than obsolete row ID', (
    tester,
  ) async {
    final playback = ControlledPlayback();
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: InMemoryCatalogQueryService(_playlist, [_selected]),
      playbackAdapter: playback,
    );
    final app = harness.controllers.app;
    await app.activateSummary(_stale, playLive: playback.load);
    final route = app.navigationController.currentRoute;
    expect(route, isA<DetailsRoute>());
    expect((route as DetailsRoute).item.id, 'new-row');
    expect(playback.calls, isEmpty);
  });

  testWidgets('late stable lookup cannot activate after playlist switch', (
    tester,
  ) async {
    final queries = _DelayedQueries();
    final harness = await pumpIptvApp(tester, catalogQueryService: queries);
    final app = harness.controllers.app;
    final pending = app.activateSummary(_stale, playLive: (_) async {});
    await harness.controllers.app.catalogView.bind(
      service: InMemoryCatalogQueryService('other', []),
      playlistId: 'other',
    );
    queries.result.complete(_selected);
    await pending;
    expect(app.navigationController.currentRoute, isA<HomeRoute>());
  });

  testWidgets('a different playlist cannot activate a matching row ID', (
    tester,
  ) async {
    final playback = ControlledPlayback();
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: InMemoryCatalogQueryService(_playlist, [_selected]),
      playbackAdapter: playback,
    );
    const other = CatalogItemSummary(
      id: 'new-row',
      title: 'Other',
      sortTitle: 'other',
      kind: CatalogItemKind.movie,
      playlistId: 'other',
      itemKey: 42,
    );
    await harness.controllers.app.activateSummary(
      other,
      playLive: playback.load,
    );
    expect(
      harness.controllers.app.navigationController.currentRoute,
      isA<HomeRoute>(),
    );
    expect(playback.calls, isEmpty);
  });

  testWidgets('removed stable item remains unavailable', (tester) async {
    final playback = ControlledPlayback();
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: InMemoryCatalogQueryService(_playlist, []),
      playbackAdapter: playback,
    );
    await harness.controllers.app.activateSummary(
      _stale,
      playLive: playback.load,
    );
    expect(
      harness.controllers.app.navigationController.currentRoute,
      isA<HomeRoute>(),
    );
    expect(playback.calls, isEmpty);
  });
}

class _DelayedQueries extends InMemoryCatalogQueryService {
  _DelayedQueries() : super(_playlist, [_selected]);
  final result = Completer<ContentItem?>();

  @override
  Future<ContentItem?> itemByKey(String playlistId, int itemKey) =>
      result.future;
}
