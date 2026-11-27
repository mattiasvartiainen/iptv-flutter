import 'package:flutter/material.dart';

import '../../app/navigation/app_route.dart';
import '../../features/catalog/widgets/catalog_focus_context.dart';
import '../../features/catalog/widgets/episode_layout.dart';
import '../../features/catalog/widgets/group_sidebar.dart';
import '../../services/catalog/catalog_query.dart';
import '../../state/catalog_view_state.dart';
import '../../ui/catalog_item_kind_presentation.dart';
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

SliverGridDelegate _posterGrid(BuildContext context) =>
    SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: AppTokens.posterTileWidth,
      mainAxisExtent: AppTokens.posterTileHeightFor(
        MediaQuery.textScalerOf(context),
      ),
      crossAxisSpacing: AppTokens.gridGap,
      mainAxisSpacing: AppTokens.gridGap,
    );

SliverGridDelegate _viewGrid(
  BuildContext context,
  SliverGridDelegate cards, {
  bool? listView,
  double extraListExtent = 0,
}) => (listView ?? AppScope.preferencesControllerOf(context).useListView)
    ? SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 1,
        mainAxisExtent:
            AppTokens.mediaListExtentFor(MediaQuery.textScalerOf(context)) +
            extraListExtent,
      )
    : cards;

String? _seriesGroup(CatalogViewState view, SeriesSummary series) => view
    .browseGroups
    .where((group) => group.id == series.groupId)
    .firstOrNull
    ?.title;

String _seriesSubtitle(CatalogViewState view, SeriesSummary series) {
  final group = _seriesGroup(view, series);
  return '${series.seasonCount} seasons · ${series.episodeCount} episodes'
      '${group == null || group.isEmpty ? '' : ' · $group'}';
}

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key, required this.route});

  final AppRoute route;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.appControllerOf(context);
    final view = controller.catalogView;
    return ListenableBuilder(
      listenable: AppScope.preferencesControllerOf(context),
      builder: (context, _) => switch (route) {
        CatalogRoute(kind: CatalogItemKind.live) => _ContentGrid(
          key: const ValueKey(CatalogGroupKind.live),
          title: 'Live TV',
          groupKind: CatalogGroupKind.live,
          collection: view.items,
          emptyText: 'No live channels found yet.',
        ),
        CatalogRoute(kind: CatalogItemKind.movie) => _ContentGrid(
          key: const ValueKey(CatalogGroupKind.movie),
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
      },
    );
  }
}

