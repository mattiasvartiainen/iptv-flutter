import 'package:flutter/material.dart';

import '../services/catalog/catalog_query.dart';
import '../state/app_controller.dart';
import '../state/catalog_view_state.dart';
import '../widgets/app_scope.dart';
import '../widgets/app_shell_scaffold.dart';

/// How close to the end of the built tiles before the next page is requested.
const int _prefetchThreshold = 30;

const SliverGridDelegate _cardGrid = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 300,
  mainAxisExtent: 180,
  crossAxisSpacing: 20,
  mainAxisSpacing: 20,
);

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final view = controller.catalogView;
    return switch (controller.screen) {
      AppScreen.liveCatalog => _ContentGrid(
        title: 'Live TV',
        collection: view.items,
        emptyText: 'No live channels found yet.',
      ),
      AppScreen.movieCatalog => _ContentGrid(
        title: 'Movies',
        collection: view.items,
        emptyText: 'No movies found yet.',
      ),
      AppScreen.seriesCatalog => _SeriesGrid(collection: view.series),
      AppScreen.seasonCatalog => _SeasonGrid(series: controller.selectedSeries),
      AppScreen.episodeCatalog => _EpisodeGrid(
        series: controller.selectedSeries,
        season: controller.selectedSeason,
        collection: view.episodes,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Renders one page window and pulls the next page as the user nears the end.
class _PagedGrid<T> extends StatelessWidget {
  const _PagedGrid({
    required this.collection,
    required this.emptyText,
    required this.gridDelegate,
    required this.itemBuilder,
  });

  final PagedCollection<T> collection;
  final String emptyText;
  final SliverGridDelegate gridDelegate;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: collection,
      builder: (context, _) {
        if (collection.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = collection.errorMessage;
        if (error != null && collection.items.isEmpty) {
          return _EmptyMessage(text: error);
        }
        if (collection.items.isEmpty) {
          return _EmptyMessage(text: emptyText);
        }

        final items = collection.items;
        return GridView.builder(
          gridDelegate: gridDelegate,
          itemCount: items.length + (collection.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return const Center(child: CircularProgressIndicator());
            }
            if (collection.hasMore &&
                index >= items.length - _prefetchThreshold) {
              // Deferred because loadMore notifies listeners mid-build otherwise.
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => collection.loadMore(),
              );
            }
            return itemBuilder(context, items[index]);
          },
        );
      },
    );
  }
}

class _ContentGrid extends StatelessWidget {
  const _ContentGrid({
    required this.title,
    required this.collection,
    required this.emptyText,
  });

  final String title;
  final PagedCollection<CatalogItemSummary> collection;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return AppShellScaffold(
      showBack: true,
      title: title,
      child: _GridFrame(
        child: _PagedGrid<CatalogItemSummary>(
          collection: collection,
          emptyText: emptyText,
          gridDelegate: _cardGrid,
          itemBuilder: (context, item) => Card(
            child: InkWell(
              onTap: () => controller.openDetailsById(item.id),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      item.kind == CatalogItemKind.live
                          ? Icons.live_tv
                          : Icons.movie,
                    ),
                    const Spacer(),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.group ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeriesGrid extends StatelessWidget {
  const _SeriesGrid({required this.collection});

  final PagedCollection<SeriesSummary> collection;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return AppShellScaffold(
      showBack: true,
      title: 'Series',
      child: _GridFrame(
        child: _PagedGrid<SeriesSummary>(
          collection: collection,
          emptyText: 'No series episodes recognized yet.',
          gridDelegate: _cardGrid,
          itemBuilder: (context, item) => Card(
            child: InkWell(
              onTap: () => controller.openSeriesSeasons(item),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.tv),
                    const Spacer(),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${item.seasonCount} seasons · ${item.episodeCount} episodes',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
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
    final controller = AppScope.of(context);
    final selectedSeries = series;
    return AppShellScaffold(
      showBack: true,
      title: selectedSeries == null ? 'Seasons' : selectedSeries.title,
      child: _GridFrame(
        child: selectedSeries == null
            ? const _EmptyMessage(
                text: 'Pick a series from the series catalog.',
              )
            : ListenableBuilder(
                listenable: controller.catalogView,
                builder: (context, _) {
                  final seasons = controller.catalogView.seasons;
                  if (seasons.isEmpty) {
                    return const _EmptyMessage(text: 'No seasons found.');
                  }
                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          mainAxisExtent: 150,
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                        ),
                    itemCount: seasons.length,
                    itemBuilder: (context, index) {
                      final season = seasons[index];
                      return Card(
                        child: InkWell(
                          onTap: () => controller.openSeriesEpisodes(season),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Season ${season.seasonNumber}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const Spacer(),
                                Text('${season.episodeCount} episodes'),
                              ],
                            ),
                          ),
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
    final controller = AppScope.of(context);
    final selectedSeries = series;
    final selectedSeason = season;
    return AppShellScaffold(
      showBack: true,
      title: selectedSeries == null || selectedSeason == null
          ? 'Episodes'
          : '${selectedSeries.title} · Season ${selectedSeason.seasonNumber}',
      child: _GridFrame(
        child: selectedSeason == null
            ? const _EmptyMessage(text: 'Pick a season to browse episodes.')
            : _PagedGrid<CatalogItemSummary>(
                collection: collection,
                emptyText: 'No episodes found.',
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisExtent: 170,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                itemBuilder: (context, episode) => Card(
                  child: InkWell(
                    onTap: () => controller.openDetailsById(episode.id),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Episode ${episode.episodeNumber ?? '-'}',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Text(
                              episode.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            episode.group ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
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
      padding: const EdgeInsets.fromLTRB(40, 8, 40, 28),
      child: child,
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text));
  }
}
