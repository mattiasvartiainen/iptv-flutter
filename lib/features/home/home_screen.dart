import 'package:flutter/material.dart';

import '../../app/navigation/app_route.dart';
import '../../services/catalog/catalog_query.dart';
import '../../ui/theme/app_tokens.dart';
import '../../ui/widgets/app_scope.dart';
import '../../ui/widgets/app_shell_scaffold.dart';
import '../../ui/widgets/media_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.appControllerOf(context);
    final preferences = AppScope.preferencesControllerOf(context);
    final isHomeRoute =
        AppScope.navigationControllerOf(context).currentRoute is HomeRoute;

    return AppShellScaffold(
      child: ListenableBuilder(
        listenable: Listenable.merge([c.catalogView, preferences]),
        builder: (context, _) {
          final focusLive =
              isHomeRoute &&
              preferences.showHomeLiveTv &&
              c.catalogView.homeLive.isNotEmpty;
          final focusMovies =
              isHomeRoute &&
              !focusLive &&
              preferences.showHomeMovies &&
              c.catalogView.homeMovies.isNotEmpty;
          final focusSeries =
              isHomeRoute &&
              !focusLive &&
              !focusMovies &&
              preferences.showHomeSeries &&
              c.catalogView.homeSeries.isNotEmpty;
          return FocusTraversalGroup(
            child: ListView(
              padding: AppTokens.homePaddingFor(
                MediaQuery.sizeOf(context).width,
              ),
              children: [
                if (preferences.showHomeLiveTv) ...[
                  _SectionHeader(
                    title: 'Live TV',
                    actionLabel: 'See all',
                    onAction: c.openLiveTv,
                  ),
                  _ContentStrip(
                    items: c.catalogView.homeLive,
                    emptyText: 'No live channels found yet.',
                    onTap: (item) => c.openDetailsById(item.id),
                    autofocusFirst: focusLive,
                  ),
                  const SizedBox(height: AppTokens.sectionGap),
                ],
                if (preferences.showHomeMovies) ...[
                  _SectionHeader(
                    title: 'Movies',
                    actionLabel: 'See all',
                    onAction: c.openMovies,
                  ),
                  _ContentStrip(
                    items: c.catalogView.homeMovies,
                    emptyText: 'No movies found yet.',
                    onTap: (item) => c.openDetailsById(item.id),
                    autofocusFirst: focusMovies,
                  ),
                  const SizedBox(height: AppTokens.sectionGap),
                ],
                if (preferences.showHomeSeries) ...[
                  _SectionHeader(
                    title: 'Series',
                    actionLabel: 'See all',
                    onAction: c.openSeries,
                  ),
                  _SeriesStrip(
                    series: c.catalogView.homeSeries,
                    autofocusFirst: focusSeries,
                  ),
                ],
                if (!preferences.showHomeLiveTv &&
                    !preferences.showHomeMovies &&
                    !preferences.showHomeSeries)
                  const _EmptyTile(
                    text:
                        'All Home sections are hidden by settings. Re-enable them in storage settings.',
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _ContentStrip extends StatelessWidget {
  const _ContentStrip({
    required this.items,
    required this.emptyText,
    required this.onTap,
    required this.autofocusFirst,
  });

  final List<CatalogItemSummary> items;
  final String emptyText;
  final ValueChanged<CatalogItemSummary> onTap;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyTile(text: emptyText);
    }

    return SizedBox(
      height: AppTokens.homeStripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: AppTokens.homeStripGap),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: AppTokens.tileWidth,
            child: MediaTile(
              key: ValueKey<String>(item.id),
              autofocus: autofocusFirst && index == 0,
              title: item.title,
              subtitle: item.group,
              icon: item.kind == CatalogItemKind.live
                  ? Icons.live_tv
                  : Icons.movie,
              imageUrl: item.artworkUrl ?? item.logoUrl,
              onActivate: () => onTap(item),
            ),
          );
        },
      ),
    );
  }
}

class _SeriesStrip extends StatelessWidget {
  const _SeriesStrip({required this.series, required this.autofocusFirst});

  final List<SeriesSummary> series;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.appControllerOf(context);
    if (series.isEmpty) {
      return const _EmptyTile(text: 'No series episodes recognized yet.');
    }

    return SizedBox(
      height: AppTokens.homeStripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: series.length,
        separatorBuilder: (_, _) =>
            const SizedBox(width: AppTokens.homeStripGap),
        itemBuilder: (context, index) {
          final value = series[index];
          return SizedBox(
            width: AppTokens.episodeTileWidth,
            child: MediaTile(
              key: ValueKey<String>(value.id),
              autofocus: autofocusFirst && index == 0,
              title: value.title,
              subtitle:
                  '${value.seasonCount} seasons · ${value.episodeCount} episodes',
              icon: Icons.tv,
              imageUrl: value.artworkUrl,
              onActivate: () => c.openSeriesSeasons(value),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  const _EmptyTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: Card(
        child: Center(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ),
    );
  }
}
