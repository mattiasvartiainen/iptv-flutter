import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/ui/widgets/paged_grid_view.dart';
import 'package:iptv_flutter/ui/widgets/paged_list_view.dart';

void main() {
  test('failed page two retains page one and can be retried', () async {
    final logger = _RecordingLogger();
    final collection = PagedCollection<int>(pageSize: 2, logger: logger);
    addTearDown(collection.dispose);
    var secondPageAttempts = 0;
    await collection.load((offset, limit) async {
      if (offset == 2 && secondPageAttempts++ == 0) {
        throw StateError(
          'Request failed: https://provider.test/live/private-user/private-pass/list.m3u',
        );
      }
      return _page(offset, limit, 4);
    });

    await collection.loadMore();

    expect(collection.items, [0, 1]);
    expect(collection.total, 4);
    expect(collection.hasMore, isTrue);
    expect(collection.isLoadingMore, isFalse);
    expect(collection.failure, CatalogFailure.pageLoadFailed);
    expect(logger.errors.single, contains('%5Bredacted%5D'));
    expect(logger.errors.single, isNot(contains('private-user')));
    expect(logger.errors.single, isNot(contains('private-pass')));

    await collection.retry();
    expect(collection.items, [0, 1, 2, 3]);
    expect(collection.failure, isNull);
  });

  test('clear drops the result of an in-flight fetch', () async {
    final collection = PagedCollection<int>(pageSize: 2);
    addTearDown(collection.dispose);
    final response = Completer<CatalogPage<int>>();
    final loading = collection.load((_, _) => response.future);

    expect(collection.isLoading, isTrue);
    collection.clear();
    response.complete(const CatalogPage<int>(items: [1, 2], offset: 0, total: 2));
    await loading;

    expect(collection.items, isEmpty);
    expect(collection.total, 0);
    expect(collection.isLoading, isFalse);
    expect(collection.isLoadingMore, isFalse);
    expect(collection.failure, isNull);
  });

  group('PagedListView', () {
    testWidgets('loads another page when the first page underfills the view', (
      tester,
    ) async {
      final collection = PagedCollection<int>(pageSize: 2);
      final offsets = <int>[];
      await collection.load((offset, limit) async {
        offsets.add(offset);
        return _page(offset, limit, 4);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: PagedListView<int>(
              collection: collection,
              emptyMessage: 'No results',
              prefetchExtent: 1,
              itemBuilder: (context, item, index) =>
                  SizedBox(height: 40, child: Text('Item $item')),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(offsets, [0, 2]);
      await tester.pumpWidget(const SizedBox.shrink());
      collection.dispose();
    });

    testWidgets('retries a failed initial page from the empty error state', (
      tester,
    ) async {
      final collection = PagedCollection<int>(pageSize: 2);
      var attempts = 0;
      await collection.load((offset, limit) async {
        attempts++;
        if (attempts == 1) {
          throw StateError(
            'Failed URL: https://provider.test/live/private-user/private-pass/list.m3u',
          );
        }
        return _page(offset, limit, 2);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: PagedListView<int>(
              collection: collection,
              emptyMessage: 'No results',
              itemBuilder: (context, item, index) => Text('Item $item'),
            ),
          ),
        ),
      );
      expect(
        find.text('Could not load results. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('private-user'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(attempts, 2);
      expect(find.text('Item 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      collection.dispose();
    });

    testWidgets('requests one next page when scrolled to the end', (
      tester,
    ) async {
      final collection = PagedCollection<int>(pageSize: 40);
      final offsets = <int>[];
      await collection.load((offset, limit) async {
        offsets.add(offset);
        return _page(offset, limit, 80);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: PagedListView<int>(
              collection: collection,
              emptyMessage: 'No results',
              prefetchExtent: 1,
              itemBuilder: (context, item, index) =>
                  SizedBox(height: 40, child: Text('Item $item')),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(offsets, [0]);

      await tester.drag(find.byType(ListView), const Offset(0, -10000));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(offsets, [0, 40]);
      await tester.pumpWidget(const SizedBox.shrink());
      collection.dispose();
    });
  });

  group('PagedGridView', () {
    testWidgets('loads another page when the first page underfills the view', (
      tester,
    ) async {
      final collection = PagedCollection<int>(pageSize: 2);
      final offsets = <int>[];
      await collection.load((offset, limit) async {
        offsets.add(offset);
        return _page(offset, limit, 4);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: PagedGridView<int>(
              collection: collection,
              emptyMessage: 'No results',
              prefetchThreshold: 1,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 40,
              ),
              itemBuilder: (context, item, autofocus) => Text('Item $item'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(offsets, [0, 2]);
      await tester.pumpWidget(const SizedBox.shrink());
      collection.dispose();
    });

    testWidgets('requests one next page when scrolled to the end', (
      tester,
    ) async {
      final collection = PagedCollection<int>(pageSize: 40);
      final offsets = <int>[];
      await collection.load((offset, limit) async {
        offsets.add(offset);
        return _page(offset, limit, 80);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 400,
            height: 300,
            child: PagedGridView<int>(
              collection: collection,
              emptyMessage: 'No results',
              prefetchThreshold: 1,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisExtent: 40,
              ),
              itemBuilder: (context, item, autofocus) => Text('Item $item'),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(offsets, [0]);

      await tester.drag(find.byType(GridView), const Offset(0, -10000));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(offsets, [0, 40]);
      await tester.pumpWidget(const SizedBox.shrink());
      collection.dispose();
    });
  });
}

CatalogPage<int> _page(int offset, int limit, int total) => CatalogPage<int>(
  items: [
    for (var item = offset; item < offset + limit && item < total; item++) item,
  ],
  offset: offset,
  total: total,
);

class _RecordingLogger implements AppLogger {
  final List<String> errors = [];

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {
    errors.add(error?.toString() ?? '');
  }

  @override
  void info(String message, {Map<String, Object?> context = const {}}) {}

  @override
  void warning(String message, {Map<String, Object?> context = const {}}) {}
}
