import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';

import '../support/catalog_fixtures.dart';

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
