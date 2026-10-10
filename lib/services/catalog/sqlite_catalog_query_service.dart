import 'package:sqflite_common/sqlite_api.dart';

import '../../models/content_item.dart';
import '../storage/storage_contracts.dart';
import 'catalog_item_sql.dart';
import 'catalog_normalizer.dart';
import 'catalog_query.dart';
import 'catalog_query_service.dart';
import 'catalog_search_indexer.dart';

/// Paged reads over the v9 catalog (`items`, `groups`, `series_v8`,
/// `items_fts`), excluding groups hidden for the default profile.
class SqliteCatalogQueryService implements CatalogQueryService {
  SqliteCatalogQueryService({
    required DatabaseAdapter databaseAdapter,
    required CatalogSearchIndexer searchIndexer,
  }) : _databaseAdapter = databaseAdapter,
       _searchIndexer = searchIndexer;

  final DatabaseAdapter _databaseAdapter;
  final CatalogSearchIndexer _searchIndexer;

  @override
  Future<CatalogPage<CatalogItemSummary>> queryItems(CatalogQuery query) async {
    final db = await _databaseAdapter.database;
    return _queryItems(db, query);
  }

  @override
  Future<CatalogSearchIndexStatus> searchIndexStatus(String playlistId) =>
      _searchIndexer.status(playlistId);

  @override
  Future<List<CatalogItemSummary>> homePreview(
    String playlistId, {
    required CatalogItemKind kind,
    int limit = kHomePreviewCount,
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT $catalogItemSummaryColumns FROM items m '
      'JOIN groups g ON g.id = m.group_id '
      'WHERE m.playlist_id = ? AND m.kind = ? '
      "AND NOT EXISTS (SELECT 1 FROM hidden_groups_v8 h "
      'WHERE h.playlist_id = m.playlist_id AND h.kind = g.kind '
      "AND h.group_title = g.title AND h.profile_id = 'default') "
      'ORDER BY m.sort_title, m.id LIMIT ?',
      [playlistId, _itemKindValue(kind), limit],
    );
    return rows.map(CatalogItemSummary.fromRow).toList(growable: false);
  }

