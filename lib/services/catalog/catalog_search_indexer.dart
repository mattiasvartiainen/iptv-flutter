import 'dart:async';

import '../storage/storage_contracts.dart';
import 'catalog_query.dart';

/// Maintains the v9 `items_fts` index from the `items_fts_queue`.
abstract interface class CatalogSearchIndexer {
  /// Runs [action] with draining for [playlistId] paused, so an import and
  /// the indexer never compete for the shared writer connection.
  Future<T> whilePaused<T>(String playlistId, Future<T> Function() action);

  /// Starts a background drain for [playlistId] unless one is running.
  void scheduleIndexing(String playlistId);

  /// Restarts draining for every playlist with queued work left by a
  /// previous run (app killed mid-drain, or abandoned-import recovery).
  Future<void> resumePendingIndexing();

  /// Drains the queue in bounded batches; returns the rows processed.
  Future<int> processQueue({String? playlistId, int batchSize});

  Future<CatalogSearchIndexStatus> status(String playlistId);
}

class SqliteCatalogSearchIndexer implements CatalogSearchIndexer {
  SqliteCatalogSearchIndexer({
    required DatabaseAdapter databaseAdapter,
    this.autoStartWorker = true,
  }) : _databaseAdapter = databaseAdapter;

  final DatabaseAdapter _databaseAdapter;

  /// When false, [scheduleIndexing] is a no-op and draining only happens on
  /// an explicit [processQueue] call. Useful in tests that need to assert on
  /// queued-but-undrained state.
  final bool autoStartWorker;

  /// Each batch costs a fixed handful of set-based statements, so it is sized
  /// to bound the transaction rather than the statement count.
  static const int defaultBatchSize = 2000;

  /// Upper bound on ids per `... WHERE id IN (...)` statement, well under
  /// SQLite's default bound parameter limit.
  static const int _chunkSize = 500;

  final Set<String> _indexingPlaylists = {};
  final Set<String> _pausedPlaylists = {};

  @override
  Future<T> whilePaused<T>(
    String playlistId,
    Future<T> Function() action,
  ) async {
    _pausedPlaylists.add(playlistId);
    try {
      return await action();
    } finally {
      _pausedPlaylists.remove(playlistId);
    }
  }

  @override
  void scheduleIndexing(String playlistId) {
    if (!autoStartWorker) return;
    if (!_indexingPlaylists.add(playlistId)) return;
    unawaited(
      processQueue(playlistId: playlistId)
          // The database may close under a detached drain; the queue persists.
          .catchError((Object _, StackTrace stackTrace) => 0)
          .whenComplete(() => _indexingPlaylists.remove(playlistId)),
    );
  }

  @override
  Future<void> resumePendingIndexing() async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT DISTINCT playlist_id FROM items_fts_queue',
    );
    for (final row in rows) {
      scheduleIndexing(row['playlist_id']! as String);
    }
  }

  @override
  Future<int> processQueue({
    String? playlistId,
    int batchSize = defaultBatchSize,
  }) async {
    var processed = 0;
    while (true) {
      final batchCount = await _drainBatch(
        playlistId: playlistId,
        batchSize: batchSize,
      );
      if (batchCount == 0) return processed;
      processed += batchCount;
    }
  }

  @override
  Future<CatalogSearchIndexStatus> status(String playlistId) async {
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

  Future<int> _drainBatch({
    required String? playlistId,
    required int batchSize,
  }) async {
    if (playlistId != null && _pausedPlaylists.contains(playlistId)) {
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
      if (playlistId != null && _pausedPlaylists.contains(playlistId)) {
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
    int size = _chunkSize,
  }) sync* {
    for (var start = 0; start < values.length; start += size) {
      final end = start + size;
      yield values.sublist(start, end > values.length ? values.length : end);
    }
  }

  static String _placeholders(int count) => List.filled(count, '?').join(', ');
}
