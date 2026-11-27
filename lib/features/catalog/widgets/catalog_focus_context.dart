import 'package:flutter/material.dart';

import '../../../state/catalog_view_state.dart';
import '../../../ui/theme/app_tokens.dart';
import '../../../ui/widgets/media_artwork.dart';

class CatalogContextSummary {
  const CatalogContextSummary({
    required this.id,
    required this.title,
    required this.icon,
    this.group,
    this.artworkUrl,
    this.counts,
  });

  final String id;
  final String title;
  final IconData icon;
  final String? group;
  final String? artworkUrl;
  final String? counts;
}

class CatalogFocusContext<T> extends StatefulWidget {
  const CatalogFocusContext({
    super.key,
    required this.collection,
    required this.idOf,
    required this.builder,
  });

  final PagedCollection<T> collection;
  final String Function(T) idOf;
  final Widget Function(BuildContext, ValueChanged<CatalogContextSummary>)
  builder;

  @override
  State<CatalogFocusContext<T>> createState() => _CatalogFocusContextState<T>();
}

class _CatalogFocusContextState<T> extends State<CatalogFocusContext<T>> {
  final _summary = ValueNotifier<CatalogContextSummary?>(null);

  @override
  void initState() {
    super.initState();
    widget.collection.addListener(_collectionChanged);
  }

  @override
  void didUpdateWidget(covariant CatalogFocusContext<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection != widget.collection) {
      oldWidget.collection.removeListener(_collectionChanged);
      widget.collection.addListener(_collectionChanged);
      _summary.value = null;
    }
  }

  void _collectionChanged() {
    final selected = _summary.value;
    if (selected != null &&
        (widget.collection.isLoading ||
            !widget.collection.items.any(
              (item) => widget.idOf(item) == selected.id,
            ))) {
      _summary.value = null;
    }
  }

  void _show(CatalogContextSummary summary) {
    if (widget.collection.items.any(
      (item) => widget.idOf(item) == summary.id,
    )) {
      _summary.value = summary;
    }
  }

  @override
  void dispose() {
    widget.collection.removeListener(_collectionChanged);
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final showPanel =
          constraints.maxWidth >= 900 && constraints.maxHeight >= 400;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.builder(context, _show)),
          if (showPanel) ...[
            const SizedBox(width: 24),
            SizedBox(
              width: 300,
              child: ValueListenableBuilder<CatalogContextSummary?>(
                valueListenable: _summary,
                builder: (context, summary, _) =>
                    CatalogContextPanel(summary: summary),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class CatalogContextPanel extends StatelessWidget {
  const CatalogContextPanel({super.key, required this.summary});
  final CatalogContextSummary? summary;

  @override
  Widget build(BuildContext context) {
    final summary = this.summary;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
      ),
      child: summary == null
          ? const SizedBox.expand()
          : ExcludeSemantics(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppTokens.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 180,
                      width: double.infinity,
                      child: MediaArtwork(
                        imageUrl: summary.artworkUrl,
                        fallbackIcon: summary.icon,
                        resizePolicy: ResizeImagePolicy.fit,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(summary.title, style: theme.textTheme.titleLarge),
                    if (summary.group case final group?
                        when group.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(group, style: theme.textTheme.bodyMedium),
                    ],
                    if (summary.counts case final counts?) ...[
                      const SizedBox(height: 8),
                      Text(counts, style: theme.textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
