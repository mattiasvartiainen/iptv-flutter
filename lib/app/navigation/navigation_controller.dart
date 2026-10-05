import 'package:flutter/foundation.dart';

import '../../services/catalog/catalog_query.dart';
import 'app_route.dart';

enum PrimaryNavItem { home, liveTv, movies, series, search }

class NavigationController extends ChangeNotifier {
  final List<AppRoute> _routes = [const HomeRoute()];

  List<AppRoute> get stack => List<AppRoute>.unmodifiable(_routes);

  AppRoute get currentRoute => _routes.last;

  PrimaryNavItem get activeNavItem {
    for (final route in _routes.reversed) {
      final item = switch (route) {
        HomeRoute() => PrimaryNavItem.home,
        CatalogRoute(kind: CatalogItemKind.live) => PrimaryNavItem.liveTv,
        CatalogRoute(kind: CatalogItemKind.movie) => PrimaryNavItem.movies,
        SeriesRoute() ||
        SeasonsRoute() ||
        EpisodesRoute() => PrimaryNavItem.series,
        SearchRoute() => PrimaryNavItem.search,
        CatalogRoute() ||
        DetailsRoute() ||
        PlayerRoute() ||
        SettingsRoute() => null,
      };
      if (item != null) return item;
    }
    return PrimaryNavItem.home;
  }

  void push(AppRoute route) {
    _routes.add(route);
    notifyListeners();
  }

  void pop() {
    if (_routes.length == 1) return;
    _routes.removeLast();
    notifyListeners();
  }

  bool popIfCurrent(AppRoute route) {
    if (_routes.length == 1 || !identical(_routes.last, route)) return false;
    pop();
    return true;
  }

  void replaceTop(AppRoute route) {
    _routes[_routes.length - 1] = route;
    notifyListeners();
  }

  void resetTo(AppRoute route) {
    _routes
      ..clear()
      ..add(route);
    notifyListeners();
  }

  void resetToHomeAndPush(AppRoute route) {
    _routes
      ..clear()
      ..add(const HomeRoute())
      ..add(route);
    notifyListeners();
  }
}
