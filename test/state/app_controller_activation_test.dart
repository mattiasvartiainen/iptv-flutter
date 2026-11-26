import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';

const movie = ContentItem(
  id: 'movie',
  title: 'Movie',
  type: ContentType.vod,
  streamUrl: 'https://fixture.test/movie.mp4',
  group: 'Movies',
);
const episode = ContentItem(
  id: 'episode',
  title: 'Show S01E01',
  type: ContentType.vod,
  streamUrl: 'https://fixture.test/series/episode.mkv',
  group: 'Series',
);
const live = ContentItem(
  id: 'live',
  title: 'Live channel',
  type: ContentType.live,
  streamUrl: 'https://fixture.test/channel.m3u8',
  group: 'Live',
);

void main() {
  late CatalogViewState catalog;
  late NavigationController navigation;
  late AppController app;
  late _Queries queries;
  setUp(() async {
    catalog = CatalogViewState();
    navigation = NavigationController();
    app = AppController(catalogView: catalog, navigationController: navigation);
    queries = _Queries();
    await catalog.bind(service: queries, playlistId: 'p');
    app.openMovies();
  });
  tearDown(() {
    catalog.dispose();
    navigation.dispose();
  });

  test('repeated OK shares a lookup and pushes exactly one Details', () async {
    final first = app.openDetailsById(movie.id);
    final second = app.openDetailsById(movie.id);
    expect(second, same(first));
    expect(queries.requests, hasLength(1));
    queries.requests.single.complete(movie);
    await Future.wait([first, second]);
    expect(navigation.stack.whereType<DetailsRoute>(), hasLength(1));
  });
  test(
    'Live activation plays once without an intermediate Details route',
    () async {
      app.openLiveTv();
      final played = <ContentItem>[];
      Future<void> play(ContentItem item) async {
        played.add(item);
        navigation.push(PlayerRoute(item));
      }

      final first = app.activateItemById(live.id, playLive: play);
      final second = app.activateItemById(live.id, playLive: play);
      expect(second, same(first));
      queries.requests.single.complete(live);
      await Future.wait([first, second]);
      expect(played, [live]);
      expect(navigation.currentRoute, isA<PlayerRoute>());
      expect(navigation.stack.whereType<DetailsRoute>(), isEmpty);
      await app.activateItemById(live.id, playLive: play);
      expect(queries.requests, hasLength(1));
      expect(played, [live]);
      app.goBack();
      expect(navigation.currentRoute, isA<CatalogRoute>());
    },
  );

  for (final item in [movie, episode]) {
    test('activation keeps Details for ${item.id}', () async {
      final activation = app.activateItemById(
        item.id,
        playLive: (_) async => fail('VOD must not play directly'),
      );
      queries.requests.single.complete(item);
      await activation;
      expect((navigation.currentRoute as DetailsRoute).item, item);
    });
  }

  for (final invalidate in ['Back', 'new selection', 'playlist rebind']) {
    test('pending Live activation cannot play after $invalidate', () async {
      app.openLiveTv();
      var plays = 0;
      final activation = app.activateItemById(
        live.id,
        playLive: (_) async {
          plays++;
        },
      );
      if (invalidate == 'Back') {
        app.goBack();
      } else if (invalidate == 'new selection') {
        final replacement = app.activateItemById(
          movie.id,
          playLive: (_) async {
            fail('Movie must not play directly');
          },
        );
        queries.requests.last.complete(movie);
        await replacement;
      } else {
        await catalog.bind(service: queries, playlistId: 'q');
      }
      queries.requests.first.complete(live);
      await activation;
      expect(plays, 0);
      expect(navigation.stack.whereType<PlayerRoute>(), isEmpty);
    });
  }
  test(
    'Back invalidates lookup even if originating route is restored',
    () async {
      final route = navigation.currentRoute;
      final pending = app.openDetailsById(episode.id);
      app.goBack();
      navigation.push(route);
      queries.requests.single.complete(episode);
      await pending;
      expect(navigation.currentRoute, same(route));
    },
  );
  test('newer selection wins regardless of completion order', () async {
    final first = app.openDetailsById(movie.id);
    final second = app.openDetailsById(episode.id);
    queries.requests[1].complete(episode);
    await second;
    queries.requests[0].complete(movie);
    await first;
    expect(navigation.stack.whereType<DetailsRoute>(), hasLength(1));
    expect((navigation.currentRoute as DetailsRoute).item, episode);
  });
  test('playlist switch and switch-back invalidate the old lookup', () async {
    final pending = app.openDetailsById(movie.id);
    await catalog.bind(service: queries, playlistId: 'q');
    await catalog.bind(service: queries, playlistId: 'p');
    queries.requests.single.complete(movie);
    await pending;
    expect(navigation.currentRoute, isA<CatalogRoute>());
  });
  test(
    'missing and failed lookups report safe failures and allow retry',
    () async {
      final missing = app.openDetailsById(movie.id);
      queries.requests.last.complete(null);
      await missing;
      expect(catalog.activationFailure.value, ItemActivationFailure.notFound);
      final failed = app.openDetailsById(movie.id);
      queries.requests.last.completeError(StateError('Fixture lookup failed'));
      await failed;
      expect(
        catalog.activationFailure.value,
        ItemActivationFailure.lookupFailed,
      );
      final retry = app.openDetailsById(movie.id);
      expect(catalog.activationFailure.value, isNull);
      queries.requests.last.complete(movie);
      await retry;
      expect(navigation.currentRoute, isA<DetailsRoute>());
    },
  );
  test(
    'errors after navigation are discarded instead of surfacing on another screen',
    () async {
      final pending = app.openDetailsById(movie.id);
      app.openSearch();
      queries.requests.last.completeError(StateError('Fixture lookup failed'));
      await pending;
      expect(navigation.currentRoute, isA<SearchRoute>());
      expect(catalog.activationFailure.value, isNull);
    },
  );
  test('late lookup cannot publish after catalog disposal', () async {
    final state = CatalogViewState();
    final nav = NavigationController();
    final controller = AppController(
      catalogView: state,
      navigationController: nav,
    );
    final source = _Queries();
    await state.bind(service: source, playlistId: 'p');
    controller.openMovies();
    final pending = controller.openDetailsById(movie.id);
    state.dispose();
    source.requests.single.complete(movie);
    await pending;
    expect(nav.currentRoute, isA<CatalogRoute>());
    nav.dispose();
  });
  test(
    'repeated activation after lookup completion does not duplicate Details',
    () async {
      final first = app.openDetailsById(movie.id);
      queries.requests.single.complete(movie);
      await first;
      await app.openDetailsById(movie.id);
      expect(queries.requests, hasLength(1));
      expect(navigation.stack.whereType<DetailsRoute>(), hasLength(1));
    },
  );
}

class _Queries extends InMemoryCatalogQueryService {
  _Queries() : super('p', [movie, episode, live]);
  final requests = <Completer<ContentItem?>>[];
  @override
  Future<ContentItem?> itemById(String itemId) {
    final request = Completer<ContentItem?>();
    requests.add(request);
    return request.future;
  }
}
