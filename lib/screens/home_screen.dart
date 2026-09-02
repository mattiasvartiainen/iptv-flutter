import 'package:flutter/material.dart';
import '../services/catalog/catalog_query.dart';
import '../widgets/app_scope.dart';
import '../widgets/app_shell_scaffold.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);

    return AppShellScaffold(
      child: ListenableBuilder(
        listenable: c.catalogView,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 28),
          children: [
            if (c.showHomeLiveTv) ...[
              _SectionHeader(
                title: 'Live TV',
                actionLabel: 'See all',
                onAction: c.openLiveTv,
              ),
              _ContentStrip(
                items: c.catalogView.homeLive,
                emptyText: 'No live channels found yet.',
                onTap: (item) => c.openDetailsById(item.id),
              ),
              const SizedBox(height: 28),
            ],
            if (c.showHomeMovies) ...[
              _SectionHeader(
                title: 'Movies',
                actionLabel: 'See all',
                onAction: c.openMovies,
              ),
              _ContentStrip(
                items: c.catalogView.homeMovies,
                emptyText: 'No movies found yet.',
                onTap: (item) => c.openDetailsById(item.id),
              ),
              const SizedBox(height: 28),
            ],
            if (c.showHomeSeries) ...[
              _SectionHeader(
                title: 'Series',
                actionLabel: 'See all',
                onAction: c.openSeries,
              ),
              _SeriesStrip(series: c.catalogView.homeSeries),
            ],
            if (!c.showHomeLiveTv && !c.showHomeMovies && !c.showHomeSeries)
              const _EmptyTile(
                text:
                    'All Home sections are hidden by settings. Re-enable them in storage settings.',
              ),
          ],
        ),
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
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
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
  });

  final List<CatalogItemSummary> items;
  final String emptyText;
  final ValueChanged<CatalogItemSummary> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _EmptyTile(text: emptyText);
    }

    return SizedBox(
      height: 182,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final item = items[index];
          return _ContentCard(item: item, onTap: () => onTap(item));
        },
      ),
    );
  }
}

class _SeriesStrip extends StatelessWidget {
  const _SeriesStrip({required this.series});

  final List<SeriesSummary> series;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    if (series.isEmpty) {
      return const _EmptyTile(text: 'No series episodes recognized yet.');
    }

    return SizedBox(
      height: 182,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: series.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final value = series[index];
          return SizedBox(
            width: 320,
            child: Card(
              child: InkWell(
                onTap: () => c.openSeriesSeasons(value),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.tv),
                      const Spacer(),
                      Text(
                        value.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${value.seasonCount} seasons · ${value.episodeCount} episodes',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.item, required this.onTap});

  final CatalogItemSummary item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
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
                const SizedBox(height: 6),
                Text(
                  item.group ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
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
