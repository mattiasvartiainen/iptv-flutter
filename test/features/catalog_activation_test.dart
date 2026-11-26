import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';

import '../support/app_harness.dart';
import '../support/controlled_playback.dart';

const _movie = ContentItem(
  id: 'movie',
  title: 'Fixture Movie',
  type: ContentType.vod,
  streamUrl: 'https://fixture.test/movie.mp4',
  group: 'Movies',
);
const _live = ContentItem(
  id: 'live',
  title: 'Fixture Channel',
  type: ContentType.live,
  streamUrl: 'https://fixture.test/channel.m3u8',
  group: 'Live',
);

void main() {
  for (final surface in ['Home', 'Live cards', 'Live list', 'Search']) {
    testWidgets('$surface starts Live immediately and restores focus on Back', (
      tester,
    ) async {
      final playback = ControlledPlayback();
      final harness = await pumpIptvApp(
        tester,
        catalogQueryService: InMemoryCatalogQueryService(
          'test-fixture-playlist',
          [_live, _movie],
        ),
        playbackAdapter: playback,
        size: const Size(1440, 900),
      );
      final app = harness.controllers.app;
      if (surface.startsWith('Live')) {
        await harness.controllers.preferences.setLiveUseListView(
          surface == 'Live list',
        );
        app.openLiveTv();
        await tester.pumpAndSettle();
      } else if (surface == 'Search') {
        app.openSearch();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Fixture Channel');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      }
      expect(
        playback.calls,
        isEmpty,
        reason: 'Entering a section does not autoplay',
      );
      final origin = app.navigationController.currentRoute;
      final title = surface == 'Search'
          ? find.descendant(
              of: find.widgetWithText(ListTile, _live.title),
              matching: find.text(_live.title),
            )
          : find.text(_live.title).first;
      final focus = Focus.of(tester.element(title));
      focus.requestFocus();
      await tester.pump();
      if (surface.startsWith('Live') || surface == 'Search') {
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      } else {
        await tester.tap(title);
      }
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<PlayerRoute>());
      expect(app.navigationController.stack.whereType<DetailsRoute>(), isEmpty);
      expect(playback.calls.where((call) => call.startsWith('load:')), [
        'load:live',
      ]);
      expect(playback.state.status, PlaybackStatus.playing);
      expect(playback.state.item, _live);
      expect(find.text(_live.streamUrl), findsNothing);
      // Player Back first dismisses controls, then leaves playback.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, same(origin));
      expect(playback.state.status, PlaybackStatus.stopped);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Back during Live lookup never starts playback', (tester) async {
    final queries = _Queries([_live]);
    final playback = ControlledPlayback();
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: queries,
      playbackAdapter: playback,
      size: const Size(1440, 900),
    );
    harness.controllers.app.openLiveTv();
    await tester.pumpAndSettle();
    await tester.tap(find.text(_live.title));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    queries.requests.single.complete(_live);
    await tester.pumpAndSettle();
    expect(
      harness.controllers.app.navigationController.currentRoute,
      isA<HomeRoute>(),
    );
    expect(playback.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Movies still require Play from Details', (tester) async {
    final playback = ControlledPlayback();
    final harness = await pumpIptvApp(
      tester,
      catalogQueryService: InMemoryCatalogQueryService(
        'test-fixture-playlist',
        [_movie],
      ),
      playbackAdapter: playback,
      size: const Size(1440, 900),
    );
    harness.controllers.app.openMovies();
    await tester.pumpAndSettle();
    await tester.tap(find.text(_movie.title));
    await tester.pumpAndSettle();
    expect(
      harness.controllers.app.navigationController.currentRoute,
      isA<DetailsRoute>(),
    );
    expect(playback.calls, isEmpty);
    await tester.tap(find.text('Play selected stream'));
    await tester.pumpAndSettle();
    expect(
      harness.controllers.app.navigationController.currentRoute,
      isA<PlayerRoute>(),
    );
    expect(playback.state.item, _movie);
    expect(playback.state.status, PlaybackStatus.playing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'remote repeated OK opens one Details; Back prevents late activation',
    (tester) async {
      final queries = _Queries();
      final harness = await pumpIptvApp(
        tester,
        catalogQueryService: queries,
        size: const Size(1440, 900),
      );
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
      expect(
        app.navigationController.stack.whereType<DetailsRoute>(),
        hasLength(1),
      );
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
    },
  );
  for (final missing in [true, false]) {
    testWidgets(
      'activation ${missing ? 'missing' : 'error'} is visible without stealing focus',
      (tester) async {
        final queries = _Queries();
        final harness = await pumpIptvApp(
          tester,
          catalogQueryService: queries,
          size: const Size(1440, 900),
        );
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
          queries.requests.single.completeError(
            StateError('Fixture lookup failure'),
          );
        }
        await tester.pumpAndSettle();
        expect(
          find.text(
            missing
                ? 'This item is no longer available. Refresh the playlist.'
                : 'Could not open this item. Please try again.',
          ),
          findsOneWidget,
        );
        expect(focus.hasFocus, isTrue);
        expect(app.navigationController.currentRoute, isA<CatalogRoute>());
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Queries extends InMemoryCatalogQueryService {
  _Queries([List<ContentItem> items = const [_movie]])
    : super('test-fixture-playlist', items);
  final requests = <Completer<ContentItem?>>[];
  @override
  Future<ContentItem?> itemById(String itemId) {
    final request = Completer<ContentItem?>();
    requests.add(request);
    return request.future;
  }
}
