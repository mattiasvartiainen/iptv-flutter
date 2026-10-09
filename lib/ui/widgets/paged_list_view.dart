import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/catalog_view_state.dart';
import 'state_views.dart';

class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.collection,
    required this.emptyMessage,
    required this.itemBuilder,
    this.prefetchExtent = 480,
    this.onRetry,
    this.emptyIcon,
    this.padding,
  }) : assert(prefetchExtent > 0);

  final PagedCollection<T> collection;
  final String emptyMessage;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final double prefetchExtent;
  final VoidCallback? onRetry;
  final IconData? emptyIcon;
  final EdgeInsetsGeometry? padding;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final ScrollController _scrollController = ScrollController();
  bool _loadScheduled = false;
  bool _initialCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_checkScrollThreshold);
    widget.collection.addListener(_collectionChanged);
    _scheduleInitialCheck();
  }

  @override
  void didUpdateWidget(covariant PagedListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection == widget.collection) return;
    oldWidget.collection.removeListener(_collectionChanged);
    widget.collection.addListener(_collectionChanged);
    _loadScheduled = false;
    _scheduleInitialCheck();
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
    if (!widget.collection.isLoadingMore) _loadScheduled = false;
    _scheduleInitialCheck();
  }

  void _scheduleInitialCheck() {
    if (!mounted || _initialCheckScheduled) return;
    _initialCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initialCheckScheduled = false;
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
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter > widget.prefetchExtent) {
      return;
    }
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
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
        return EmptyView(message: widget.emptyMessage, icon: widget.emptyIcon);
      }
      final items = collection.items;
      return NotificationListener<ScrollUpdateNotification>(
        onNotification: (notification) {
          if (notification.metrics.extentAfter <= widget.prefetchExtent) {
            _checkScrollThreshold();
          }
          return false;
        },
        child: ListView.builder(
          controller: _scrollController,
          padding: widget.padding,
          itemCount: items.length + (collection.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              if (collection.errorMessage case final error?) {
                return ErrorView(
                  message: error,
                  onRetry:
                      widget.onRetry ?? () => unawaited(collection.retry()),
                );
              }
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return widget.itemBuilder(context, items[index], index);
          },
        ),
      );
    },
  );
}
