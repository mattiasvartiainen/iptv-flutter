import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/catalog/m3u_parser.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';
import 'package:iptv_flutter/services/settings/app_preferences.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';

import '../support/catalog_fixtures.dart';
import '../support/in_memory_settings_repository.dart';

void main() {
  late CatalogViewState view;
  late _RecordingLogger logger;

  setUp(() {
    logger = _RecordingLogger();
    view = CatalogViewState(logger: logger);
  });

  tearDown(() {
    view.dispose();
  });

  test('switching browse kind resets selected group to All', () async {
    const playlistId = 'browse-kind-reset';
    final service = InMemoryCatalogQueryService(playlistId, fixtureCatalog);
    await view.bind(service: service, playlistId: playlistId);

    await view.showItems(CatalogItemKind.live);
    final selectedLiveGroup = view.browseGroups.first.id;
    await view.selectBrowseGroup(selectedLiveGroup);
    expect(view.selectedGroupId, selectedLiveGroup);

    await view.showItems(CatalogItemKind.movie);

    expect(view.browseGroupKind, CatalogGroupKind.movie);
    expect(view.selectedGroupId, isNull);
  });

  test(
    'Live TV uses source order in All and groups, and remembers A-Z',
    () async {
      final settings = InMemorySettingsRepository();
      view.dispose();
      view = CatalogViewState(
        preferences: AppPreferences(settingsRepository: settings),
      );
      final service = InMemoryCatalogQueryService(
        'p1',
        const M3uParser().parse(swedishPlaylistText(swedishChannelNames)),
      );
      await view.bind(service: service, playlistId: 'p1');
      await view.showItems(CatalogItemKind.live);
      expect(view.items.items.map((item) => item.title), swedishChannelNames);
      final group = view.browseGroups.single.id;
      await view.selectBrowseGroup(group);
      expect(view.items.items.map((item) => item.title), swedishChannelNames);

      await view.setLiveTvSort(CatalogSort.title);
      final alphabetical = [...swedishChannelNames]..sort();
      expect(view.items.items.map((item) => item.title), alphabetical);
      expect(view.selectedGroupId, group);
      await view.selectBrowseGroup(null);
      expect(view.items.items.map((item) => item.title), alphabetical);

      final restarted = CatalogViewState(
        preferences: AppPreferences(settingsRepository: settings),
      );
      addTearDown(restarted.dispose);
      await restarted.bind(service: service, playlistId: 'p1');
      await restarted.showItems(CatalogItemKind.live);
      expect(restarted.liveTvSort, CatalogSort.title);
      expect(restarted.items.items.map((item) => item.title), alphabetical);

      await view.bind(
        service: InMemoryCatalogQueryService('p2', fixtureCatalog),
        playlistId: 'p2',
      );
      expect(view.liveTvSort, CatalogSort.playlistOrder);
      await view.showItems(CatalogItemKind.movie);
      expect(view.items.items.map((item) => item.title), [
        'Northbound',
        'The Last Signal',
      ]);
      await view.bind(service: service, playlistId: 'p1');
      expect(view.liveTvSort, CatalogSort.title);
    },
  );

  for (final kind in [CatalogGroupKind.movie, CatalogGroupKind.series]) {
    test(
      '$kind sorts All and groups and restores its independent preference',
      () async {
        final settings = InMemorySettingsRepository();
        view.dispose();
        view = CatalogViewState(
          preferences: AppPreferences(settingsRepository: settings),
        );
        final catalog = const M3uParser().parse(movieSeriesPlaylistText);
        final service = InMemoryCatalogQueryService('p1', catalog);
        Future<void> show() => kind == CatalogGroupKind.series
            ? view.showSeries()
            : view.showItems(CatalogItemKind.movie);
        Iterable<String> titles(CatalogViewState value) =>
            kind == CatalogGroupKind.series
            ? value.series.items.map((item) => item.title)
            : value.items.items.map((item) => item.title);
        final suffix = kind == CatalogGroupKind.series ? 'Show' : 'Movie';
        final alphabetical = [
          'Alpha $suffix',
          'Middle $suffix',
          'Zebra $suffix',
        ];
        final original = ['Zebra $suffix', 'Alpha $suffix', 'Middle $suffix'];
        await view.bind(service: service, playlistId: 'p1');
        await show();
        expect(titles(view), alphabetical);
        await view.setCatalogSort(kind, CatalogSort.playlistOrder);
        expect(titles(view), original);
        await view.selectBrowseGroup(view.browseGroups.single.id);
        expect(titles(view), original);
        await view.setCatalogSort(kind, CatalogSort.title);
        expect(titles(view), alphabetical);
        await view.setCatalogSort(kind, CatalogSort.playlistOrder);
        await view.selectBrowseGroup(null);
        expect(titles(view), original);
        final other = kind == CatalogGroupKind.series
            ? CatalogGroupKind.movie
            : CatalogGroupKind.series;
        expect(view.sortFor(other), CatalogSort.title);

        final restarted = CatalogViewState(
          preferences: AppPreferences(settingsRepository: settings),
        );
        addTearDown(restarted.dispose);
        await restarted.bind(service: service, playlistId: 'p1');
        if (kind == CatalogGroupKind.series) {
          await restarted.showSeries();
        } else {
          await restarted.showItems(CatalogItemKind.movie);
        }
        expect(titles(restarted), original);
        await view.bind(
          service: InMemoryCatalogQueryService('p2', catalog),
          playlistId: 'p2',
        );
        expect(view.sortFor(kind), CatalogSort.title);
        await view.bind(service: service, playlistId: 'p1');
        expect(view.sortFor(kind), CatalogSort.playlistOrder);
      },
    );
  }

  test('a late Series save cannot reload the Movies page', () async {
    final settings = _GatedSortSettings();
    view.dispose();
    view = CatalogViewState(
      preferences: AppPreferences(settingsRepository: settings),
    );
    await view.bind(
      service: InMemoryCatalogQueryService(
        'p1',
        const M3uParser().parse(movieSeriesPlaylistText),
      ),
      playlistId: 'p1',
    );
    await view.showSeries();
    final pending = view.setCatalogSort(
      CatalogGroupKind.series,
      CatalogSort.playlistOrder,
    );
    await settings.saveRequested.future;
    await view.showItems(CatalogItemKind.movie);
    final ids = view.items.items.map((item) => item.id).toList();
    settings.saveResponse.complete();
    await pending;
    expect(view.browseGroupKind, CatalogGroupKind.movie);
    expect(view.items.items.map((item) => item.id), ids);
    expect(view.sortFor(CatalogGroupKind.series), CatalogSort.playlistOrder);
    expect(view.sortFor(CatalogGroupKind.movie), CatalogSort.title);
  });

  test('a late Series page cannot append after its sort changes', () async {
    final text =
        '#EXTM3U\n${List.generate(220, (index) => '#EXTINF:-1 group-title="Series",Show ${220 - index} S01 E01\n'
            'https://example.invalid/series/$index.mkv\n').join()}';
    final service = _GatedSeriesPageService(
      'p1',
      const M3uParser().parse(text),
    );
    await view.bind(service: service, playlistId: 'p1');
    await view.showSeries();
    final pending = view.series.loadMore();
    await service.pageRequested.future;
    await view.setCatalogSort(
      CatalogGroupKind.series,
      CatalogSort.playlistOrder,
    );
    final expected = List.generate(220, (index) => 'Show ${220 - index}');
    expect(
      view.series.items.map((item) => item.title),
      expected.take(view.series.pageSize),
    );
    service.pageResponse.complete(service.oldPage);
    await pending;
    expect(
      view.series.items.map((item) => item.title),
      expected.take(view.series.pageSize),
    );
    while (view.series.hasMore) {
      await view.series.loadMore();
    }
    expect(view.series.items.map((item) => item.title), expected);
    expect(view.series.items.map((item) => item.id).toSet(), hasLength(220));
  });

  test('a sort change rejects an in-flight page from the old order', () async {
    final names = List.generate(220, (index) => 'Channel ${220 - index}');
    final service = _GatedPageService(
      'p1',
      const M3uParser().parse(swedishPlaylistText(names)),
    );
    await view.bind(service: service, playlistId: 'p1');
    await view.showItems(CatalogItemKind.live);
    final pageSize = view.items.pageSize;
    expect(view.items.items, hasLength(pageSize));
    final pending = view.items.loadMore();
    await service.pageRequested.future;
    await view.setLiveTvSort(CatalogSort.title);
    final alphabetical = [...names]..sort();
    expect(
      view.items.items.map((item) => item.title),
      alphabetical.take(pageSize),
    );
    service.pageResponse.complete(service.oldPage);
    await pending;
    expect(
      view.items.items.map((item) => item.title),
      alphabetical.take(pageSize),
    );
    while (view.items.hasMore) {
      await view.items.loadMore();
    }
    expect(view.items.items.map((item) => item.title), alphabetical);
    expect(view.items.items.map((item) => item.id).toSet(), hasLength(220));
  });

  test('a failed sort save is logged, visible, and retryable', () async {
    final settings = _FailOnceSortSettings();
    view.dispose();
    view = CatalogViewState(
      preferences: AppPreferences(settingsRepository: settings),
      logger: logger,
    );
    await view.bind(
      service: InMemoryCatalogQueryService('p1', fixtureCatalog),
      playlistId: 'p1',
    );
    await view.showItems(CatalogItemKind.live);
    await view.setLiveTvSort(CatalogSort.title);
    expect(view.liveTvSort, CatalogSort.playlistOrder);
    expect(view.sortFailure, CatalogFailure.sortSaveFailed);
    expect(logger.errors, hasLength(1));
    await view.setLiveTvSort(CatalogSort.title);
    expect(view.liveTvSort, CatalogSort.title);
    expect(view.sortFailure, isNull);
  });

  test(
    'a late save cannot change another playlist or its loaded page',
    () async {
      final settings = _GatedSortSettings();
      view.dispose();
      view = CatalogViewState(
        preferences: AppPreferences(settingsRepository: settings),
      );
      await view.bind(
        service: InMemoryCatalogQueryService('p1', fixtureCatalog),
        playlistId: 'p1',
      );
      await view.showItems(CatalogItemKind.live);
      final pending = view.setLiveTvSort(CatalogSort.title);
      await settings.saveRequested.future;
      await view.bind(
        service: InMemoryCatalogQueryService('p2', fixtureCatalog),
        playlistId: 'p2',
      );
      await view.showItems(CatalogItemKind.live);
      final ids = view.items.items.map((item) => item.id).toList();
      settings.saveResponse.complete();
      await pending;
      expect(view.playlistId, 'p2');
      expect(view.liveTvSort, CatalogSort.playlistOrder);
      expect(view.items.items.map((item) => item.id), ids);
      expect(view.isSavingSort, isFalse);
      expect(settings.appSettings['live_tv_sort:p1'], 'title');
    },
  );

  test('group query failure is typed, logged safely, and retryable', () async {
    const playlistId = 'browse-group-failure';
    final service = _FailOnceGroupsService(playlistId, fixtureCatalog);
    await view.bind(service: service, playlistId: playlistId);

    await view.showItems(CatalogItemKind.live);

    expect(view.groupsFailure, CatalogFailure.groupsLoadFailed);
    expect(logger.errors, hasLength(1));
    expect(logger.errors.single, contains('%5Bredacted%5D'));
    expect(logger.errors.single, isNot(contains('private-user')));
    expect(logger.errors.single, isNot(contains('private-pass')));

    await view.retryBrowseGroups();

    expect(view.groupsFailure, isNull);
    expect(view.browseGroups, isNotEmpty);
    expect(logger.errors, hasLength(1));
  });

  test(
    'a late group response cannot replace a newer browse kind or page',
    () async {
      const playlistId = 'browse-generation';
      final service = _GatedGroupsService(playlistId, fixtureCatalog);
      await view.bind(service: service, playlistId: playlistId);

      final liveRequest = view.showItems(CatalogItemKind.live);
      final movieRequest = view.showItems(CatalogItemKind.movie);
      final movieGroup = _group(11, CatalogGroupKind.movie, 'Movies');
      service.completeGroups(CatalogGroupKind.movie, [movieGroup]);
      await movieRequest;

      service.completeGroups(CatalogGroupKind.live, [
        _group(12, CatalogGroupKind.live, 'Stale live group'),
      ]);
      await liveRequest;

      expect(view.browseGroupKind, CatalogGroupKind.movie);
      expect(view.browseGroups, [movieGroup]);
      expect(
        view.items.items.every((item) => item.kind == CatalogItemKind.movie),
        isTrue,
      );
    },
  );
}

