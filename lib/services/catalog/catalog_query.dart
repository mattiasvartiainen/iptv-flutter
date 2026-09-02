import 'package:flutter/foundation.dart';

import '../../models/content_item.dart';

/// Storage-level content classification.
///
/// [ContentType] only distinguishes live from on-demand, but `media_items`
/// separates movies from episodes so browsing surfaces can filter without
/// re-parsing titles in Dart.
enum CatalogItemKind {
  live,
  movie,
  episode,
  unknown;

  static CatalogItemKind fromStorage(String? value) => switch (value) {
    'live' => CatalogItemKind.live,
    'movie' => CatalogItemKind.movie,
    'episode' => CatalogItemKind.episode,
    _ => CatalogItemKind.unknown,
  };

  String get storageValue => name;

  ContentType get contentType =>
      this == CatalogItemKind.live ? ContentType.live : ContentType.vod;
}

enum CatalogSort {
  /// Alphabetical by `sort_title`.
  title,

  /// Original playlist ordering by `source_index`.
  playlistOrder,
}

/// A single page of results plus enough metadata to drive incremental loading.
@immutable
class CatalogPage<T> {
  const CatalogPage({
    required this.items,
    required this.offset,
    required this.total,
  });

  const CatalogPage.empty() : items = const [], offset = 0, total = 0;

  final List<T> items;
  final int offset;

  /// Total number of rows matching the query, not just this page.
  final int total;

  bool get isEmpty => items.isEmpty;
  bool get hasMore => offset + items.length < total;
  int get nextOffset => offset + items.length;

  CatalogPage<T> append(CatalogPage<T> next) => CatalogPage<T>(
    items: [...items, ...next.items],
    offset: offset,
    total: next.total,
  );
}

/// Lightweight row projection for lists and grids.
///
/// Deliberately excludes `stream_url`, `description` and the parsed attribute
/// map: browsing surfaces never need them, and retaining them is what makes a
/// large catalog expensive to hold in memory.
@immutable
class CatalogItemSummary {
  const CatalogItemSummary({
    required this.id,
    required this.title,
    required this.sortTitle,
    required this.kind,
    this.group,
    this.logoUrl,
    this.artworkUrl,
    this.sourceIndex = 0,
    this.episodeNumber,
  });

  final String id;
  final String title;
  final String sortTitle;
  final CatalogItemKind kind;
  final String? group;
  final String? logoUrl;
  final String? artworkUrl;
  final int sourceIndex;

  /// Only populated by episode queries.
  final int? episodeNumber;

  ContentType get type => kind.contentType;

  static CatalogItemSummary fromRow(Map<String, Object?> row) =>
      CatalogItemSummary(
        id: row['id'] as String,
        title: row['title'] as String,
        sortTitle: (row['sort_title'] as String?) ?? row['title'] as String,
        kind: CatalogItemKind.fromStorage(row['content_type'] as String?),
        group: row['group_title'] as String?,
        logoUrl: row['logo_url'] as String?,
        artworkUrl: row['artwork_url'] as String?,
        sourceIndex: (row['source_index'] as int?) ?? 0,
        episodeNumber: row['episode_number'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      other is CatalogItemSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class SeriesSummary {
  const SeriesSummary({
    required this.id,
    required this.title,
    required this.sortTitle,
    required this.seasonCount,
    required this.episodeCount,
    this.artworkUrl,
  });

  final String id;
  final String title;
  final String sortTitle;
  final int seasonCount;
  final int episodeCount;
  final String? artworkUrl;

  static SeriesSummary fromRow(Map<String, Object?> row) => SeriesSummary(
    id: row['id'] as String,
    title: row['title'] as String,
    sortTitle: (row['sort_title'] as String?) ?? row['title'] as String,
    seasonCount: (row['season_count'] as int?) ?? 0,
    episodeCount: (row['episode_count'] as int?) ?? 0,
    artworkUrl: row['artwork_url'] as String?,
  );

  @override
  bool operator ==(Object other) => other is SeriesSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class SeasonSummary {
  const SeasonSummary({
    required this.id,
    required this.seriesId,
    required this.seasonNumber,
    required this.episodeCount,
  });

  final String id;
  final String seriesId;
  final int seasonNumber;
  final int episodeCount;

  static SeasonSummary fromRow(Map<String, Object?> row) => SeasonSummary(
    id: row['id'] as String,
    seriesId: row['series_id'] as String,
    seasonNumber: (row['season_number'] as int?) ?? 0,
    episodeCount: (row['episode_count'] as int?) ?? 0,
  );

  @override
  bool operator ==(Object other) => other is SeasonSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Default number of rows fetched per catalog page.
const int kCatalogPageSize = 100;

/// Number of preview tiles rendered per home row.
const int kHomePreviewCount = 12;

@immutable
class CatalogQuery {
  const CatalogQuery({
    required this.playlistId,
    this.kinds = const [],
    this.group,
    this.searchTerm,
    this.offset = 0,
    this.limit = kCatalogPageSize,
    this.sort = CatalogSort.title,
  }) : assert(limit > 0, 'limit must be positive'),
       assert(offset >= 0, 'offset must not be negative');

  final String playlistId;

  /// Empty means "any kind".
  final List<CatalogItemKind> kinds;
  final String? group;
  final String? searchTerm;
  final int offset;
  final int limit;
  final CatalogSort sort;

  bool get hasSearchTerm => (searchTerm?.trim().isNotEmpty) ?? false;

  CatalogQuery nextPage() => copyWith(offset: offset + limit);

  /// Returns a query for the first page, dropping any accumulated offset.
  CatalogQuery reset() => copyWith(offset: 0);

  CatalogQuery copyWith({
    String? playlistId,
    List<CatalogItemKind>? kinds,
    Object? group = _unset,
    Object? searchTerm = _unset,
    int? offset,
    int? limit,
    CatalogSort? sort,
  }) => CatalogQuery(
    playlistId: playlistId ?? this.playlistId,
    kinds: kinds ?? this.kinds,
    group: identical(group, _unset) ? this.group : group as String?,
    searchTerm: identical(searchTerm, _unset)
        ? this.searchTerm
        : searchTerm as String?,
    offset: offset ?? this.offset,
    limit: limit ?? this.limit,
    sort: sort ?? this.sort,
  );

  /// Identity of the result set, ignoring paging position.
  String get resultSetKey =>
      '$playlistId|${kinds.map((k) => k.name).join(",")}|'
      '${group ?? ""}|${searchTerm?.trim() ?? ""}|${sort.name}';

  @override
  bool operator ==(Object other) =>
      other is CatalogQuery &&
      other.resultSetKey == resultSetKey &&
      other.offset == offset &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(resultSetKey, offset, limit);
}

const Object _unset = Object();
