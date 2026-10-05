import '../../models/content_item.dart';
import '../../services/catalog/catalog_query.dart';

sealed class AppRoute {
  const AppRoute();
}

final class HomeRoute extends AppRoute {
  const HomeRoute();
}

final class CatalogRoute extends AppRoute {
  const CatalogRoute(this.kind);

  final CatalogItemKind kind;
}

final class SeriesRoute extends AppRoute {
  const SeriesRoute();
}

final class SeasonsRoute extends AppRoute {
  const SeasonsRoute(this.series);

  final SeriesSummary series;
}

final class EpisodesRoute extends AppRoute {
  const EpisodesRoute(this.series, this.season);

  final SeriesSummary series;
  final SeasonSummary season;
}

final class DetailsRoute extends AppRoute {
  const DetailsRoute(this.item);

  final ContentItem item;
}

final class PlayerRoute extends AppRoute {
  const PlayerRoute(this.item);

  final ContentItem item;
}

final class SearchRoute extends AppRoute {
  const SearchRoute();
}

final class SettingsRoute extends AppRoute {
  const SettingsRoute();
}
