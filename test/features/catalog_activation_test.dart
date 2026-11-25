import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';

import '../support/app_harness.dart';

const _movie = ContentItem(id: 'movie', title: 'Fixture Movie', type: ContentType.vod,
  streamUrl: 'https://fixture.test/movie.mp4', group: 'Movies');

void main() {
  testWidgets('remote repeated OK opens one Details; Back prevents late activation', (tester) async {
    final queries = _Queries();
    final harness = await pumpIptvApp(tester, catalogQueryService: queries, size: const Size(1440, 900));
    final app = harness.controllers.app;
    app.openMovies();
    await tester.pumpAndSettle();
    final tile = find.byType(MediaTile).first;
    Focus.of(tester.element(find.text(_movie.title).first)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(queries.requests, hasLength(1));
    queries.requests.single.complete(_movie);
    await tester.pumpAndSettle();
    expect(app.navigationController.stack.whereType<DetailsRoute>(), hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(tile);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    queries.requests.last.complete(_movie);
    await tester.pumpAndSettle();
    expect(app.navigationController.currentRoute, isA<HomeRoute>());
    expect(tester.takeException(), isNull);
  });
  for (final missing in [true, false]) {
    testWidgets('activation ${missing ? 'missing' : 'error'} is visible without stealing focus', (tester) async {
      final queries = _Queries();
      final harness = await pumpIptvApp(tester, catalogQueryService: queries, size: const Size(1440, 900));
      final app = harness.controllers.app;
      app.openMovies();
      await tester.pumpAndSettle();
      final focus = Focus.of(tester.element(find.text(_movie.title).first));
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      if (missing) {
        queries.requests.single.complete(null);
      } else {
        queries.requests.single.completeError(StateError('Fixture lookup failure'));
      }
      await tester.pumpAndSettle();
      expect(find.text(missing ? 'This item is no longer available. Refresh the playlist.' :
        'Could not open this item. Please try again.'), findsOneWidget);
      expect(focus.hasFocus, isTrue);
      expect(app.navigationController.currentRoute, isA<CatalogRoute>());
      expect(tester.takeException(), isNull);
    });
  }
}

class _Queries extends InMemoryCatalogQueryService {
  _Queries() : super('test-fixture-playlist', [_movie]);
  final requests = <Completer<ContentItem?>>[];
  @override
  Future<ContentItem?> itemById(String itemId) {
    final request = Completer<ContentItem?>();
    requests.add(request);
    return request.future;
  }
}
