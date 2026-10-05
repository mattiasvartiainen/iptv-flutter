import '../app/navigation/app_route.dart';
import '../app/navigation/navigation_controller.dart';
import '../models/content_item.dart';
import '../services/catalog/catalog_query.dart';
import 'catalog_view_state.dart';

class AppController {
  AppController({
    required this.catalogView,
    required this.navigationController,
  });

  final CatalogViewState catalogView;
  final NavigationController navigationController;

  int get catalogItemCount => catalogView.itemCount;
  PrimaryNavItem get activeNavItem => navigationController.activeNavItem;

  void openHome() {
    navigationController.resetTo(const HomeRoute());
  }

  void openLiveTv() {
    navigationController.resetToHomeAndPush(
      const CatalogRoute(CatalogItemKind.live),
    );
    catalogView.showItems(CatalogItemKind.live);
  }

  void openMovies() {
    navigationController.resetToHomeAndPush(
      const CatalogRoute(CatalogItemKind.movie),
    );
    catalogView.showItems(CatalogItemKind.movie);
  }

  void openSeries() {
    navigationController.resetToHomeAndPush(const SeriesRoute());
    catalogView.showSeries();
  }

  void openSearch() {
    navigationController.resetToHomeAndPush(const SearchRoute());
  }

  void openSeriesSeasons(SeriesSummary series) {
    navigationController.push(SeasonsRoute(series));
    catalogView.showSeasons(series);
  }

  void openSeriesEpisodes(SeriesSummary series, SeasonSummary season) {
    navigationController.push(EpisodesRoute(series, season));
    catalogView.showEpisodes(season);
  }

  void openDetails(ContentItem item) {
    navigationController.push(DetailsRoute(item));
  }

  Future<void> openDetailsById(String itemId) async {
    final item = await catalogView.itemById(itemId);
    if (item != null) openDetails(item);
  }

  void openSettings() {
    if (navigationController.currentRoute is! SettingsRoute) {
      navigationController.push(const SettingsRoute());
    }
  }

  void goBack() => navigationController.pop();
}