class _GatedSeriesPageService extends InMemoryCatalogQueryService {
  _GatedSeriesPageService(super.playlistId, super.items);
  final pageRequested = Completer<void>();
  final pageResponse = Completer<CatalogPage<SeriesSummary>>();
  late CatalogPage<SeriesSummary> oldPage;

  @override
  Future<CatalogPage<SeriesSummary>> querySeries(
    String playlistId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
    int? groupId,
    CatalogSort sort = CatalogSort.title,
  }) async {
    final page = await super.querySeries(
      playlistId,
      offset: offset,
      limit: limit,
      searchTerm: searchTerm,
      groupId: groupId,
      sort: sort,
    );
    if (offset > 0 && sort == CatalogSort.title) {
      oldPage = page;
      pageRequested.complete();
      return pageResponse.future;
    }
    return page;
  }
}

class _GatedPageService extends InMemoryCatalogQueryService {
  _GatedPageService(super.playlistId, super.items);

  final pageRequested = Completer<void>();
  final pageResponse = Completer<CatalogPage<CatalogItemSummary>>();
  late CatalogPage<CatalogItemSummary> oldPage;

  @override
  Future<CatalogPage<CatalogItemSummary>> queryItems(CatalogQuery query) async {
    final page = await super.queryItems(query);
    if (query.offset > 0 && query.sort == CatalogSort.playlistOrder) {
      oldPage = page;
      pageRequested.complete();
      return pageResponse.future;
    }
    return page;
  }
}

