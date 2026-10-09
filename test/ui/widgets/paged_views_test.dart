import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/ui/widgets/paged_grid_view.dart';
import 'package:iptv_flutter/ui/widgets/paged_list_view.dart';

void main() {
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
        if (attempts == 1) throw StateError('temporary failure');
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
