import 'dart:async';

import 'package:sqflite_common/sqlite_api.dart';

import '../../models/content_item.dart';
import '../storage/storage_contracts.dart';
import 'catalog_import_coordinator.dart';
import 'catalog_importer.dart';
import 'catalog_normalizer.dart';
import 'catalog_query.dart';
import 'catalog_query_service.dart';
import 'catalog_repository.dart';
import 'id_identity.dart';

class SqliteCatalogRepository
    implements CatalogRepository, CatalogQueryService {
  SqliteCatalogRepository({
    required DatabaseAdapter databaseAdapter,
    this.autoStartSearchIndexWorker = true,
    CatalogImportCoordinator? importCoordinator,
  }) : _databaseAdapter = databaseAdapter,
       _importCoordinator = importCoordinator ?? CatalogImportCoordinator() {
    _catalogImporter = CatalogImporter(
      databaseAdapter: _databaseAdapter,
      coordinator: _importCoordinator,
    );
  }

  final DatabaseAdapter _databaseAdapter;
  final CatalogImportCoordinator _importCoordinator;
  late final CatalogImporter _catalogImporter;

  /// When false, a successful import only queues search-index changes and
  /// leaves draining to an explicit [processCatalogSearchIndexQueue] call.
  /// Useful in tests that need to assert on queued-but-undrained state.
  final bool autoStartSearchIndexWorker;

  /// Playlists with a search-index drain already in flight; prevents a
  /// second refresh from starting a competing worker for the same playlist.
  final Set<String> _indexingPlaylists = {};

  final Set<String> _pausedIndexingPlaylists = {};

  /// Default batch size for [processCatalogSearchIndexQueue]. Each batch
  /// costs a fixed handful of set-based statements, so it is sized to bound
  /// the transaction rather than the statement count.
  static const int searchIndexBatchSize = 2000;

  /// Upper bound on ids per `... WHERE id IN (...)` statement, well under
  /// SQLite's default bound parameter limit.
  static const int _deleteChunkSize = 500;

  Future<void> cancelImport(String playlistId) {
    return _importCoordinator.cancel(playlistId);
  }

  Future<void> recoverAbandonedImports() async {
    final db = await _databaseAdapter.database;
    final abandoned = await db.query(
      'import_sessions',
      columns: const ['id', 'playlist_id', 'tier'],
      where: 'state IN (?, ?)',
      whereArgs: ['running', 'reconciling'],
    );
    for (final session in abandoned) {
      final sessionId = session['id']! as int;
      final playlistId = session['playlist_id']! as String;
      final tier = session['tier'];
      final isColdV9Import = tier == 'cold_import';
      final isWarmV9Import = tier == 'row_diff';
      await _databaseAdapter.transaction((txn) async {
        if (isColdV9Import) {
          await txn.delete(
            'items_fts_queue',
            where: 'playlist_id = ?',
            whereArgs: [playlistId],
          );
          await txn.delete(
            'items',
            where: 'playlist_id = ?',
            whereArgs: [playlistId],
          );
          await txn.delete(
            'series_v8',
            where: 'playlist_id = ?',
            whereArgs: [playlistId],
          );
          await txn.delete(
            'groups',
            where: 'playlist_id = ?',
            whereArgs: [playlistId],
          );
          await txn.delete(
            'import_rows',
            where: 'import_id = ?',
            whereArgs: [sessionId],
          );
          await txn.delete(
            'import_seen',
            where: 'import_id = ?',
            whereArgs: [sessionId],
          );
        } else if (isWarmV9Import) {
          await txn.delete(
            'import_rows',
            where: 'import_id = ?',
            whereArgs: [sessionId],
          );
          await txn.delete(
            'import_seen',
            where: 'import_id = ?',
            whereArgs: [sessionId],
          );
        }
        await txn.update(
          'import_sessions',
          {
            'state': 'aborted',
            'finished_at': DateTime.now().toUtc().millisecondsSinceEpoch,
            'error': 'Import interrupted by application shutdown.',
          },
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      });
    }
  }

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) async {
    final resolvedPlaylistId =
        playlistId ?? await _resolvePlaylistId(playlistUrl);

    final db = await _databaseAdapter.database;
    final cachedItems = await _countV9Items(db, resolvedPlaylistId);
    if (policy == CatalogLoadPolicy.cacheOnly) {
      return CatalogLoadResult(
        playlistId: resolvedPlaylistId,
        itemCount: cachedItems,
      );
    }
    if (policy == CatalogLoadPolicy.cacheFirst && cachedItems > 0) {
      final refreshDue = await _isRefreshDue(
        db,
        playlistId: resolvedPlaylistId,
      );
      if (!refreshDue) {
        return CatalogLoadResult(
          playlistId: resolvedPlaylistId,
          itemCount: cachedItems,
        );
      }
    }
    await _ensurePlaylistRefreshSettings(db, resolvedPlaylistId);
    _pausedIndexingPlaylists.add(resolvedPlaylistId);
    late final CatalogImportResult imported;
    try {
      imported = await _catalogImporter.importPlaylist(
        playlistId: resolvedPlaylistId,
        playlistUrl: playlistUrl,
        onProgress: onProgress,
      );
      await _markRefreshSuccess(
        db,
        playlistId: resolvedPlaylistId,
        completedAt: DateTime.now().toUtc(),
      );
    } finally {
      _pausedIndexingPlaylists.remove(resolvedPlaylistId);
    }
    _startCatalogSearchIndexWorker(resolvedPlaylistId);
    return CatalogLoadResult(
      playlistId: imported.playlistId,
      itemCount: imported.itemCount,
    );
  }

  Future<int> _countV9Items(DatabaseExecutor db, String playlistId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS item_count FROM items WHERE playlist_id = ?',
      [playlistId],
    );
    return (rows.single['item_count'] as num).toInt();
  }

  // --- CatalogQueryService ---------------------------------------------------

  @override
  Future<CatalogPage<CatalogItemSummary>> queryItems(CatalogQuery query) async {
    final db = await _databaseAdapter.database;
    return _queryV9Items(db, query);
  }

  @override
  Future<CatalogSearchIndexStatus> searchIndexStatus(String playlistId) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      '''
SELECT
  (SELECT COUNT(*) FROM items WHERE playlist_id = ?) AS total_items,
  (SELECT COUNT(*) FROM items_fts_queue WHERE playlist_id = ?) AS pending_items,
  (SELECT COUNT(*) FROM items_fts_queue q JOIN items i
    ON i.id = q.item_id
    WHERE q.playlist_id = ? AND q.operation IN ('insert', 'upsert'))
    AS pending_upserts
''',
      [playlistId, playlistId, playlistId],
    );
    final row = rows.single;
    final totalItems = (row['total_items'] as num).toInt();
    final pendingItems = (row['pending_items'] as num).toInt();
    final pendingUpserts = (row['pending_upserts'] as num).toInt();
    final indexedItems = totalItems - pendingUpserts;
    return CatalogSearchIndexStatus(
      totalItems: totalItems,
      indexedItems: indexedItems < 0 ? 0 : indexedItems,
      pendingItems: pendingItems,
    );
  }

  @override
  Future<List<CatalogItemSummary>> homePreview(
    String playlistId, {
    required CatalogItemKind kind,
    int limit = kHomePreviewCount,
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT $_v9SummaryColumns FROM items m '
      'JOIN groups g ON g.id = m.group_id '
      'WHERE m.playlist_id = ? AND m.kind = ? '
      "AND NOT EXISTS (SELECT 1 FROM hidden_groups_v8 h "
      'WHERE h.playlist_id = m.playlist_id AND h.kind = g.kind '
      "AND h.group_title = g.title AND h.profile_id = 'default') "
      'ORDER BY m.sort_title, m.id LIMIT ?',
      [playlistId, _v9KindForItem(kind), limit],
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
    return _queryV9Series(
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
    return _queryV9Episodes(
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
      args.addAll(kinds.map(_v9KindForItem));
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
      [playlistId, _v9GroupKindValue(kind), profileId],
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
    if (await _isV9GroupHidden(
      db,
      playlistId: playlistId,
      groupId: groupId,
      profileId: 'default',
    )) {
      return const CatalogPage.empty();
    }
    return _queryV9Items(
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
    if (await _isV9GroupHidden(
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
    return _queryV9Series(
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
    return _mapV9RowToItem(rows.single);
  }

  Future<void> setV9Favorite({
    required String playlistId,
    required int itemKey,
    required bool favorite,
    String profileId = 'default',
  }) async {
    final db = await _databaseAdapter.database;
    if (favorite) {
      await db.insert('favorites_v8', {
        'profile_id': profileId,
        'playlist_id': playlistId,
        'item_key': itemKey,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await db.delete(
        'favorites_v8',
        where: 'profile_id = ? AND playlist_id = ? AND item_key = ?',
        whereArgs: [profileId, playlistId, itemKey],
      );
    }
  }

  Future<List<CatalogItemSummary>> v9FavoriteItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kCatalogPageSize,
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT $_v9SummaryColumns FROM favorites_v8 f '
      'JOIN items m ON m.playlist_id = f.playlist_id AND m.item_key = f.item_key '
      'JOIN groups g ON g.id = m.group_id '
      'WHERE f.playlist_id = ? AND f.profile_id = ? '
      'ORDER BY f.created_at DESC, m.id LIMIT ?',
      [playlistId, profileId, limit],
    );
    return rows.map(CatalogItemSummary.fromRow).toList(growable: false);
  }

  Future<void> saveV9PlaybackProgress({
    required String playlistId,
    required int itemKey,
    required int positionMs,
    int? durationMs,
    String profileId = 'default',
  }) async {
    final db = await _databaseAdapter.database;
    await db.insert('playback_progress_v8', {
      'profile_id': profileId,
      'playlist_id': playlistId,
      'item_key': itemKey,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<CatalogPlaybackProgress?> v9PlaybackProgress({
    required String playlistId,
    required int itemKey,
    String profileId = 'default',
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.query(
      'playback_progress_v8',
      where: 'profile_id = ? AND playlist_id = ? AND item_key = ?',
      whereArgs: [profileId, playlistId, itemKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CatalogPlaybackProgress(
      itemKey: row['item_key']! as int,
      positionMs: row['position_ms']! as int,
      durationMs: row['duration_ms'] as int?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
    );
  }

  Future<void> recordV9WatchHistory({
    required String playlistId,
    required int itemKey,
    required bool completed,
    int? positionMs,
    int? durationMs,
    String profileId = 'default',
  }) async {
    final db = await _databaseAdapter.database;
    await db.insert('watch_history_v8', {
      'profile_id': profileId,
      'playlist_id': playlistId,
      'item_key': itemKey,
      'watched_at': DateTime.now().millisecondsSinceEpoch,
      'completed': completed ? 1 : 0,
      'position_ms': positionMs,
      'duration_ms': durationMs,
    });
  }

  Future<List<CatalogItemSummary>> v9RecentlyWatchedItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kHomePreviewCount,
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT $_v9SummaryColumns FROM watch_history_v8 h '
      'JOIN items m ON m.playlist_id = h.playlist_id AND m.item_key = h.item_key '
      'JOIN groups g ON g.id = m.group_id '
      'WHERE h.playlist_id = ? AND h.profile_id = ? '
      'GROUP BY m.id ORDER BY MAX(h.watched_at) DESC LIMIT ?',
      [playlistId, profileId, limit],
    );
    return rows.map(CatalogItemSummary.fromRow).toList(growable: false);
  }

  static const String _v9SummaryColumns =
      'm.id AS id, m.title AS title, m.sort_title AS sort_title, '
      'm.kind AS kind, g.id AS group_id, g.title AS group_title, m.logo_url AS logo_url, '
      'm.logo_url AS artwork_url, m.ord AS ord, '
      'm.episode_number AS episode_number';

  Future<bool> _isV9GroupHidden(
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

  Future<CatalogPage<CatalogItemSummary>> _queryV9Items(
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
      args.addAll(query.kinds.map(_v9KindForItem));
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
      'SELECT $_v9SummaryColumns FROM $from WHERE $where '
      'ORDER BY $orderBy LIMIT ? OFFSET ?',
      [...args, query.limit, query.offset],
    );
    return CatalogPage<CatalogItemSummary>(
      items: rows.map(CatalogItemSummary.fromRow).toList(growable: false),
      offset: query.offset,
      total: total,
    );
  }

  Future<CatalogPage<SeriesSummary>> _queryV9Series(
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

  Future<CatalogPage<CatalogItemSummary>> _queryV9Episodes(
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
      'SELECT $_v9SummaryColumns FROM $from WHERE $where '
      'ORDER BY m.episode_number, m.id LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );
    return CatalogPage<CatalogItemSummary>(
      items: rows.map(CatalogItemSummary.fromRow).toList(growable: false),
      offset: offset,
      total: total,
    );
  }

  static int _v9KindForItem(CatalogItemKind kind) => switch (kind) {
    CatalogItemKind.live => 1,
    CatalogItemKind.movie => 2,
    CatalogItemKind.episode => 3,
    CatalogItemKind.unknown => 0,
  };

  static int _v9GroupKindValue(CatalogGroupKind kind) => switch (kind) {
    CatalogGroupKind.live => 1,
    CatalogGroupKind.movie => 2,
    CatalogGroupKind.series => 3,
  };

  ContentItem _mapV9RowToItem(Map<String, Object?> row) => ContentItem(
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

  Future<bool> _isRefreshDue(
    DatabaseExecutor db, {
    required String playlistId,
  }) async {
    final rows = await db.query(
      'playlist_settings',
      columns: const ['refresh_enabled', 'refresh_mode', 'next_refresh_at'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (rows.isEmpty) return true;

    final row = rows.first;
    final refreshEnabled = (row['refresh_enabled'] as int? ?? 1) == 1;
    if (!refreshEnabled) return false;

    final refreshMode = (row['refresh_mode'] as String?) ?? 'weekly';
    if (refreshMode == 'manual') return false;

    final nextRefreshRaw = row['next_refresh_at'] as String?;
    if (nextRefreshRaw == null || nextRefreshRaw.isEmpty) return true;

    final nextRefreshAt = DateTime.tryParse(nextRefreshRaw)?.toUtc();
    if (nextRefreshAt == null) return true;

    final now = DateTime.now().toUtc();
    return now.isAfter(nextRefreshAt) || now.isAtSameMomentAs(nextRefreshAt);
  }

  Future<void> _ensurePlaylistRefreshSettings(
    DatabaseExecutor db,
    String playlistId,
  ) async {
    final settingsRows = await db.query(
      'playlist_settings',
      columns: const ['playlist_id'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (settingsRows.isNotEmpty) return;

    final playlistRows = await db.query(
      'playlists',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (playlistRows.isEmpty) return;

    await db.insert('playlist_settings', {
      'playlist_id': playlistId,
      'refresh_enabled': 1,
      'refresh_mode': 'weekly',
      'refresh_interval_hours': 168,
      'last_refresh_at': null,
      'next_refresh_at': null,
      'last_refresh_status': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _markRefreshSuccess(
    DatabaseExecutor db, {
    required String playlistId,
    required DateTime completedAt,
  }) async {
    final completedIso = completedAt.toUtc().toIso8601String();
    final settingsRows = await db.query(
      'playlist_settings',
      columns: const ['refresh_interval_hours', 'refresh_enabled'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );

    String? nextRefreshIso;
    if (settingsRows.isNotEmpty) {
      final row = settingsRows.first;
      final refreshEnabled = (row['refresh_enabled'] as int? ?? 1) == 1;
      if (refreshEnabled) {
        final intervalHours = row['refresh_interval_hours'] as int? ?? 168;
        nextRefreshIso = completedAt
            .toUtc()
            .add(Duration(hours: intervalHours))
            .toIso8601String();
      }
    }

    await db.update(
      'playlist_settings',
      {
        'last_refresh_at': completedIso,
        'next_refresh_at': nextRefreshIso,
        'last_refresh_status': 'success',
        'updated_at': completedIso,
      },
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
  }

  /// Restarts indexing for playlists whose queue survived a previous run
  /// (app killed mid-drain, or abandoned-import recovery).
  Future<void> resumeSearchIndexing() async {
    final db = await _databaseAdapter.database;
    final catalogRows = await db.rawQuery(
      'SELECT DISTINCT playlist_id FROM items_fts_queue',
    );
    for (final row in catalogRows) {
      _startCatalogSearchIndexWorker(row['playlist_id']! as String);
    }
  }

  void _startCatalogSearchIndexWorker(String playlistId) {
    if (!autoStartSearchIndexWorker) return;
    if (!_indexingPlaylists.add('catalog:$playlistId')) return;
    unawaited(
      processCatalogSearchIndexQueue(playlistId: playlistId)
          .catchError((Object _, StackTrace stackTrace) => 0)
          .whenComplete(() => _indexingPlaylists.remove('catalog:$playlistId')),
    );
  }

  Future<int> processCatalogSearchIndexQueue({
    String? playlistId,
    int batchSize = searchIndexBatchSize,
  }) async {
    var processed = 0;
    while (true) {
      final batchCount = await _drainCatalogSearchIndexBatch(
        playlistId: playlistId,
        batchSize: batchSize,
      );
      if (batchCount == 0) return processed;
      processed += batchCount;
    }
  }

  Future<int> _drainCatalogSearchIndexBatch({
    required String? playlistId,
    required int batchSize,
  }) async {
    if (playlistId != null && _pausedIndexingPlaylists.contains(playlistId)) {
      return 0;
    }
    return _databaseAdapter.transaction((txn) async {
      final rows = await txn.query(
        'items_fts_queue',
        columns: const ['item_id', 'operation', 'old_title'],
        where: playlistId == null ? null : 'playlist_id = ?',
        whereArgs: playlistId == null ? null : [playlistId],
        orderBy: 'priority, queued_at, item_id',
        limit: batchSize,
      );
      if (rows.isEmpty) return 0;
      if (playlistId != null && _pausedIndexingPlaylists.contains(playlistId)) {
        return 0;
      }

      final queuedIds = <int>[];
      final deleteEntries = <(int, String)>[];
      final upsertIds = <int>[];
      for (final row in rows) {
        final itemId = (row['item_id'] as num).toInt();
        queuedIds.add(itemId);
        final operation = row['operation']! as String;
        final oldTitle = row['old_title'] as String?;
        if (oldTitle != null) deleteEntries.add((itemId, oldTitle));
        if (operation == 'upsert') upsertIds.add(itemId);
      }

      for (final chunk in _chunked(deleteEntries, size: 300)) {
        final values = <Object?>[];
        for (final entry in chunk) {
          values
            ..add(entry.$1)
            ..add(entry.$2);
        }
        final tuples = List.filled(chunk.length, "('delete', ?, ?)").join(', ');
        await txn.rawInsert(
          'INSERT INTO items_fts(items_fts, rowid, title) VALUES $tuples',
          values,
        );
      }
      for (final chunk in _chunked(upsertIds)) {
        final placeholders = _placeholders(chunk.length);
        await txn.rawInsert(
          'INSERT INTO items_fts(rowid, title) '
          'SELECT id, title FROM items WHERE id IN ($placeholders)',
          chunk,
        );
      }
      for (final chunk in _chunked(queuedIds)) {
        await txn.rawDelete(
          'DELETE FROM items_fts_queue WHERE item_id IN (${_placeholders(chunk.length)})',
          chunk,
        );
      }
      return rows.length;
    });
  }

  static Iterable<List<T>> _chunked<T>(
    List<T> values, {
    int size = _deleteChunkSize,
  }) sync* {
    for (var start = 0; start < values.length; start += size) {
      final end = start + size;
      yield values.sublist(start, end > values.length ? values.length : end);
    }
  }

  static String _placeholders(int count) => List.filled(count, '?').join(', ');

  Future<String> _resolvePlaylistId(String playlistUrl) async {
    final strongId = strongStableId('playlist', playlistUrl);
    final legacyId = legacyStableId('id', 'playlist|$playlistUrl');
    final db = await _databaseAdapter.database;

    final strongRows = await db.query(
      'playlists',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [strongId],
      limit: 1,
    );
    if (strongRows.isNotEmpty) return strongId;

    final legacyRows = await db.query(
      'playlists',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [legacyId],
      limit: 1,
    );
    if (legacyRows.isNotEmpty) return legacyId;

    return strongId;
  }
}
