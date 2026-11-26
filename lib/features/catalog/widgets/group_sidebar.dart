import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/catalog/catalog_query.dart';
import '../../../state/catalog_view_state.dart';
import '../../../ui/theme/app_tokens.dart';
import '../../../ui/widgets/app_scope.dart';
import '../../../ui/widgets/state_views.dart';
import 'compact_group_strip.dart';

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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListenableBuilder(
                listenable: view,
                builder: (context, _) => _CompactGroupSelector(view: view),
              ),
              if (constraints.maxWidth < AppTokens.compactBreakpoint)
                ListenableBuilder(
                  listenable: view,
                  builder: (context, _) =>
                      CompactGroupStrip(key: ValueKey(kind), view: view),
                ),
              Expanded(child: FocusTraversalGroup(child: child)),
            ],
          );
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
                    favoriteGroupSelected: view.favoriteGroupSelected,
                    awaitingGroupSelection: view.awaitingGroupSelection,
                    loading: view.isLoadingGroups,
                    error: view.groupsFailure,
                    totalItems:
                        collection?.total ?? seriesCollection?.total ?? 0,
                    onSelected: view.selectBrowseGroup,
                    onFavoritesSelected: view.selectFavorites,
                    onRetry: () => unawaited(view.retryBrowseGroups()),
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

class _CompactGroupSelector extends StatefulWidget {
  const _CompactGroupSelector({required this.view});

  final CatalogViewState view;

  @override
  State<_CompactGroupSelector> createState() => _CompactGroupSelectorState();
}

class _CompactGroupSelectorState extends State<_CompactGroupSelector> {
  final _focus = FocusNode(debugLabel: 'Catalog group selector');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final error = view.groupsFailure;
    if (error != null) {
      return TextButton.icon(
        focusNode: _focus,
        onPressed: () => unawaited(view.retryBrowseGroups()),
        icon: const Icon(Icons.refresh),
        label: Text(catalogFailureMessage(error)),
      );
    }
    if (view.isLoadingGroups && view.browseGroups.isEmpty) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    final selected = view.browseGroups
        .where((group) => group.id == view.selectedGroupId)
        .firstOrNull;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        focusNode: _focus,
        onPressed: () async {
          final route = DialogRoute<void>(
            context: context,
            builder: (dialogContext) => LayoutBuilder(
              builder: (context, constraints) => AlertDialog(
                title: const Text('Groups'),
                content: SizedBox(
                  width: 420,
                  height: constraints.maxHeight * 0.6,
                  child: ListView.builder(
                    itemCount: view.browseGroups.length + 2,
                    itemBuilder: (context, index) {
                      final isFavorite = index == 0;
                      final group = index < 2
                          ? null
                          : view.browseGroups[index - 2];
                      return ListTile(
                        autofocus: index == 0,
                        selected: isFavorite
                            ? view.favoriteGroupSelected
                            : !view.favoriteGroupSelected &&
                                  group?.id == view.selectedGroupId &&
                                  !view.awaitingGroupSelection,
                        title: Text(
                          isFavorite
                              ? 'Favourites'
                              : group?.title ?? 'All groups',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () {
                          Navigator.of(dialogContext).pop();
                          if (isFavorite) {
                            unawaited(view.selectFavorites());
                          } else {
                            unawaited(view.selectBrowseGroup(group?.id));
                          }
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );
          await Navigator.of(context, rootNavigator: true).push(route);
          await route.completed;
          if (context.mounted &&
              ModalRoute.of(context)?.isCurrent == true &&
              !Navigator.of(context, rootNavigator: true).canPop()) {
            _focus.requestFocus();
          }
        },
        icon: const Icon(Icons.filter_list),
        label: Text(
          'Groups: ${view.favoriteGroupSelected ? 'Favourites' : selected?.title ?? (view.awaitingGroupSelection ? 'Choose a group' : 'All groups')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _GroupFilterMenu extends StatelessWidget {
  const _GroupFilterMenu({
    required this.kind,
    required this.groups,
    required this.selectedGroupId,
    required this.favoriteGroupSelected,
    required this.awaitingGroupSelection,
    required this.loading,
    required this.error,
    required this.totalItems,
    required this.onSelected,
    required this.onFavoritesSelected,
    required this.onRetry,
  });

  final CatalogGroupKind kind;
  final List<GroupSummary> groups;
  final int? selectedGroupId;
  final bool favoriteGroupSelected;
  final bool awaitingGroupSelection;
  final bool loading;
  final CatalogFailure? error;
  final int totalItems;
  final ValueChanged<int?> onSelected;
  final VoidCallback onFavoritesSelected;
  final VoidCallback onRetry;

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
        Expanded(
          child: error == null
              ? FocusTraversalGroup(
                  child: ListView(
                    children: [
                      _GroupChoice(
                        label: 'Favourites',
                        count: favoriteGroupSelected ? totalItems : null,
                        selected: favoriteGroupSelected,
                        onTap: onFavoritesSelected,
                      ),
                      _GroupChoice(
                        label: 'All groups',
                        count:
                            selectedGroupId == null &&
                                !awaitingGroupSelection &&
                                !favoriteGroupSelected
                            ? totalItems
                            : null,
                        selected:
                            selectedGroupId == null &&
                            !awaitingGroupSelection &&
                            !favoriteGroupSelected,
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
                )
              : ErrorView(
                  message: catalogFailureMessage(error!),
                  onRetry: onRetry,
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
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    selected: selected,
    dense: true,
    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: count == null
        ? null
        : Text('$count', style: Theme.of(context).textTheme.labelSmall),
    onTap: onTap,
  );
}
