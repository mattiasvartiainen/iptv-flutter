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
    await refreshHomeSections();
  }

  void unbind() {
    _service = null;
    _playlistId = null;
    items.clear();
    series.clear();
    episodes.clear();
    seasons = const [];
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

  Future<void> showItems(CatalogItemKind kind) {
    final service = _service;
    final playlistId = _playlistId;
    if (service == null || playlistId == null) return Future<void>.value();

    return items.load(
      (offset, limit) => service.queryItems(
        CatalogQuery(
          playlistId: playlistId,
          kinds: [kind],
          offset: offset,
          limit: limit,
        ),
      ),
    );
  }

  Future<void> showSeries() {
    final service = _service;
    final playlistId = _playlistId;
    if (service == null || playlistId == null) return Future<void>.value();

    return series.load(
      (offset, limit) =>
          service.querySeries(playlistId, offset: offset, limit: limit),
    );
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