class _FailOnceSortSettings extends InMemorySettingsRepository {
  bool fail = true;

  @override
  Future<void> setAppSetting(String key, String value) async {
    if (fail) {
      fail = false;
      throw StateError('Storage unavailable');
    }
    await super.setAppSetting(key, value);
  }
}

class _GatedSortSettings extends InMemorySettingsRepository {
  final saveRequested = Completer<void>();
  final saveResponse = Completer<void>();

  @override
  Future<void> setAppSetting(String key, String value) async {
    saveRequested.complete();
    await saveResponse.future;
    await super.setAppSetting(key, value);
  }
}

class _GatedGroupsService extends InMemoryCatalogQueryService {
  _GatedGroupsService(super.playlistId, super.items);

  final Map<CatalogGroupKind, Completer<List<GroupSummary>>> _groupResponses = {
    for (final kind in CatalogGroupKind.values)
      kind: Completer<List<GroupSummary>>(),
  };

  void completeGroups(CatalogGroupKind kind, List<GroupSummary> groups) {
    _groupResponses[kind]!.complete(groups);
  }

  @override
  Future<List<GroupSummary>> queryGroups(
    String playlistId, {
    required CatalogGroupKind kind,
    String profileId = 'default',
  }) => _groupResponses[kind]!.future;
}

class _FailOnceGroupsService extends InMemoryCatalogQueryService {
  _FailOnceGroupsService(super.playlistId, super.items);

  bool _shouldFail = true;

  @override
  Future<List<GroupSummary>> queryGroups(
    String playlistId, {
    required CatalogGroupKind kind,
    String profileId = 'default',
  }) {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError(
        'Failed URL: https://provider.test/live/private-user/private-pass/list.m3u',
      );
    }
    return super.queryGroups(playlistId, kind: kind, profileId: profileId);
  }
}

class _RecordingLogger implements AppLogger {
  final errors = <String>[];

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

GroupSummary _group(int id, CatalogGroupKind kind, String title) =>
    GroupSummary(
      id: id,
      kind: kind,
      title: title,
      sortTitle: title.toLowerCase(),
      itemCount: 1,
      ordinal: 0,
    );
