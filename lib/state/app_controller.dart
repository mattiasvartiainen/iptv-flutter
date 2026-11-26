import '../app/navigation/app_route.dart';
import '../app/navigation/navigation_controller.dart';
import '../models/content_item.dart';
import '../services/catalog/catalog_query.dart';
import '../services/logging/app_logger.dart';
import 'catalog_view_state.dart';

class AppController {
  AppController({
    required this.catalogView,
    required this.navigationController,
    this.logger = const DebugAppLogger(),
  });

  final CatalogViewState catalogView;
  final NavigationController navigationController;
  final AppLogger logger;
  int _activationGeneration = 0;
  ({
    String itemId,
    AppRoute route,
    int binding,
    bool directLive,
    Future<void> future,
  })?
  _pendingActivation;

  int get catalogItemCount => catalogView.itemCount;
  PrimaryNavItem get activeNavItem => navigationController.activeNavItem;

  void openHome() {
    navigationController.resetTo(const HomeRoute());
  }

  void openLiveTv() {
    navigationController.resetToHomeAndPush(
      const CatalogRoute(CatalogItemKind.live),
    );
    catalogView.showItems(CatalogItemKind.live, selectFirstGroup: true);
  }

  void openMovies() {
    navigationController.resetToHomeAndPush(
      const CatalogRoute(CatalogItemKind.movie),
    );
    catalogView.showItems(CatalogItemKind.movie, selectFirstGroup: true);
  }

  void openSeries() {
    navigationController.resetToHomeAndPush(const SeriesRoute());
    catalogView.showSeries(selectFirstGroup: true);
  }

  void openSearch() {
    navigationController.resetToHomeAndPush(const SearchRoute());
  }

  void openSeriesSeasons(SeriesSummary series) {
    navigationController.push(SeriesDetailsRoute(series));
  }

  void openSeriesEpisodes(SeriesSummary series, SeasonSummary season) {
    navigationController.push(EpisodesRoute(series, season));
    catalogView.showEpisodes(season);
  }

  void openDetails(ContentItem item) {
    navigationController.push(DetailsRoute(item));
  }

  Future<void> openDetailsById(String itemId) {
    return _activateById(itemId);
  }

  Future<void> activateItemById(
    String itemId, {
    required Future<void> Function(ContentItem) playLive,
  }) => _activateById(itemId, playLive: playLive);

  Future<void> _activateById(
    String itemId, {
    Future<void> Function(ContentItem)? playLive,
  }) {
    final route = navigationController.currentRoute;
    if ((route is DetailsRoute && route.item.id == itemId) ||
        (playLive != null && route is PlayerRoute && route.item.id == itemId)) {
      return Future<void>.value();
    }
    final binding = catalogView.bindingGeneration;
    final pending = _pendingActivation;
    if (pending != null &&
        pending.itemId == itemId &&
        identical(pending.route, route) &&
        pending.binding == binding &&
        pending.directLive == (playLive != null)) {
      return pending.future;
    }
    final generation = ++_activationGeneration;
    final future = _resolveActivation(
      itemId,
      route,
      binding,
      generation,
      playLive,
    );
    _pendingActivation = (
      itemId: itemId,
      route: route,
      binding: binding,
      directLive: playLive != null,
      future: future,
    );
    return future;
  }

  Future<void> _resolveActivation(
    String itemId,
    AppRoute route,
    int binding,
    int generation,
    Future<void> Function(ContentItem)? playLive,
  ) async {
    var routeChanged = false;
    void invalidate() {
      routeChanged = true;
      if (generation == _activationGeneration) _pendingActivation = null;
    }

    navigationController.addListener(invalidate);
    bool current() =>
        !routeChanged &&
        generation == _activationGeneration &&
        binding == catalogView.bindingGeneration &&
        identical(navigationController.currentRoute, route);
    catalogView.activationFailure.value = null;
    try {
      ContentItem? item;
      try {
        item = await catalogView.itemById(itemId);
      } catch (_) {
        if (!current()) return;
        logger.error('catalog_activation_lookup_failed');
        catalogView.activationFailure.value =
            ItemActivationFailure.lookupFailed;
        return;
      }
      if (!current()) return;
      if (item == null) {
        logger.warning('catalog_activation_item_missing');
        catalogView.activationFailure.value = ItemActivationFailure.notFound;
        return;
      }
      if (item.type == ContentType.live && playLive != null) {
        await playLive(item);
      } else {
        openDetails(item);
      }
    } finally {
      navigationController.removeListener(invalidate);
      if (generation == _activationGeneration) _pendingActivation = null;
    }
  }

  void openSettings() {
    if (navigationController.currentRoute is! SettingsRoute) {
      navigationController.push(const SettingsRoute());
    }
  }

  void goBack() => navigationController.pop();
}
