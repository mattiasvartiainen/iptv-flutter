import '../../models/content_item.dart';
import 'catalog_normalizer.dart';
import 'catalog_query.dart';

/// Read side of the catalog: every method returns a bounded result set so the
/// UI never has to hold a whole playlist in memory.
abstract interface class CatalogQueryService {
  /// Applies kind/group/search filters and returns a single page.
  Future<CatalogPage<CatalogItemSummary>> queryItems(CatalogQuery query);

  /// Small unpaged slice used by the home rows.
  Future<List<CatalogItemSummary>> homePreview(
    String playlistId, {
    required CatalogItemKind kind,
    int limit = kHomePreviewCount,
  });

  Future<CatalogPage<SeriesSummary>> querySeries(
    String playlistId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
  });

  Future<List<SeasonSummary>> seasons(String seriesId);

  Future<CatalogPage<CatalogItemSummary>> episodes(
    String seasonId, {
    int offset = 0,
    int limit = kCatalogPageSize,
  });

  Future<List<String>> groups(
    String playlistId, {
    List<CatalogItemKind> kinds = const [],
  });

  /// Full row for the selected item; the only place a [ContentItem] is built.
  Future<ContentItem?> itemById(String itemId);
}

/// Converts free text into a safe FTS5 prefix expression.
///
/// User input reaches `MATCH` directly, so every token is quoted to neutralise
/// FTS5 operators (`"`, `*`, `-`, `NEAR`, `:`) that would otherwise be parsed
/// as syntax and raise a SqliteException. Returns null when nothing searchable
/// remains, in which case callers should skip the FTS path.
String? buildFtsPrefixQuery(String term) {
  final tokens = term
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((token) => token.isNotEmpty)
      .toList();
  if (tokens.isEmpty) return null;
  return tokens.map((token) => '"$token"*').join(' ');
}

/// List-backed implementation for fixtures, tests and the non-caching
/// [M3uCatalogRepository]. Series structure is derived once up front rather
/// than on every query.
class InMemoryCatalogQueryService implements CatalogQueryService {
  InMemoryCatalogQueryService(this.playlistId, List<ContentItem> items) {
    _index(items);
  }

  final String playlistId;

  final Map<String, ContentItem> _itemsById = {};
  final Map<String, CatalogItemKind> _kindById = {};
  final List<CatalogItemSummary> _summaries = [];
  final Map<String, SeriesSummary> _seriesById = {};
  final Map<String, List<SeasonSummary>> _seasonsBySeries = {};
  final Map<String, List<CatalogItemSummary>> _episodesBySeason = {};

  void _index(List<ContentItem> items) {
    final seasonNumbersBySeries = <String, Set<int>>{};
    final episodeCountBySeries = <String, int>{};
    final seriesTitleById = <String, String>{};
    final seasonNumberById = <String, int>{};
    final seriesIdBySeason = <String, String>{};

    for (final item in items) {
      final match = CatalogNormalizer.parseSeriesEpisodeTitle(item.title);
      final isEpisode =
          item.type == ContentType.vod &&
          match != null &&
          match.seriesTitle.isNotEmpty;
      final kind = switch ((item.type, isEpisode)) {
        (ContentType.live, _) => CatalogItemKind.live,
        (ContentType.vod, true) => CatalogItemKind.episode,
        (ContentType.vod, false) => CatalogItemKind.movie,
      };

      final summary = CatalogItemSummary(
        id: item.id,
        title: item.title,
        sortTitle: CatalogNormalizer.normalizeText(item.title),
        kind: kind,
        group: CatalogNormalizer.canonicalGroup(item.group),
        logoUrl: item.logoUrl,
        artworkUrl: item.posterUrl,
        sourceIndex: item.sourceIndex,
        episodeNumber: isEpisode ? match.episodeNumber : null,
      );

      _itemsById[item.id] = item;
      _kindById[item.id] = kind;
      _summaries.add(summary);

      if (!isEpisode) continue;

      final seriesId = 'series|$playlistId|${match.seriesTitle}';
      final seasonId = 'season|$seriesId|${match.seasonNumber}';
      seriesTitleById[seriesId] = match.seriesTitle;
      seasonNumberById[seasonId] = match.seasonNumber;
      seriesIdBySeason[seasonId] = seriesId;
      seasonNumbersBySeries
          .putIfAbsent(seriesId, () => <int>{})
          .add(match.seasonNumber);
      episodeCountBySeries[seriesId] =
          (episodeCountBySeries[seriesId] ?? 0) + 1;
      _episodesBySeason.putIfAbsent(seasonId, () => []).add(summary);
    }

    for (final entry in seriesTitleById.entries) {
      _seriesById[entry.key] = SeriesSummary(
        id: entry.key,
        title: entry.value,
        sortTitle: CatalogNormalizer.normalizeText(entry.value),
        seasonCount: seasonNumbersBySeries[entry.key]?.length ?? 0,
        episodeCount: episodeCountBySeries[entry.key] ?? 0,
      );
    }

    for (final entry in seasonNumberById.entries) {
      final seriesId = seriesIdBySeason[entry.key]!;
      _seasonsBySeries
          .putIfAbsent(seriesId, () => [])
          .add(
            SeasonSummary(
              id: entry.key,
              seriesId: seriesId,
              seasonNumber: entry.value,
              episodeCount: _episodesBySeason[entry.key]?.length ?? 0,
            ),
          );
    }

    for (final seasons in _seasonsBySeries.values) {
      seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    }
  }