  @override
  Future<CatalogPage<SeriesSummary>> querySeries(
    String playlistId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
  }) async {
    final db = await _databaseAdapter.database;
    return _querySeries(
      db,
      playlistId,
      offset: offset,
      limit: limit,
      searchTerm: searchTerm,
    );
  }

  @override
  Future<List<SeasonSummary>> seasons(String seriesId) async {
    final seriesKey = int.tryParse(seriesId);
    if (seriesKey == null) return const [];
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      '''
SELECT ? AS series_key, season_number,
       COUNT(*) AS episode_count
FROM items
WHERE series_key = ? AND season_number IS NOT NULL
GROUP BY season_number
ORDER BY season_number
''',
      [seriesKey, seriesKey],
    );
    return rows
        .map(
          (row) => SeasonSummary(
            id: '$seriesKey:${row['season_number']}',
            seriesId: '$seriesKey',
            seasonNumber: row['season_number']! as int,
            episodeCount: (row['episode_count'] as num).toInt(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<CatalogPage<CatalogItemSummary>> episodes(
    String seasonId, {
    int offset = 0,
    int limit = kCatalogPageSize,
  }) async {
    final seasonParts = seasonId.split(':');
    final seriesKey = seasonParts.length == 2
        ? int.tryParse(seasonParts.first)
        : null;
    final seasonNumber = seasonParts.length == 2
        ? int.tryParse(seasonParts.last)
        : null;
    if (seriesKey == null || seasonNumber == null) {
      return CatalogPage<CatalogItemSummary>(
        items: const [],
        offset: offset,
        total: 0,
      );
    }
    final db = await _databaseAdapter.database;
    return _queryEpisodes(
      db,
      seriesKey,
      seasonNumber,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<List<String>> groups(
    String playlistId, {
    List<CatalogItemKind> kinds = const [],
  }) async {
    final db = await _databaseAdapter.database;
    final clauses = <String>['playlist_id = ?'];
    final args = <Object?>[playlistId];
    if (kinds.isNotEmpty) {
      clauses.add('kind IN (${List.filled(kinds.length, '?').join(', ')})');
      args.addAll(kinds.map(_itemKindValue));
    }
    final rows = await db.rawQuery(
      'SELECT DISTINCT title FROM groups WHERE ${clauses.join(' AND ')} '
      'ORDER BY title',
      args,
    );
    return rows.map((row) => row['title']! as String).toList(growable: false);
  }

  @override
  Future<List<GroupSummary>> queryGroups(
    String playlistId, {
    required CatalogGroupKind kind,
    String profileId = 'default',
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      '''
SELECT g.id, g.kind, g.title, g.sort_title, g.item_count, g.ord
FROM groups g
WHERE g.playlist_id = ? AND g.kind = ?
  AND NOT EXISTS (
    SELECT 1 FROM hidden_groups_v8 h
    WHERE h.playlist_id = g.playlist_id AND h.kind = g.kind
      AND h.group_title = g.title AND h.profile_id = ?
  )
ORDER BY g.ord, g.sort_title, g.id
''',
      [playlistId, _groupKindValue(kind), profileId],
    );
    return rows.map(GroupSummary.fromRow).toList(growable: false);
  }

  @override
  Future<CatalogPage<CatalogItemSummary>> itemsInGroup(
    String playlistId,
    int groupId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    CatalogSort sort = CatalogSort.title,
  }) async {
    final db = await _databaseAdapter.database;
    final groupRows = await db.query(
      'groups',
      columns: const ['id'],
      where: 'id = ? AND playlist_id = ?',
      whereArgs: [groupId, playlistId],
      limit: 1,
    );
    if (groupRows.isEmpty) return const CatalogPage.empty();
    if (await _isGroupHidden(
      db,
      playlistId: playlistId,
      groupId: groupId,
      profileId: 'default',
    )) {
      return const CatalogPage.empty();
    }
    return _queryItems(
      db,
      CatalogQuery(
        playlistId: playlistId,
        groupId: groupId,
        offset: offset,
        limit: limit,
        sort: sort,
      ),
    );
  }

  @override
  Future<CatalogPage<SeriesSummary>> seriesInGroup(
    String playlistId,
    int groupId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
  }) async {
    final db = await _databaseAdapter.database;
    final groupRows = await db.query(
      'groups',
      columns: const ['id', 'kind'],
      where: 'id = ? AND playlist_id = ?',
      whereArgs: [groupId, playlistId],
      limit: 1,
    );
    if (groupRows.isEmpty || groupRows.single['kind'] != 3) {
      return CatalogPage<SeriesSummary>(
        items: const [],
        offset: offset,
        total: 0,
      );
    }
    if (await _isGroupHidden(
      db,
      playlistId: playlistId,
      groupId: groupId,
      profileId: 'default',
    )) {
      return CatalogPage<SeriesSummary>(
        items: const [],
        offset: offset,
        total: 0,
      );
    }
    return _querySeries(
      db,
      playlistId,
      offset: offset,
      limit: limit,
      searchTerm: searchTerm,
      groupId: groupId,
    );
  }

  @override
  Future<ContentItem?> itemById(String itemId) async {
    final rowId = int.tryParse(itemId);
    if (rowId == null) return null;
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      '''
SELECT m.id, m.title, m.kind, m.stream_url, g.title AS group_title,
       m.logo_url, m.tvg_id, m.tvg_name, m.tvg_chno, m.xui_id, m.ord
FROM items m JOIN groups g ON g.id = m.group_id
WHERE m.id = ? LIMIT 1
''',
      [rowId],
    );
    if (rows.isEmpty) return null;
    return _mapRowToItem(rows.single);
  }

  Future<bool> _isGroupHidden(
    DatabaseExecutor db, {
    required String playlistId,
    required int groupId,
    required String profileId,
  }) async {
    final rows = await db.rawQuery(
      '''
SELECT 1 FROM groups g JOIN hidden_groups_v8 h
ON h.playlist_id = g.playlist_id AND h.kind = g.kind AND h.group_title = g.title
WHERE g.id = ? AND g.playlist_id = ? AND h.profile_id = ? LIMIT 1
''',
      [groupId, playlistId, profileId],
    );
    return rows.isNotEmpty;
  }

  Future<CatalogPage<CatalogItemSummary>> _queryItems(
    DatabaseExecutor db,
    CatalogQuery query,
  ) async {
    final fts = query.hasSearchTerm
        ? buildFtsPrefixQuery(query.searchTerm!)
        : null;
    if (query.hasSearchTerm && fts == null) {
      return CatalogPage<CatalogItemSummary>(
        items: const [],
        offset: query.offset,
        total: 0,
      );
    }
    final clauses = <String>[
      'm.playlist_id = ?',
      '''NOT EXISTS (
        SELECT 1 FROM hidden_groups_v8 h
        WHERE h.playlist_id = m.playlist_id AND h.kind = g.kind
          AND h.group_title = g.title AND h.profile_id = 'default'
      )''',
    ];
    final args = <Object?>[query.playlistId];
    if (fts != null) {
      clauses.add('items_fts MATCH ?');
      args.add(fts);
    }
    if (query.kinds.isNotEmpty) {
      clauses.add(
        'm.kind IN (${List.filled(query.kinds.length, '?').join(', ')})',
      );
      args.addAll(query.kinds.map(_itemKindValue));
    }
    if (query.group != null) {
      clauses.add('g.title = ?');
      args.add(query.group);
    }
    if (query.groupId != null) {
      clauses.add('m.group_id = ?');
      args.add(query.groupId);
    }
    final from = fts == null
        ? 'items m JOIN groups g ON g.id = m.group_id'
        : 'items_fts JOIN items m ON m.id = items_fts.rowid '
              'JOIN groups g ON g.id = m.group_id';
    final where = clauses.join(' AND ');
    final orderBy = fts != null
        ? 'bm25(items_fts), m.sort_title, m.id'
        : switch (query.sort) {
            CatalogSort.title => 'm.sort_title, m.id',
            CatalogSort.playlistOrder => 'm.ord, m.id',
          };
    final total = await _countRows(db, from: from, where: where, args: args);
    if (total == 0 || query.offset >= total) {
      return CatalogPage<CatalogItemSummary>(
        items: const [],
        offset: query.offset,
        total: total,
      );
    }
    final rows = await db.rawQuery(
      'SELECT $catalogItemSummaryColumns FROM $from WHERE $where '
      'ORDER BY $orderBy LIMIT ? OFFSET ?',
      [...args, query.limit, query.offset],
    );
    return CatalogPage<CatalogItemSummary>(
      items: rows.map(CatalogItemSummary.fromRow).toList(growable: false),
      offset: query.offset,
      total: total,
    );
  }

  Future<CatalogPage<SeriesSummary>> _querySeries(
    DatabaseExecutor db,
    String playlistId, {
    required int offset,
    required int limit,
    String? searchTerm,
    int? groupId,
  }) async {
    final clauses = <String>[
      's.playlist_id = ?',
      '''NOT EXISTS (
        SELECT 1 FROM hidden_groups_v8 h
        WHERE h.playlist_id = s.playlist_id AND h.kind = g.kind
          AND h.group_title = g.title AND h.profile_id = 'default'
      )''',
    ];
    final args = <Object?>[playlistId];
    if (groupId != null) {
      clauses.add('s.group_id = ?');
      args.add(groupId);
    }
    final term = searchTerm?.trim();
    if (term != null && term.isNotEmpty) {
      clauses.add('s.sort_title LIKE ? ESCAPE ?');
      args
        ..add('%${_escapeLike(CatalogNormalizer.normalizeText(term))}%')
        ..add(r'\');
    }
    final where = clauses.join(' AND ');
    final total = await _countRows(
      db,
      from: 'series_v8 s JOIN groups g ON g.id = s.group_id',
      where: where,
      args: args,
    );
    if (total == 0 || offset >= total) {
      return CatalogPage<SeriesSummary>(
        items: const [],
        offset: offset,
        total: total,
      );
    }
    final rows = await db.rawQuery(
      'SELECT s.series_key AS series_key, s.title, s.sort_title, '
      's.artwork_url, s.season_count, s.episode_count, s.group_id '
      'FROM series_v8 s JOIN groups g ON g.id = s.group_id '
      'WHERE $where ORDER BY s.sort_title, s.series_key '
      'LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return CatalogPage<SeriesSummary>(
      items: rows.map(SeriesSummary.fromRow).toList(growable: false),
      offset: offset,
      total: total,
    );
  }

  Future<CatalogPage<CatalogItemSummary>> _queryEpisodes(
    DatabaseExecutor db,
    int seriesKey,
    int seasonNumber, {
    required int offset,
    required int limit,
  }) async {
    const from = 'items m JOIN groups g ON g.id = m.group_id';
    const where = 'm.series_key = ? AND m.season_number = ?';
    final args = <Object?>[seriesKey, seasonNumber];
    final total = await _countRows(db, from: from, where: where, args: args);
    if (total == 0 || offset >= total) {
      return CatalogPage<CatalogItemSummary>(
        items: const [],
        offset: offset,
        total: total,
      );
    }
    final rows = await db.rawQuery(
      'SELECT $catalogItemSummaryColumns FROM $from WHERE $where '
      'ORDER BY m.episode_number, m.id LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return CatalogPage<CatalogItemSummary>(
      items: rows.map(CatalogItemSummary.fromRow).toList(growable: false),
      offset: offset,
      total: total,
    );
  }

  static int _itemKindValue(CatalogItemKind kind) => switch (kind) {
    CatalogItemKind.live => 1,
    CatalogItemKind.movie => 2,
    CatalogItemKind.episode => 3,
    CatalogItemKind.unknown => 0,
  };

  static int _groupKindValue(CatalogGroupKind kind) => switch (kind) {
    CatalogGroupKind.live => 1,
    CatalogGroupKind.movie => 2,
    CatalogGroupKind.series => 3,
  };

  ContentItem _mapRowToItem(Map<String, Object?> row) => ContentItem(
    id: (row['id']! as int).toString(),
    title: row['title']! as String,
    type: row['kind'] == 1 ? ContentType.live : ContentType.vod,
    streamUrl: row['stream_url']! as String,
    group: row['group_title']! as String,
    logoUrl: row['logo_url'] as String?,
    metadata: {
      if (row['tvg_id'] is String) 'tvg-id': row['tvg_id']! as String,
      if (row['tvg_name'] is String) 'tvg-name': row['tvg_name']! as String,
      if (row['tvg_chno'] is String) 'tvg-chno': row['tvg_chno']! as String,
      if (row['xui_id'] is String) 'xui-id': row['xui_id']! as String,
    },
    sourceIndex: row['ord']! as int,
  );

  Future<int> _countRows(
    DatabaseExecutor db, {
    required String from,
    required String where,
    required List<Object?> args,
  }) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM $from WHERE $where',
      args,
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
