import 'package:flutter/material.dart';

import '../../../services/catalog/catalog_query.dart';
import '../../../state/catalog_view_state.dart';
import '../../../ui/widgets/app_scope.dart';

class GroupSidebarLayout extends StatelessWidget {
  const GroupSidebarLayout({
    super.key,
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
