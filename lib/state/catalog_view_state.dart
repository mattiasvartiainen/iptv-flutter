import 'package:flutter/foundation.dart';

import '../models/content_item.dart';
import '../services/catalog/catalog_query.dart';
import '../services/catalog/catalog_query_service.dart';

typedef PageFetcher<T> = Future<CatalogPage<T>> Function(int offset, int limit);

/// Holds one visible page window of a query result.
///
/// Results are tagged with a generation so a slow page-N response can never be
/// appended after the query has been reset or replaced.
class PagedCollection<T> extends ChangeNotifier {
  PagedCollection({this.pageSize = kCatalogPageSize});

  final int pageSize;

  PageFetcher<T>? _fetcher;
  int _generation = 0;
  bool _disposed = false;

  List<T> _items = const [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _errorMessage;

  List<T> get items => _items;
  int get total => _total;
  bool get isLoading => _loading;
  bool get isLoadingMore => _loadingMore;
  String? get errorMessage => _errorMessage;
  bool get hasMore => _items.length < _total;

  Future<void> load(PageFetcher<T> fetcher) {
    _fetcher = fetcher;
    final generation = ++_generation;
    _items = const [];
    _total = 0;
    _errorMessage = null;
    _loading = true;
    _loadingMore = false;
    _notify();
    return _fetch(generation, offset: 0);
  }

  Future<void> loadMore() {
    if (_loading || _loadingMore || !hasMore || _fetcher == null) {
      return Future<void>.value();
    }
    _loadingMore = true;
    _notify();
    return _fetch(_generation, offset: _items.length, append: true);
  }

  void clear() {
    _generation++;
    _fetcher = null;
    _items = const [];
    _total = 0;
    _loading = false;
    _loadingMore = false;
    _errorMessage = null;
    _notify();
  }

  Future<void> _fetch(
    int generation, {
    required int offset,
    bool append = false,
  }) async {
    final fetcher = _fetcher;
    if (fetcher == null) return;
    try {
      final page = await fetcher(offset, pageSize);
      if (generation != _generation) return;
      _items = append
          ? List.unmodifiable([..._items, ...page.items])
          : page.items;
      _total = page.total;
    } catch (error) {
      if (generation != _generation) return;
      _errorMessage = '$error';
    }
    if (generation != _generation) return;
    _loading = false;
    _loadingMore = false;
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Query-driven replacement for the in-memory catalog that used to live on
/// [AppController]. Only the current page plus the home previews are resident.
class CatalogViewState extends ChangeNotifier {
  final PagedCollection<CatalogItemSummary> items = PagedCollection();
  final PagedCollection<SeriesSummary> series = PagedCollection();
  final PagedCollection<CatalogItemSummary> episodes = PagedCollection();

  CatalogQueryService? _service;
  String? _playlistId;
  bool _disposed = false;

  List<CatalogItemSummary> homeLive = const [];
  List<CatalogItemSummary> homeMovies = const [];
  List<SeriesSummary> homeSeries = const [];
  List<SeasonSummary> seasons = const [];
  List<GroupSummary> browseGroups = const [];
  CatalogGroupKind? browseGroupKind;
  int? selectedGroupId;
  bool isLoadingGroups = false;
  String? groupsErrorMessage;

  /// Total media rows for the bound playlist, used for empty-state decisions.
  int itemCount = 0;

  bool get hasContent => itemCount > 0;
  String? get playlistId => _playlistId;

  Future<void> bind({
    required CatalogQueryService service,
    required String playlistId,
  }) async {
    _service = service;
    _playlistId = playlistId;
    items.clear();
    series.clear();
    episodes.clear();
    seasons = const [];
    browseGroups = const [];
    browseGroupKind = null;
    selectedGroupId = null;
    await refreshHomeSections();
  }

  void unbind() {
    _service = null;
    _playlistId = null;
    items.clear();
    series.clear();
    episodes.clear();
    seasons = const [];
    browseGroups = const [];
    browseGroupKind = null;
    selectedGroupId = null;
    homeLive = const [];
    homeMovies = const [];
    homeSeries = const [];
    itemCount = 0;
    _notify();
  }

  Future<void> refreshHomeSections() async {
    final service = _service;
    final playlistId = _playlistId;
    if (service == null || playlistId == null) return;

    final results = await Future.wait([
      service.homePreview(playlistId, kind: CatalogItemKind.live),
      service.homePreview(playlistId, kind: CatalogItemKind.movie),
      service.querySeries(playlistId, limit: kHomePreviewCount),
      service.queryItems(CatalogQuery(playlistId: playlistId, limit: 1)),
    ]);

    if (_playlistId != playlistId) return;
    homeLive = results[0] as List<CatalogItemSummary>;
    homeMovies = results[1] as List<CatalogItemSummary>;
    homeSeries = (results[2] as CatalogPage<SeriesSummary>).items;
    itemCount = (results[3] as CatalogPage<CatalogItemSummary>).total;
    _notify();
  }

  Future<void> showItems(CatalogItemKind kind, {int? groupId}) async {
    final service = _service;
    final playlistId = _playlistId;
    if (service == null || playlistId == null) return Future<void>.value();

    final groupKind = switch (kind) {
      CatalogItemKind.live => CatalogGroupKind.live,
      CatalogItemKind.movie => CatalogGroupKind.movie,
      CatalogItemKind.episode => CatalogGroupKind.series,
      CatalogItemKind.unknown => CatalogGroupKind.live,
    };
    final kindChanged = browseGroupKind != groupKind;
    browseGroupKind = groupKind;
    selectedGroupId = kindChanged ? null : groupId;
    await _loadBrowseGroups(service, playlistId, groupKind);
    final selectedGroup = selectedGroupId;
    await items.load(
      (offset, limit) => selectedGroup == null
          ? service.queryItems(
              CatalogQuery(
                playlistId: playlistId,
                kinds: [kind],
                offset: offset,
                limit: limit,
              ),
            )
          : service.itemsInGroup(
              playlistId,
              selectedGroup,
              offset: offset,
              limit: limit,
            ),
    );
  }

  Future<void> showSeries({int? groupId}) async {
    final service = _service;
    final playlistId = _playlistId;
    if (service == null || playlistId == null) return Future<void>.value();

    const groupKind = CatalogGroupKind.series;
    final kindChanged = browseGroupKind != groupKind;
    browseGroupKind = groupKind;
    selectedGroupId = kindChanged ? null : groupId;
    await _loadBrowseGroups(service, playlistId, groupKind);
    final selectedGroup = selectedGroupId;
    await series.load(
      (offset, limit) => selectedGroup == null
          ? service.querySeries(playlistId, offset: offset, limit: limit)
          : service.seriesInGroup(
              playlistId,
              selectedGroup,
              offset: offset,
              limit: limit,
            ),
    );
  }

  Future<void> selectBrowseGroup(int? groupId) async {
    final kind = browseGroupKind;
    if (kind == null) return;
    selectedGroupId = groupId;
    _notify();
    switch (kind) {
      case CatalogGroupKind.live:
        await showItems(CatalogItemKind.live, groupId: groupId);
      case CatalogGroupKind.movie:
        await showItems(CatalogItemKind.movie, groupId: groupId);
      case CatalogGroupKind.series:
        await showSeries(groupId: groupId);
    }
  }

  Future<void> _loadBrowseGroups(
    CatalogQueryService service,
    String playlistId,
    CatalogGroupKind kind,
  ) async {
    isLoadingGroups = true;
    groupsErrorMessage = null;
    _notify();
    try {
      final loaded = await service.queryGroups(playlistId, kind: kind);
      if (_service != service ||
          _playlistId != playlistId ||
          browseGroupKind != kind) {
        return;
      }
      browseGroups = loaded;
      if (selectedGroupId != null &&
          !loaded.any((group) => group.id == selectedGroupId)) {
        selectedGroupId = null;
      }
    } catch (error) {
      if (_service != service || _playlistId != playlistId) return;
      groupsErrorMessage = '$error';
      browseGroups = const [];
      selectedGroupId = null;
    } finally {
      if (_service == service && _playlistId == playlistId) {
        isLoadingGroups = false;
        _notify();
      }
    }
  }

  Future<void> showSeasons(SeriesSummary value) async {
    final service = _service;
    if (service == null) return;
    seasons = const [];
    episodes.clear();
    _notify();
    final loaded = await service.seasons(value.id);
    if (_service != service) return;
    seasons = loaded;
    _notify();
  }

  Future<void> showEpisodes(SeasonSummary season) {
    final service = _service;
    if (service == null) return Future<void>.value();
    return episodes.load(
      (offset, limit) =>
          service.episodes(season.id, offset: offset, limit: limit),
    );
  }

  Future<ContentItem?> itemById(String itemId) async =>
      _service?.itemById(itemId);

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    items.dispose();
    series.dispose();
    episodes.dispose();
    super.dispose();
  }
}
