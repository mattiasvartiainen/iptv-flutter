import 'package:flutter/foundation.dart';

import '../models/content_item.dart';
import '../services/catalog/catalog_query.dart';
import '../services/catalog/catalog_query_service.dart';
import '../services/logging/app_logger.dart';
import '../services/security/url_redaction.dart';
import '../services/settings/app_preferences.dart';

typedef PageFetcher<T> = Future<CatalogPage<T>> Function(int offset, int limit);

enum CatalogFailure { pageLoadFailed, groupsLoadFailed, sortSaveFailed }

/// Holds one visible page window of a query result.
///
/// Results are tagged with a generation so a slow page-N response can never be
/// appended after the query has been reset or replaced.
class PagedCollection<T> extends ChangeNotifier {
  PagedCollection({
    this.pageSize = kCatalogPageSize,
    AppLogger logger = const DebugAppLogger(),
  }) : _logger = logger;

  final int pageSize;
  final AppLogger _logger;

  PageFetcher<T>? _fetcher;
  int _generation = 0;
  bool _disposed = false;

  List<T> _items = const [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  CatalogFailure? _failure;

  List<T> get items => _items;
  int get total => _total;
  bool get isLoading => _loading;
  bool get isLoadingMore => _loadingMore;
  CatalogFailure? get failure => _failure;
  bool get hasMore => _items.length < _total;

  Future<void> load(PageFetcher<T> fetcher) {
    _fetcher = fetcher;
    final generation = ++_generation;
    _items = const [];
    _total = 0;
    _failure = null;
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
    _failure = null;
    _notify();
    return _fetch(_generation, offset: _items.length, append: true);
  }

  Future<void> retry() {
    final fetcher = _fetcher;
    if (fetcher == null || _loading || _loadingMore) {
      return Future<void>.value();
    }
    return _items.isEmpty ? load(fetcher) : loadMore();
  }

  void clear() {
    _generation++;
    _fetcher = null;
    _items = const [];
    _total = 0;
    _loading = false;
    _loadingMore = false;
    _failure = null;
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
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      _failure = CatalogFailure.pageLoadFailed;
      _logger.error(
        'catalog_page_load_failed',
        error: redactSensitiveText(error.toString()),
        stackTrace: StackTrace.fromString(
          redactSensitiveText(stackTrace.toString()),
        ),
        context: {'offset': offset, 'append': append},
      );
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
  CatalogViewState({
    AppLogger logger = const DebugAppLogger(),
    AppPreferences? preferences,
  }) : _logger = logger,
       _preferences = preferences,
       items = PagedCollection(logger: logger),
       series = PagedCollection(logger: logger),
       episodes = PagedCollection(logger: logger),
       searchResults = PagedCollection(logger: logger);

  final AppLogger _logger;
  final AppPreferences? _preferences;
  final PagedCollection<CatalogItemSummary> items;
  final PagedCollection<SeriesSummary> series;
  final PagedCollection<CatalogItemSummary> episodes;
  final PagedCollection<CatalogItemSummary> searchResults;

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
  CatalogFailure? groupsFailure;
  CatalogSearchIndexStatus? searchIndexStatus;
  String _searchTerm = '';
  CatalogItemKind? _searchKind;
  int _searchStatusGeneration = 0;
  int _browseGeneration = 0;
  int _bindingGeneration = 0;
  final Map<CatalogGroupKind, CatalogSort> _sorts = {};
  final Map<CatalogGroupKind, CatalogFailure> _sortFailures = {};
  bool isSavingSort = false;

  CatalogSort sortFor(CatalogGroupKind kind) =>
      _sorts[kind] ??
      (kind == CatalogGroupKind.live
          ? CatalogSort.playlistOrder
          : CatalogSort.title);
  CatalogSort get liveTvSort => sortFor(CatalogGroupKind.live);
  CatalogFailure? sortFailureFor(CatalogGroupKind kind) => _sortFailures[kind];
  CatalogFailure? get sortFailure =>
      browseGroupKind == null ? null : _sortFailures[browseGroupKind];

  /// Total media rows for the bound playlist, used for empty-state decisions.
  int itemCount = 0;

  bool get hasContent => itemCount > 0;
  String? get playlistId => _playlistId;

  Future<void> bind({
    required CatalogQueryService service,
    required String playlistId,
  }) async {
    final binding = ++_bindingGeneration;
    _browseGeneration++;
    _service = service;
    _playlistId = playlistId;
    items.clear();
    series.clear();
    episodes.clear();
    searchResults.clear();
    seasons = const [];
    browseGroups = const [];
    browseGroupKind = null;
    selectedGroupId = null;
    groupsFailure = null;
    searchIndexStatus = null;
    _searchTerm = '';
    _searchKind = null;
    _sorts.clear();
    isSavingSort = false;
    _sortFailures.clear();
    final preferences = _preferences;
    if (preferences != null) {
      final sorts = await Future.wait(
        CatalogGroupKind.values.map(
          (kind) => preferences.catalogSort(playlistId, kind),
        ),
      );
      if (binding != _bindingGeneration || _disposed) return;
      for (final kind in CatalogGroupKind.values) {
        _sorts[kind] = sorts[kind.index];
      }
    }
    await refreshHomeSections();
  }

  void unbind() {
    _bindingGeneration++;
    _browseGeneration++;
    _service = null;
    _playlistId = null;
    items.clear();
    series.clear();
    episodes.clear();
    searchResults.clear();
    seasons = const [];
    browseGroups = const [];
    browseGroupKind = null;
    selectedGroupId = null;
    groupsFailure = null;
    searchIndexStatus = null;
    _searchTerm = '';
    _searchKind = null;
    _sorts.clear();
    isSavingSort = false;
    _sortFailures.clear();
    homeLive = const [];
    homeMovies = const [];
    homeSeries = const [];
    itemCount = 0;
    _notify();
  }

  Future<void> search(String term, {CatalogItemKind? kind}) async {
    final service = _service;
    final playlistId = _playlistId;
    if (service == null || playlistId == null) return;

    _searchTerm = term.trim();
    _searchKind = kind;
    final normalizedTerm = _searchTerm;
    final selectedKind = _searchKind;
    if (normalizedTerm.isEmpty) {
      searchResults.clear();
    } else {
      await searchResults.load(
        (offset, limit) => service.queryItems(
          CatalogQuery(
            playlistId: playlistId,
            kinds: selectedKind == null ? const [] : [selectedKind],
            searchTerm: normalizedTerm,
            offset: offset,
            limit: limit,
          ),
        ),
      );
    }
    await refreshSearchIndexStatus();
  }

  Future<void> refreshSearchIndexStatus() async {
    final service = _service;
    final playlistId = _playlistId;
    if (service == null || playlistId == null) return;
    final generation = ++_searchStatusGeneration;
    final status = await service.searchIndexStatus(playlistId);
    if (_playlistId != playlistId || generation != _searchStatusGeneration) {
      return;
    }
    final previousPending = searchIndexStatus?.pendingItems;
    searchIndexStatus = status;
    _notify();
    if (previousPending != null &&
        previousPending > 0 &&
        status.pendingItems == 0 &&
        _searchTerm.isNotEmpty) {
      await _reloadSearchResults();
    }
  }

  Future<void> _reloadSearchResults() async {
    final service = _service;
    final playlistId = _playlistId;
    if (service == null || playlistId == null || _searchTerm.isEmpty) return;
    final term = _searchTerm;
    final kind = _searchKind;
    await searchResults.load(
      (offset, limit) => service.queryItems(
        CatalogQuery(
          playlistId: playlistId,
          kinds: kind == null ? const [] : [kind],
          searchTerm: term,
          offset: offset,
          limit: limit,
        ),
      ),
    );
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
    final generation = ++_browseGeneration;

    final groupKind = switch (kind) {
      CatalogItemKind.live => CatalogGroupKind.live,
      CatalogItemKind.movie => CatalogGroupKind.movie,
      CatalogItemKind.episode => CatalogGroupKind.series,
      CatalogItemKind.unknown => CatalogGroupKind.live,
    };
    final sort = sortFor(groupKind);
    final kindChanged = browseGroupKind != groupKind;
    browseGroupKind = groupKind;
    selectedGroupId = kindChanged ? null : groupId;
    await _loadBrowseGroups(
      service,
      playlistId,
      groupKind,
      generation: generation,
    );
    if (generation != _browseGeneration) return;
    final selectedGroup = selectedGroupId;
    await items.load(
      (offset, limit) => selectedGroup == null
          ? service.queryItems(
              CatalogQuery(
                playlistId: playlistId,
                kinds: [kind],
                offset: offset,
                limit: limit,
                sort: sort,
              ),
            )
          : service.itemsInGroup(
              playlistId,
              selectedGroup,
              offset: offset,
              limit: limit,
              sort: sort,
            ),
    );
  }

  Future<void> setLiveTvSort(CatalogSort sort) =>
      setCatalogSort(CatalogGroupKind.live, sort);

  Future<void> setCatalogSort(CatalogGroupKind kind, CatalogSort sort) async {
    final playlistId = _playlistId;
    if (playlistId == null || isSavingSort || sort == sortFor(kind)) {
      return;
    }
    final binding = _bindingGeneration;
    isSavingSort = true;
    _sortFailures.remove(kind);
    _notify();
    try {
      await _preferences?.setCatalogSort(playlistId, kind, sort);
      if (binding != _bindingGeneration || _disposed) return;
      _sorts[kind] = sort;
      if (browseGroupKind == kind) {
        if (kind == CatalogGroupKind.series) {
          series.clear();
        } else {
          items.clear();
        }
      }
      _notify();
      if (browseGroupKind == kind) {
        switch (kind) {
          case CatalogGroupKind.live:
            await showItems(CatalogItemKind.live, groupId: selectedGroupId);
          case CatalogGroupKind.movie:
            await showItems(CatalogItemKind.movie, groupId: selectedGroupId);
          case CatalogGroupKind.series:
            await showSeries(groupId: selectedGroupId);
        }
      }
    } catch (error, stackTrace) {
      if (binding != _bindingGeneration || _disposed) return;
      _sortFailures[kind] = CatalogFailure.sortSaveFailed;
      _logger.error(
        'catalog_sort_save_failed',
        error: redactSensitiveText(error.toString()),
        stackTrace: StackTrace.fromString(
          redactSensitiveText(stackTrace.toString()),
        ),
        context: {'kind': kind.name},
      );
    } finally {
      if (binding == _bindingGeneration && !_disposed) {
        isSavingSort = false;
        _notify();
      }
    }
  }

  Future<void> showSeries({int? groupId}) async {
    final service = _service;
    final playlistId = _playlistId;
    if (service == null || playlistId == null) return Future<void>.value();
    final generation = ++_browseGeneration;

    const groupKind = CatalogGroupKind.series;
    final sort = sortFor(groupKind);
    final kindChanged = browseGroupKind != groupKind;
    browseGroupKind = groupKind;
    selectedGroupId = kindChanged ? null : groupId;
    await _loadBrowseGroups(
      service,
      playlistId,
      groupKind,
      generation: generation,
    );
    if (generation != _browseGeneration) return;
    final selectedGroup = selectedGroupId;
    await series.load(
      (offset, limit) => selectedGroup == null
          ? service.querySeries(
              playlistId,
              offset: offset,
              limit: limit,
              sort: sort,
            )
          : service.seriesInGroup(
              playlistId,
              selectedGroup,
              offset: offset,
              limit: limit,
              sort: sort,
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
    CatalogGroupKind kind, {
    required int generation,
  }) async {
    isLoadingGroups = true;
    groupsFailure = null;
    _notify();
    try {
      final loaded = await service.queryGroups(playlistId, kind: kind);
      if (_service != service ||
          _playlistId != playlistId ||
          generation != _browseGeneration ||
          browseGroupKind != kind) {
        return;
      }
      browseGroups = loaded;
      if (selectedGroupId != null &&
          !loaded.any((group) => group.id == selectedGroupId)) {
        selectedGroupId = null;
      }
    } catch (error, stackTrace) {
      if (_service != service ||
          _playlistId != playlistId ||
          generation != _browseGeneration) {
        return;
      }
      groupsFailure = CatalogFailure.groupsLoadFailed;
      browseGroups = const [];
      selectedGroupId = null;
      _logger.error(
        'catalog_groups_load_failed',
        error: redactSensitiveText(error.toString()),
        stackTrace: StackTrace.fromString(
          redactSensitiveText(stackTrace.toString()),
        ),
        context: {'kind': kind.name},
      );
    } finally {
      if (_service == service &&
          _playlistId == playlistId &&
          generation == _browseGeneration) {
        isLoadingGroups = false;
        _notify();
      }
    }
  }

  Future<void> retryBrowseGroups() async {
    switch (browseGroupKind) {
      case CatalogGroupKind.live:
        await showItems(CatalogItemKind.live, groupId: selectedGroupId);
      case CatalogGroupKind.movie:
        await showItems(CatalogItemKind.movie, groupId: selectedGroupId);
      case CatalogGroupKind.series:
        await showSeries(groupId: selectedGroupId);
      case null:
        return;
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
    searchResults.dispose();
    super.dispose();
  }
}
