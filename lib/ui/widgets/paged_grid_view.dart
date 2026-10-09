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
  }) : assert(prefetchThreshold > 0);

  final PagedCollection<T> collection;
  final String emptyMessage;
  final SliverGridDelegate gridDelegate;
  final Widget Function(BuildContext context, T item, bool autofocus)
  itemBuilder;
  final int prefetchThreshold;
  final VoidCallback? onRetry;
  final IconData? emptyIcon;

  @override
  State<PagedGridView<T>> createState() => _PagedGridViewState<T>();
}

class _PagedGridViewState<T> extends State<PagedGridView<T>> {
  final ScrollController _scrollController = ScrollController();
  bool _firstLayoutCheckScheduled = false;
  bool _loadScheduled = false;
  double _viewportWidth = 0;

  @override
  void initState() {
    super.initState();
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
        collection.errorMessage != null ||
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.collection,
      builder: (context, _) {
        final collection = widget.collection;
        if (collection.isLoading && collection.items.isEmpty) {
          return const LoadingView();
        }
        if (collection.errorMessage case final error?
            when collection.items.isEmpty) {
          return ErrorView(
            message: error,
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
                    if (collection.errorMessage case final error?) {
                      return ErrorView(
                        message: error,
                        onRetry:
                            widget.onRetry ??
                            () => unawaited(collection.retry()),
                      );
                    }
                    return const LoadingView();
                  }
                  return widget.itemBuilder(context, items[index], index == 0);
                },
              ),
            );
          },
        );
      },
    );
  }
}