class _ContentGrid extends StatelessWidget {
  const _ContentGrid({
    super.key,
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
    final isLive = groupKind == CatalogGroupKind.live;
    final preferences = AppScope.preferencesControllerOf(context);
    final listView = isLive
        ? preferences.liveUseListView
        : preferences.useListView;
    return AppShellScaffold(
      showBack: true,
      title: title,
      child: ListenableBuilder(
        listenable: controller.catalogView,
        builder: (context, _) => Column(
          children: [
            if (controller.catalogView.sortFailureFor(groupKind)
                case final failure?)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  catalogFailureMessage(failure),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _GridFrame(
                child: GroupSidebarLayout(
                  kind: groupKind,
                  collection: collection,
                  seriesCollection: null,
                  child: CatalogFocusContext<CatalogItemSummary>(
                    collection: collection,
                    idOf: (item) => item.id,
                    builder: (context, showContext) =>
                        PagedGridView<CatalogItemSummary>(
                          resetScrollOnLoad: true,
                          preserveFocusedItemOnLayoutChange: true,
                          collection: collection,
                          emptyMessage:
                              controller.catalogView.favoriteGroupSelected
                              ? 'No favourites in this section yet.'
                              : controller.catalogView.awaitingGroupSelection
                              ? 'No automatically selected group. Choose a group to browse.'
                              : emptyText,
                          gridDelegate: _viewGrid(
                            context,
                            isLive ? _cardGrid : _posterGrid(context),
                            listView: listView,
                            extraListExtent: isLive ? 8 : 0,
                          ),
                          itemBuilder: (context, item, autofocus) => MediaTile(
                            listView: listView,
                            presentation: isLive
                                ? MediaTilePresentation.standard
                                : MediaTilePresentation.poster,
                            showListArtwork: isLive,
                            keepAliveWhileFocused: true,
                            onFocusChanged: (focused) {
                              if (focused) {
                                showContext(
                                  CatalogContextSummary(
                                    id: item.id,
                                    title: item.title,
                                    group: item.group,
                                    icon: item.kind.icon,
                                    artworkUrl: item.artworkUrl ?? item.logoUrl,
                                  ),
                                );
                              }
                            },
                            key: ValueKey<String>(item.id),
                            autofocus: autofocus,
                            title: item.title,
                            subtitle: item.group,
                            icon: item.kind.icon,
                            imageUrl: item.artworkUrl ?? item.logoUrl,
                            onActivate: () =>
                                AppScope.activateSummary(context, item),
                          ),
                        ),
                  ),
                ),
              ),
            ),
          ],
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
      child: ListenableBuilder(
        listenable: controller.catalogView,
        builder: (context, _) => Column(
          children: [
            if (controller.catalogView.sortFailureFor(groupKind)
                case final failure?)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  catalogFailureMessage(failure),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _GridFrame(
                child: GroupSidebarLayout(
                  kind: groupKind,
                  collection: null,
                  seriesCollection: collection,
                  child: CatalogFocusContext<SeriesSummary>(
                    collection: collection,
                    idOf: (item) => item.id,
                    builder: (context, showContext) => PagedGridView<SeriesSummary>(
                      resetScrollOnLoad: true,
                      preserveFocusedItemOnLayoutChange: true,
                      collection: collection,
                      emptyMessage: controller.catalogView.favoriteGroupSelected
                          ? 'No favourites in this section yet.'
                          : controller.catalogView.awaitingGroupSelection
                          ? 'No automatically selected group. Choose a group to browse.'
                          : 'No series episodes recognized yet.',
                      gridDelegate: _viewGrid(context, _posterGrid(context)),
                      itemBuilder: (context, item, autofocus) => MediaTile(
                        listView: AppScope.preferencesControllerOf(
                          context,
                        ).useListView,
                        presentation: MediaTilePresentation.poster,
                        keepAliveWhileFocused: true,
                        onFocusChanged: (focused) {
                          if (focused) {
                            showContext(
                              CatalogContextSummary(
                                id: item.id,
                                title: item.title,
                                group: _seriesGroup(
                                  controller.catalogView,
                                  item,
                                ),
                                counts:
                                    '${item.seasonCount} seasons · ${item.episodeCount} episodes',
                                icon: Icons.tv,
                                artworkUrl: item.artworkUrl,
                              ),
                            );
                          }
                        },
                        key: ValueKey<String>(item.id),
                        autofocus: autofocus,
                        title: item.title,
                        subtitle: _seriesSubtitle(controller.catalogView, item),
                        icon: Icons.tv,
                        imageUrl: item.artworkUrl,
                        onActivate: () => controller.openSeriesSeasons(item),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
                    gridDelegate: _viewGrid(
                      context,
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: AppTokens.tileWidth,
                        mainAxisExtent: AppTokens.seasonTileHeight,
                        crossAxisSpacing: AppTokens.gridGap,
                        mainAxisSpacing: AppTokens.gridGap,
                      ),
                    ),
                    itemCount: seasons.length,
                    itemBuilder: (context, index) {
                      final season = seasons[index];
                      return MediaTile(
                        listView: AppScope.preferencesControllerOf(
                          context,
                        ).useListView,
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
            : LayoutBuilder(
                builder: (context, constraints) {
                  final layout = EpisodeLayout(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    listPreference: AppScope.preferencesControllerOf(
                      context,
                    ).useListView,
                    textScaler: MediaQuery.textScalerOf(context),
                  );
                  return PagedGridView<CatalogItemSummary>(
                    collection: collection,
                    emptyMessage: 'No episodes found.',
                    preserveFocusedItemOnLayoutChange: true,
                    gridDelegate: layout.gridDelegate,
                    itemBuilder: (context, episode, autofocus) => MediaTile(
                      listView: layout.isRow,
                      episodeRow: layout.isRow,
                      keepAliveWhileFocused: true,
                      key: ValueKey<String>(episode.id),
                      autofocus: autofocus,
                      title: episode.title,
                      subtitle:
                          'Episode ${episode.episodeNumber ?? '-'}${episode.group == null || episode.group!.isEmpty ? '' : ' · ${episode.group}'}',
                      icon: Icons.play_circle_outline,
                      imageUrl: episode.artworkUrl ?? episode.logoUrl,
                      onActivate: () =>
                          AppScope.activateSummary(context, episode),
                    ),
                  );
                },
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
