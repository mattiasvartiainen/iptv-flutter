import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/catalog_view_state.dart';
import 'state_views.dart';

const int _defaultPrefetchThreshold = 30;

class PagedGridView<T> extends StatefulWidget {
  const PagedGridView({
    super.key,
    required this.collection,
    required this.emptyMessage,
    required this.gridDelegate,
    required this.itemBuilder,
    this.prefetchThreshold = _defaultPrefetchThreshold,
    this.onRetry,
    this.emptyIcon,
    this.resetScrollOnLoad = false,
    this.preserveFocusedItemOnLayoutChange = false,
  }) : assert(prefetchThreshold > 0);

  final PagedCollection<T> collection;
  final String emptyMessage;
  final SliverGridDelegate gridDelegate;
  final Widget Function(BuildContext context, T item, bool autofocus)
  itemBuilder;
  final int prefetchThreshold;
  final VoidCallback? onRetry;
  final IconData? emptyIcon;
  final bool resetScrollOnLoad;
  final bool preserveFocusedItemOnLayoutChange;

  @override
  State<PagedGridView<T>> createState() => _PagedGridViewState<T>();
}

class _PagedGridViewState<T> extends State<PagedGridView<T>> {
  late final ScrollController _scrollController;
  bool _firstLayoutCheckScheduled = false;
  bool _loadScheduled = false;
  double _viewportWidth = 0;
  bool _autofocusFirstItem = true;
  int? _focusedIndex;
  FocusNode? _focusedNode;
  (double, double, int, double, double)? _focusLayout;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      keepScrollOffset: !widget.resetScrollOnLoad,
    );
    _scrollController.addListener(_checkScrollThreshold);
    widget.collection.addListener(_collectionChanged);
    _scheduleFirstLayoutCheck();
  }

  @override
  void didUpdateWidget(covariant PagedGridView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection != widget.collection) {
      oldWidget.collection.removeListener(_collectionChanged);
      widget.collection.addListener(_collectionChanged);
      _loadScheduled = false;
      _firstLayoutCheckScheduled = false;
      _scheduleFirstLayoutCheck();
    }
  }

  @override
  void dispose() {
    widget.collection.removeListener(_collectionChanged);
    _scrollController
      ..removeListener(_checkScrollThreshold)
      ..dispose();
    super.dispose();
  }

  void _collectionChanged() {
    if (!mounted) return;
    if (widget.resetScrollOnLoad && widget.collection.isLoading) {
      final focused = FocusManager.instance.primaryFocus;
      _autofocusFirstItem =
          focused == null ||
          focused is FocusScopeNode ||
          focused.context?.findAncestorStateOfType<_PagedGridViewState<T>>() ==
              this;
    }
    if (widget.resetScrollOnLoad &&
        widget.collection.isLoading &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (!widget.collection.hasMore || widget.collection.isLoadingMore) {
      _loadScheduled = false;
    }
    _scheduleFirstLayoutCheck();
  }

  void _scheduleFirstLayoutCheck() {
    if (_firstLayoutCheckScheduled || !mounted) return;
    _firstLayoutCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _firstLayoutCheckScheduled = false;
      _checkScrollThreshold();
    });
  }

  void _checkScrollThreshold() {
    final collection = widget.collection;
    if (!mounted ||
        _loadScheduled ||
        collection.isLoading ||
        collection.isLoadingMore ||
        collection.failure != null ||
        !collection.hasMore) {
      return;
    }

    final shouldPrefetch =
        !_scrollController.hasClients ||
        _scrollController.position.extentAfter <=
            _prefetchExtentForWidth(_viewportWidth);
    if (!shouldPrefetch) return;

    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = widget.collection;
      if (current.isLoading || current.isLoadingMore || !current.hasMore) {
        _loadScheduled = false;
        return;
      }
      unawaited(current.loadMore());
    });
  }

  double _prefetchExtentForWidth(double width) {
    final delegate = widget.gridDelegate;
    late final int columns;
    late final double rowExtent;
    if (delegate is SliverGridDelegateWithFixedCrossAxisCount) {
      columns = delegate.crossAxisCount;
      rowExtent =
          delegate.mainAxisExtent ??
          (width - delegate.crossAxisSpacing * (columns - 1)) /
              columns /
              delegate.childAspectRatio;
      return (widget.prefetchThreshold / columns).ceil() *
          (rowExtent + delegate.mainAxisSpacing);
    }

    if (delegate is! SliverGridDelegateWithMaxCrossAxisExtent) return 600;
    columns = math.max(
      1,
      ((width + delegate.crossAxisSpacing) /
              (delegate.maxCrossAxisExtent + delegate.crossAxisSpacing))
          .floor(),
    );
    rowExtent = delegate.mainAxisExtent ?? 180;
    final rows = (widget.prefetchThreshold / columns).ceil();
    return rows * (rowExtent + delegate.mainAxisSpacing);
  }

  void _preserveFocusOnLayoutChange(BoxConstraints constraints) {
    final delegate = widget.gridDelegate;
    if (!widget.preserveFocusedItemOnLayoutChange) return;
    final (columns, extent, spacing) = switch (delegate) {
      SliverGridDelegateWithFixedCrossAxisCount(
        :final crossAxisCount,
        mainAxisExtent: final double extent,
        :final mainAxisSpacing,
      ) =>
        (crossAxisCount, extent, mainAxisSpacing),
      SliverGridDelegateWithMaxCrossAxisExtent(
        :final maxCrossAxisExtent,
        :final crossAxisSpacing,
        mainAxisExtent: final double extent,
        :final mainAxisSpacing,
      ) =>
        (
          math.max(
            1,
            (constraints.maxWidth / (maxCrossAxisExtent + crossAxisSpacing))
                .ceil(),
          ),
          extent,
          mainAxisSpacing,
        ),
      _ => (0, 0.0, 0.0),
    };
    if (columns == 0) return;
    final next = (
      constraints.maxWidth,
      constraints.maxHeight,
      columns,
      extent,
      spacing,
    );
    final previous = _focusLayout;
    _focusLayout = next;
    if (previous == null || previous == next || _focusedIndex == null) return;
    final node = FocusManager.instance.primaryFocus;
    if (node == null || node != _focusedNode) return;
    final index = _focusedIndex!;
    if (!_scrollController.hasClients) return;
    final oldStart = (index ~/ previous.$3) * (previous.$4 + previous.$5);
    final oldOffset = _scrollController.offset;
    if (oldStart + previous.$4 <= oldOffset ||
        oldStart >= oldOffset + previous.$2) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          _focusLayout != next ||
          FocusManager.instance.primaryFocus != node) {
        return;
      }
      final target = (index ~/ columns) * (extent + spacing);
      _scrollController.jumpTo(
        target.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final focusContext = node.context;
        if (mounted &&
            focusContext != null &&
            FocusManager.instance.primaryFocus == node) {
          unawaited(Scrollable.ensureVisible(focusContext));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.collection,
      builder: (context, _) {
        final collection = widget.collection;
        if (collection.isLoading && collection.items.isEmpty) {
          return const LoadingView();
        }
        if (collection.failure case final failure?
            when collection.items.isEmpty) {
          return ErrorView(
            message: catalogFailureMessage(failure),
            onRetry: widget.onRetry ?? () => unawaited(collection.retry()),
          );
        }
        if (collection.items.isEmpty) {
          return EmptyView(
            message: widget.emptyMessage,
            icon: widget.emptyIcon,
          );
        }
        final items = collection.items;
        return LayoutBuilder(
          builder: (context, constraints) {
            _viewportWidth = constraints.maxWidth;
            _preserveFocusOnLayoutChange(constraints);
            return NotificationListener<ScrollUpdateNotification>(
              onNotification: (notification) {
                if (notification.metrics.extentAfter <=
                    _prefetchExtentForWidth(_viewportWidth)) {
                  _checkScrollThreshold();
                }
                return false;
              },
              child: GridView.builder(
                controller: _scrollController,
                gridDelegate: widget.gridDelegate,
                itemCount: items.length + (collection.hasMore ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index >= items.length) {
                    if (collection.failure case final failure?) {
                      return ErrorView(
                        message: catalogFailureMessage(failure),
                        onRetry:
                            widget.onRetry ??
                            () => unawaited(collection.retry()),
                      );
                    }
                    return const LoadingView();
                  }
                  final child = widget.itemBuilder(
                    context,
                    items[index],
                    index == 0 && _autofocusFirstItem,
                  );
                  if (!widget.preserveFocusedItemOnLayoutChange) return child;
                  return Focus(
                    canRequestFocus: false,
                    onFocusChange: (focused) {
                      if (focused) {
                        _focusedIndex = index;
                        _focusedNode = FocusManager.instance.primaryFocus;
                      } else if (_focusedIndex == index) {
                        _focusedIndex = null;
                        _focusedNode = null;
                      }
                    },
                    child: child,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
