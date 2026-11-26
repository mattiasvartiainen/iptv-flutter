import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/automatic_content_policy.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';

import '../support/catalog_fixtures.dart';

void main() {
  test(
    'explicit markers are case insensitive without excluding ordinary titles',
    () {
      expect(AutomaticContentPolicy.excludesGroup('Adults (VOD)'), isTrue);
      expect(AutomaticContentPolicy.excludesGroup('XXX Live'), isTrue);
      expect(AutomaticContentPolicy.excludesGroup('Sweden'), isFalse);
      expect(AutomaticContentPolicy.excludesTitle('Example [xXx]'), isTrue);
      expect(AutomaticContentPolicy.excludesTitle('Example (18+)'), isTrue);
      expect(AutomaticContentPolicy.excludesTitle('Example [Adult]'), isTrue);
      expect(
        AutomaticContentPolicy.excludesTitle('V Sport Premier League 4'),
        isFalse,
      );
    },
  );

  test(
    'automatic views omit marked content; explicit browsing and search remain available',
    () async {
      final service = InMemoryCatalogQueryService(
        'p',
        const M3uParser().parse(adultLabelsPlaylistText),
      );
      final view = CatalogViewState();
      addTearDown(view.dispose);
      await view.bind(service: service, playlistId: 'p');
      expect(view.homeLiveGroup?.title, 'Sweden');
      expect(view.homeMoviesGroup?.title, 'Family Movies');
      expect(view.homeSeriesGroup?.title, 'Family Series');
      expect(view.homeLive.map((e) => e.title), ['Ordinary channel']);
      expect(view.homeMovies.map((e) => e.title), [
        'Another film',
        'Ordinary film',
      ]);
      expect(view.homeSeries.map((e) => e.title), ['Ordinary Show']);
      await view.showItems(CatalogItemKind.movie, selectFirstGroup: true);
      expect(view.items.items.map((e) => e.title), [
        'Another film',
        'Ordinary film',
      ]);
      await view.setCatalogSort(
        CatalogGroupKind.movie,
        CatalogSort.playlistOrder,
      );
      expect(view.items.items.map((e) => e.title), [
        'Ordinary film',
        'Another film',
      ]);
      final safeGroup = view.selectedGroupId;
      await view.selectBrowseGroup(safeGroup);
      expect(view.items.items.map((e) => e.title), [
        'Ordinary film',
        'Marked film [xXx]',
        'Another film',
      ]);
      await view.selectBrowseGroup(view.browseGroups.first.id);
      expect(view.items.items.single.title, 'Restricted film [XXX]');
      await view.selectBrowseGroup(null);
      expect(view.items.total, 4);
      await view.search('Marked film');
      expect(view.searchResults.items.single.title, 'Marked film [xXx]');
      await view.showSeries(selectFirstGroup: true);
      expect(view.series.items.map((e) => e.title), ['Ordinary Show']);
      await view.selectBrowseGroup(view.selectedGroupId);
      expect(view.series.items.map((e) => e.title), [
        'Marked Show',
        'Ordinary Show',
      ]);
    },
  );

  test('all adult groups never cause automatic fallback to All', () async {
    final onlyAdult = const M3uParser()
        .parse(adultLabelsPlaylistText)
        .where(
          (item) => item.group.contains('Adults') || item.group.contains('XXX'),
        )
        .toList();
    final view = CatalogViewState();
    addTearDown(view.dispose);
    await view.bind(
      service: InMemoryCatalogQueryService('p', onlyAdult),
      playlistId: 'p',
    );
    expect(view.homeLive, isEmpty);
    expect(view.homeMovies, isEmpty);
    expect(view.homeSeries, isEmpty);
    expect(view.itemCount, 3);
    await view.showItems(CatalogItemKind.live, selectFirstGroup: true);
    expect(view.awaitingGroupSelection, isTrue);
    expect(view.items.items, isEmpty);
    await view.selectBrowseGroup(null);
    expect(view.items.total, 1);
    await view.showSeries(selectFirstGroup: true);
    expect(view.awaitingGroupSelection, isTrue);
    expect(view.series.items, isEmpty);
    await view.selectBrowseGroup(null);
    expect(view.series.total, 1);
  });
}
