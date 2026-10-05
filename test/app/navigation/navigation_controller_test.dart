import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';

void main() {
  test('push and pop preserve typed route parameters', () {
    final navigation = NavigationController();
    addTearDown(navigation.dispose);
    const item = ContentItem(
      id: 'news',
      title: 'News',
      type: ContentType.live,
      streamUrl: 'https://example.invalid/news.m3u8',
      group: 'News',
    );

    navigation.resetToHomeAndPush(const CatalogRoute(CatalogItemKind.live));
    navigation.push(const DetailsRoute(item));

    expect(navigation.stack, hasLength(3));
    expect((navigation.currentRoute as DetailsRoute).item.id, 'news');
    expect(navigation.activeNavItem, PrimaryNavItem.liveTv);

    navigation.pop();
    expect(navigation.currentRoute, isA<CatalogRoute>());
    navigation.pop();
    expect(navigation.currentRoute, isA<HomeRoute>());
    navigation.pop();
    expect(navigation.stack, hasLength(1));
  });

  test('nested series routes pop to their exact parent', () {
    final navigation = NavigationController();
    addTearDown(navigation.dispose);
    const series = SeriesSummary(
      id: 'series-1',
      title: 'Series',
      sortTitle: 'series',
      seasonCount: 1,
      episodeCount: 1,
    );
    const season = SeasonSummary(
      id: 'season-1',
      seriesId: 'series-1',
      seasonNumber: 1,
      episodeCount: 1,
    );

    navigation.resetToHomeAndPush(const SeriesRoute());
    navigation.push(const SeasonsRoute(series));
    navigation.push(const EpisodesRoute(series, season));

    navigation.pop();
    expect(navigation.currentRoute, isA<SeasonsRoute>());
    navigation.pop();
    expect(navigation.currentRoute, isA<SeriesRoute>());
    navigation.pop();
    expect(navigation.currentRoute, isA<HomeRoute>());
  });

  test('top navigation resets history and Settings preserves its context', () {
    final navigation = NavigationController();
    addTearDown(navigation.dispose);
    const catalog = CatalogRoute(CatalogItemKind.movie);

    navigation.resetToHomeAndPush(catalog);
    navigation.push(const SettingsRoute());
    expect(navigation.activeNavItem, PrimaryNavItem.movies);

    navigation.pop();
    expect(identical(navigation.currentRoute, catalog), isTrue);
    navigation.resetToHomeAndPush(const SearchRoute());
    expect(navigation.stack, hasLength(2));
    expect(navigation.activeNavItem, PrimaryNavItem.search);
  });
}
