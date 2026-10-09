import 'package:flutter/material.dart';

import '../../app/navigation/app_route.dart';
import '../../features/catalog/widgets/group_sidebar.dart';
import '../../services/catalog/catalog_query.dart';
import '../../state/catalog_view_state.dart';
import '../../ui/theme/app_tokens.dart';
import '../../ui/widgets/app_scope.dart';
import '../../ui/widgets/app_shell_scaffold.dart';
import '../../ui/widgets/media_tile.dart';
import '../../ui/widgets/paged_grid_view.dart';
import '../../ui/widgets/state_views.dart';

const SliverGridDelegate _cardGrid = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: AppTokens.tileWidth,
  mainAxisExtent: AppTokens.tileHeight,
  crossAxisSpacing: AppTokens.gridGap,
  mainAxisSpacing: AppTokens.gridGap,
);

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key, required this.route});

  final AppRoute route;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.appControllerOf(context);
    final view = controller.catalogView;
    return switch (route) {
      CatalogRoute(kind: CatalogItemKind.live) => _ContentGrid(
        title: 'Live TV',
        groupKind: CatalogGroupKind.live,
        collection: view.items,
        emptyText: 'No live channels found yet.',
      ),
      CatalogRoute(kind: CatalogItemKind.movie) => _ContentGrid(
        title: 'Movies',
        groupKind: CatalogGroupKind.movie,
        collection: view.items,
        emptyText: 'No movies found yet.',
      ),
      SeriesRoute() => _SeriesGrid(
        groupKind: CatalogGroupKind.series,
        collection: view.series,
      ),
      SeasonsRoute(:final series) => _SeasonGrid(series: series),
      EpisodesRoute(:final series, :final season) => _EpisodeGrid(
        series: series,
        season: season,
        collection: view.episodes,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _ContentGrid extends StatelessWidget {
  const _ContentGrid({
    required this.title,
    required this.groupKind,
    required this.collection,
    required this.emptyText,
  });

  final String title;
  final CatalogGroupKind groupKind;
  final PagedCollection<CatalogItemSummary> collection;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.appControllerOf(context);
    return AppShellScaffold(
      showBack: true,
      title: title,
      child: _GridFrame(
        child: GroupSidebarLayout(
          kind: groupKind,
          collection: collection,
          seriesCollection: null,
          child: PagedGridView<CatalogItemSummary>(
            collection: collection,
            emptyMessage: emptyText,
            gridDelegate: _cardGrid,
            itemBuilder: (context, item, autofocus) => MediaTile(
              key: ValueKey<String>(item.id),
              autofocus: autofocus,
              title: item.title,
              subtitle: item.group,
              icon: item.kind == CatalogItemKind.live
                  ? Icons.live_tv
                  : Icons.movie,
              imageUrl: item.artworkUrl ?? item.logoUrl,
              onActivate: () => controller.openDetailsById(item.id),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesGrid extends StatelessWidget {
  const _SeriesGrid({required this.groupKind, required this.collection});

  final CatalogGroupKind groupKind;
  final PagedCollection<SeriesSummary> collection;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.appControllerOf(context);
    return AppShellScaffold(
      showBack: true,
      title: 'Series',
      child: _GridFrame(
        child: GroupSidebarLayout(
          kind: groupKind,
          collection: null,
          seriesCollection: collection,
          child: PagedGridView<SeriesSummary>(
            collection: collection,
            emptyMessage: 'No series episodes recognized yet.',
            gridDelegate: _cardGrid,
            itemBuilder: (context, item, autofocus) => MediaTile(
              key: ValueKey<String>(item.id),
              autofocus: autofocus,
              title: item.title,
              subtitle:
                  '${item.seasonCount} seasons · ${item.episodeCount} episodes',
              icon: Icons.tv,
              imageUrl: item.artworkUrl,
              onActivate: () => controller.openSeriesSeasons(item),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeasonGrid extends StatelessWidget {
  const _SeasonGrid({required this.series});

  final SeriesSummary? series;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.appControllerOf(context);
    final selectedSeries = series;
    return AppShellScaffold(
      showBack: true,
      title: selectedSeries == null ? 'Seasons' : selectedSeries.title,
      child: _GridFrame(
        child: selectedSeries == null
            ? const EmptyView(message: 'Pick a series from the series catalog.')
            : ListenableBuilder(
                listenable: controller.catalogView,
                builder: (context, _) {
                  final seasons = controller.catalogView.seasons;
                  if (seasons.isEmpty) {
                    return const EmptyView(message: 'No seasons found.');
                  }
                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: AppTokens.tileWidth,
                          mainAxisExtent: AppTokens.seasonTileHeight,
                          crossAxisSpacing: AppTokens.gridGap,
                          mainAxisSpacing: AppTokens.gridGap,
                        ),
                    itemCount: seasons.length,
                    itemBuilder: (context, index) {
                      final season = seasons[index];
                      return MediaTile(
                        key: ValueKey<String>(season.id),
                        autofocus: index == 0,
                        title: 'Season ${season.seasonNumber}',
                        subtitle: '${season.episodeCount} episodes',
                        icon: Icons.video_library,
                        onActivate: () => controller.openSeriesEpisodes(
                          selectedSeries,
                          season,
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({
    required this.series,
    required this.season,
    required this.collection,
  });

  final SeriesSummary? series;
  final SeasonSummary? season;
  final PagedCollection<CatalogItemSummary> collection;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.appControllerOf(context);
    final selectedSeries = series;
    final selectedSeason = season;
    return AppShellScaffold(
      showBack: true,
      title: selectedSeries == null || selectedSeason == null
          ? 'Episodes'
          : '${selectedSeries.title} · Season ${selectedSeason.seasonNumber}',
      child: _GridFrame(
        child: selectedSeason == null
            ? const EmptyView(message: 'Pick a season to browse episodes.')
            : PagedGridView<CatalogItemSummary>(
                collection: collection,
                emptyMessage: 'No episodes found.',
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: AppTokens.episodeTileWidth,
                  mainAxisExtent: AppTokens.episodeTileHeight,
                  crossAxisSpacing: AppTokens.gridGap,
                  mainAxisSpacing: AppTokens.gridGap,
                ),
                itemBuilder: (context, episode, autofocus) => MediaTile(
                  key: ValueKey<String>(episode.id),
                  autofocus: autofocus,
                  title: episode.title,
                  subtitle:
                      'Episode ${episode.episodeNumber ?? '-'}${episode.group == null || episode.group!.isEmpty ? '' : ' · ${episode.group}'}',
                  icon: Icons.play_circle_outline,
                  imageUrl: episode.artworkUrl ?? episode.logoUrl,
                  onActivate: () => controller.openDetailsById(episode.id),
                ),
              ),
      ),
    );
  }
}

class _GridFrame extends StatelessWidget {
  const _GridFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppTokens.pagePaddingFor(MediaQuery.sizeOf(context).width),
      child: child,
    );
  }
}
