import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';

import '../support/catalog_fixtures.dart';

void main() {
  test(
    'favourites retain sorting, refresh after changes, and remain explicit',
    () async {
      final catalog = const M3uParser().parse(adultLabelsPlaylistText);
      String id(String title) =>
          catalog.firstWhere((item) => item.title == title).id;
      final favorites = {
        id('Ordinary film'),
        id('Marked film [xXx]'),
        id('Another film'),
      };
      final service = InMemoryCatalogQueryService(
        'p',
        catalog,
        favoriteItemIds: favorites,
      );
      final view = CatalogViewState();
      addTearDown(view.dispose);
      await view.bind(service: service, playlistId: 'p');
      await view.showItems(CatalogItemKind.movie, selectFirstGroup: true);
      expect(view.items.items.map((e) => e.title), [
        'Another film',
        'Ordinary film',
      ]);
      await view.selectFavorites();
      expect(view.items.items.map((e) => e.title), [
        'Another film',
        'Marked film [xXx]',
        'Ordinary film',
      ]);
      await view.setCatalogSort(
        CatalogGroupKind.movie,
        CatalogSort.playlistOrder,
      );
      expect(view.favoriteGroupSelected, isTrue);
      expect(view.items.items.map((e) => e.title), [
        'Ordinary film',
        'Marked film [xXx]',
        'Another film',
      ]);
      favorites.remove(id('Marked film [xXx]'));
      view.favoriteChanged('different-playlist');
      expect(view.items.total, 3);
      view.favoriteChanged('p');
      await Future<void>.delayed(Duration.zero);
      expect(view.items.total, 2);
      await view.selectBrowseGroup(null);
      expect(view.favoriteGroupSelected, isFalse);
      expect(view.items.total, 4);
      await view.showItems(CatalogItemKind.movie, selectFirstGroup: true);
      expect(view.favoriteGroupSelected, isFalse);
      expect(view.items.total, 2);
    },
  );

  test(
    'series favourites aggregate distinct shows from their episodes',
    () async {
      final catalog = const M3uParser().parse(adultLabelsPlaylistText);
      final favorites = catalog
          .where((item) => item.title.contains('Marked Show'))
          .map((item) => item.id)
          .toSet();
      final service = InMemoryCatalogQueryService(
        'p',
        catalog,
        favoriteItemIds: favorites,
      );
      final view = CatalogViewState();
      addTearDown(view.dispose);
      await view.bind(service: service, playlistId: 'p');
      await view.showSeries(selectFirstGroup: true);
      expect(view.series.items.single.title, 'Ordinary Show');
      await view.selectFavorites();
      expect(view.series.items.single.title, 'Marked Show');
      favorites.clear();
      view.favoriteChanged('p');
      await Future<void>.delayed(Duration.zero);
      expect(view.series.total, 0);
    },
  );
}
