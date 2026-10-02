import '../../models/content_item.dart';
import 'catalog_normalizer.dart';
import 'catalog_query.dart';

/// Read side of the catalog: every method returns a bounded result set so the
/// UI never has to hold a whole playlist in memory.
abstract interface class CatalogQueryService {
  /// Applies kind/group/search filters and returns a single page.
  Future<CatalogPage<CatalogItemSummary>> queryItems(CatalogQuery query);

  Future<List<GroupSummary>> queryGroups(
    String playlistId, {
    required CatalogGroupKind kind,
    String profileId = 'default',
  });

  Future<CatalogPage<CatalogItemSummary>> itemsInGroup(
    String playlistId,
    int groupId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    CatalogSort sort = CatalogSort.title,
  });

  Future<CatalogPage<SeriesSummary>> seriesInGroup(
    String playlistId,
    int groupId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
  });

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
  final Map<(CatalogGroupKind, String), int> _groupIds = {};
  final Map<int, (CatalogGroupKind, String)> _groupById = {};
  final List<CatalogItemSummary> _summaries = [];
  final Map<String, SeriesSummary> _seriesById = {};
  final Map<String, List<SeasonSummary>> _seasonsBySeries = {};
  final Map<String, List<CatalogItemSummary>> _episodesBySeason = {};

  void _index(List<ContentItem> items) {
    final seasonNumbersBySeries = <String, Set<int>>{};
    final episodeCountBySeries = <String, int>{};
    final seriesTitleById = <String, String>{};
    final seriesGroupIdById = <String, int>{};
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
        groupId: _groupIdFor(
          kind,
          CatalogNormalizer.canonicalGroup(item.group),
        ),
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
      seriesGroupIdById[seriesId] = summary.groupId!;
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
        groupId: seriesGroupIdById[entry.key],
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
      if (query.groupId != null && summary.groupId != query.groupId) {
        return false;
      }
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
    int? groupId,
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
            .where((series) => groupId == null || series.groupId == groupId)
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
  Future<List<GroupSummary>> queryGroups(
    String playlistId, {
    required CatalogGroupKind kind,
    String profileId = 'default',
  }) async {
    if (playlistId != this.playlistId) return const [];
    final summaries = <int, GroupSummary>{};
    for (final item in _summaries) {
      if (item.groupId == null) continue;
      final identity = _groupById[item.groupId!]!;
      if (identity.$1 != kind) continue;
      final current = summaries[item.groupId!];
      if (current == null) {
        summaries[item.groupId!] = GroupSummary(
          id: item.groupId!,
          kind: kind,
          title: identity.$2,
          sortTitle: CatalogNormalizer.normalizeText(identity.$2),
          itemCount: 1,
          ordinal: item.sourceIndex,
        );
      } else {
        summaries[item.groupId!] = GroupSummary(
          id: current.id,
          kind: current.kind,
          title: current.title,
          sortTitle: current.sortTitle,
          itemCount: current.itemCount + 1,
          ordinal: item.sourceIndex < current.ordinal
              ? item.sourceIndex
              : current.ordinal,
        );
      }
    }
    final result = summaries.values.toList()
      ..sort((a, b) {
        final order = a.ordinal.compareTo(b.ordinal);
        return order != 0 ? order : a.sortTitle.compareTo(b.sortTitle);
      });
    return result;
  }

  @override
  Future<CatalogPage<CatalogItemSummary>> itemsInGroup(
    String playlistId,
    int groupId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    CatalogSort sort = CatalogSort.title,
  }) => queryItems(
    CatalogQuery(
      playlistId: playlistId,
      groupId: groupId,
      offset: offset,
      limit: limit,
      sort: sort,
    ),
  );

  @override
  Future<CatalogPage<SeriesSummary>> seriesInGroup(
    String playlistId,
    int groupId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
  }) => querySeries(
    playlistId,
    offset: offset,
    limit: limit,
    searchTerm: searchTerm,
    groupId: groupId,
  );

  @override
  Future<ContentItem?> itemById(String itemId) async => _itemsById[itemId];

  int _groupIdFor(CatalogItemKind kind, String title) {
    final groupKind = switch (kind) {
      CatalogItemKind.live => CatalogGroupKind.live,
      CatalogItemKind.movie => CatalogGroupKind.movie,
      CatalogItemKind.episode => CatalogGroupKind.series,
      CatalogItemKind.unknown => CatalogGroupKind.live,
    };
    return _groupIds.putIfAbsent((groupKind, title), () {
      final id = _groupIds.length + 1;
      _groupById[id] = (groupKind, title);
      return id;
    });
  }

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
