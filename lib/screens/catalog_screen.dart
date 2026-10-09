import 'package:flutter/material.dart';

import '../app/navigation/app_route.dart';
import '../services/catalog/catalog_query.dart';
import '../state/catalog_view_state.dart';
import '../ui/theme/app_tokens.dart';
import '../ui/widgets/media_tile.dart';
import '../widgets/app_scope.dart';
import '../widgets/app_shell_scaffold.dart';

/// How close to the end of the built tiles before the next page is requested.
const int _prefetchThreshold = 30;

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
  final Widget Function(BuildContext context, T item, bool autofocus)
  itemBuilder;

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
            return itemBuilder(context, items[index], index == 0);
          },
        );
      },
    );
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
        child: _GroupSidebarLayout(
          kind: groupKind,
          collection: collection,
          seriesCollection: null,
          child: _PagedGrid<CatalogItemSummary>(
            collection: collection,
            emptyText: emptyText,
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
        child: _GroupSidebarLayout(
          kind: groupKind,
          collection: null,
          seriesCollection: collection,
          child: _PagedGrid<SeriesSummary>(
            collection: collection,
            emptyText: 'No series episodes recognized yet.',
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

class _GroupSidebarLayout extends StatelessWidget {
  const _GroupSidebarLayout({
    required this.kind,
    required this.collection,
    required this.seriesCollection,
    required this.child,
  });

  final CatalogGroupKind kind;
  final PagedCollection<CatalogItemSummary>? collection;
  final PagedCollection<SeriesSummary>? seriesCollection;
  final Widget child;

  static const double _sidebarBreakpoint = 1050;
  static const double _sidebarWidth = 250;

  @override
  Widget build(BuildContext context) {
    final view = AppScope.appControllerOf(context).catalogView;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _sidebarBreakpoint) {
          return FocusTraversalGroup(child: child);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FocusTraversalGroup(
              child: SizedBox(
                width: _sidebarWidth,
                child: ListenableBuilder(
                  listenable: Listenable.merge([
                    view,
                    ?collection,
                    ?seriesCollection,
                  ]),
                  builder: (context, _) => _GroupFilterMenu(
                    kind: kind,
                    groups: view.browseGroups,
                    selectedGroupId: view.selectedGroupId,
                    loading: view.isLoadingGroups,
                    error: view.groupsErrorMessage,
                    totalItems:
                        collection?.total ?? seriesCollection?.total ?? 0,
                    onSelected: view.selectBrowseGroup,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(child: FocusTraversalGroup(child: child)),
          ],
        );
      },
    );
  }
}

class _GroupFilterMenu extends StatelessWidget {
  const _GroupFilterMenu({
    required this.kind,
    required this.groups,
    required this.selectedGroupId,
    required this.loading,
    required this.error,
    required this.totalItems,
    required this.onSelected,
  });

  final CatalogGroupKind kind;
  final List<GroupSummary> groups;
  final int? selectedGroupId;
  final bool loading;
  final String? error;
  final int totalItems;
  final ValueChanged<int?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Text(
            'GROUPS',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error!, style: theme.textTheme.bodySmall),
          ),
        Expanded(
          child: FocusTraversalGroup(
            child: ListView(
              children: [
                _GroupChoice(
                  label: 'All groups',
                  count: totalItems,
                  selected: selectedGroupId == null,
                  onTap: () => onSelected(null),
                ),
                for (final group in groups)
                  _GroupChoice(
                    label: group.title,
                    count: group.itemCount,
                    selected: selectedGroupId == group.id,
                    onTap: () => onSelected(group.id),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupChoice extends StatelessWidget {
  const _GroupChoice({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    selected: selected,
    dense: true,
    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: Text('$count', style: Theme.of(context).textTheme.labelSmall),
    onTap: onTap,
  );
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
            ? const _EmptyMessage(text: 'Pick a season to browse episodes.')
            : _PagedGrid<CatalogItemSummary>(
                collection: collection,
                emptyText: 'No episodes found.',
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

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(text));
  }
}
