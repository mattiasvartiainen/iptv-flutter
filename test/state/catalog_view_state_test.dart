import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';

import '../support/catalog_fixtures.dart';

void main() {
  late CatalogViewState view;

  setUp(() {
    view = CatalogViewState();
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

GroupSummary _group(int id, CatalogGroupKind kind, String title) =>
    GroupSummary(
      id: id,
      kind: kind,
      title: title,
      sortTitle: title.toLowerCase(),
      itemCount: 1,
      ordinal: 0,
    );
