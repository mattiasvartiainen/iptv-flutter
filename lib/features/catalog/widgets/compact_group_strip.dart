import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../state/catalog_view_state.dart';

class CompactGroupStrip extends StatelessWidget {
  const CompactGroupStrip({super.key, required this.view});

  final CatalogViewState view;

  @override
  Widget build(BuildContext context) {
    if (view.groupsFailure != null ||
        (view.isLoadingGroups && view.browseGroups.isEmpty)) {
      return const SizedBox.shrink();
    }

    final height = math.max(
      48.0,
      MediaQuery.textScalerOf(context).scale(20) + 28,
    );
    return SizedBox(
      height: height,
      child: FocusTraversalGroup(
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: view.browseGroups.length + 2,
          itemBuilder: (context, index) {
            final favorite = index == 0;
            final group = index < 2 ? null : view.browseGroups[index - 2];
            final selected = favorite
                ? view.favoriteGroupSelected
                : !view.favoriteGroupSelected &&
                      !view.awaitingGroupSelection &&
                      group?.id == view.selectedGroupId;
            final label = favorite
                ? 'Favourites'
                : group?.title ?? 'All groups';
            return Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: ChoiceChip(
                    label: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: selected,
                    onSelected: (_) {
                      if (favorite) {
                        unawaited(view.selectFavorites());
                      } else {
                        unawaited(view.selectBrowseGroup(group?.id));
                      }
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