  @override
  Future<CatalogPage<CatalogItemSummary>> queryItems(CatalogQuery query) async {
    if (query.playlistId != playlistId) return const CatalogPage.empty();

    final term = query.searchTerm?.trim().toLowerCase();
    final matches = _summaries.where((summary) {
      if (query.kinds.isNotEmpty && !query.kinds.contains(summary.kind)) {
        return false;
      }
      if (query.group != null && summary.group != query.group) return false;
      if (term != null && term.isNotEmpty) {
        return summary.sortTitle.contains(term);
      }
      return true;
    }).toList();

    _sort(matches, query.sort);
    return _paginate(matches, offset: query.offset, limit: query.limit);
  }

  @override
  Future<List<CatalogItemSummary>> homePreview(
    String playlistId, {
    required CatalogItemKind kind,
    int limit = kHomePreviewCount,
  }) async {
    final page = await queryItems(
      CatalogQuery(playlistId: playlistId, kinds: [kind], limit: limit),
    );
    return page.items;
  }

  @override
  Future<CatalogPage<SeriesSummary>> querySeries(
    String playlistId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
  }) async {
    if (playlistId != this.playlistId) return const CatalogPage.empty();

    final term = searchTerm?.trim().toLowerCase();
    final matches =
        _seriesById.values
            .where(
              (series) =>
                  term == null ||
                  term.isEmpty ||
                  series.sortTitle.contains(term),
            )
            .toList()
          ..sort((a, b) {
            final byTitle = a.sortTitle.compareTo(b.sortTitle);
            return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
          });

    return _paginate(matches, offset: offset, limit: limit);
  }

  @override
  Future<List<SeasonSummary>> seasons(String seriesId) async =>
      List.unmodifiable(_seasonsBySeries[seriesId] ?? const []);

  @override
  Future<CatalogPage<CatalogItemSummary>> episodes(
    String seasonId, {
    int offset = 0,
    int limit = kCatalogPageSize,
  }) async {
    final episodes = [...?_episodesBySeason[seasonId]]
      ..sort((a, b) => (a.episodeNumber ?? 0).compareTo(b.episodeNumber ?? 0));
    return _paginate(episodes, offset: offset, limit: limit);
  }

  @override
  Future<List<String>> groups(
    String playlistId, {
    List<CatalogItemKind> kinds = const [],
  }) async {
    if (playlistId != this.playlistId) return const [];
    final groups = <String>{};
    for (final summary in _summaries) {
      if (kinds.isNotEmpty && !kinds.contains(summary.kind)) continue;
      final group = summary.group;
      if (group != null && group.isNotEmpty) groups.add(group);
    }
    return groups.toList()..sort();
  }

  @override
  Future<ContentItem?> itemById(String itemId) async => _itemsById[itemId];

  void _sort(List<CatalogItemSummary> items, CatalogSort sort) {
    items.sort((a, b) {
      final primary = switch (sort) {
        CatalogSort.title => a.sortTitle.compareTo(b.sortTitle),
        CatalogSort.playlistOrder => a.sourceIndex.compareTo(b.sourceIndex),
      };
      return primary != 0 ? primary : a.id.compareTo(b.id);
    });
  }

  CatalogPage<T> _paginate<T>(
    List<T> all, {
    required int offset,
    required int limit,
  }) {
    if (offset >= all.length) {
      return CatalogPage<T>(items: const [], offset: offset, total: all.length);
    }
    final end = (offset + limit).clamp(0, all.length);
    return CatalogPage<T>(
      items: List.unmodifiable(all.sublist(offset, end)),
      offset: offset,
      total: all.length,
    );
  }
}
