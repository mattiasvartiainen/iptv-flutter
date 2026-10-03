part of 'catalog_importer.dart';

extension _CatalogImporterWarm on CatalogImporter {
  Future<CatalogImportResult> _importWarm({
    required String playlistId,
    required String playlistUrl,
    required CatalogImportReporter reporter,
  }) async {
    final db = await _databaseAdapter.database;
    final totalStopwatch = Stopwatch()..start();
    final sessionId = await db.insert('import_sessions', {
      'playlist_id': playlistId,
      'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      'state': 'running',
      'tier': 'row_diff',
    });
    reporter.attachSession(sessionId);

    var bytesReceived = 0;
    int? bytesTotal;
    var parsedItems = 0;
    var newCount = 0;
    var changedCount = 0;
    var movedCount = 0;
    CatalogImportWorkerHandle? worker;

    try {
      worker = await CatalogImportWorker.start(
        playlistId: playlistId,
        playlistUrl: playlistUrl,
        selectRows: (batch) async {
          final previous = <int, (int, int)>{};
          for (final keyChunk in _warmChunks(
            batch.itemKeys.toList(growable: false),
            400,
          )) {
            final found = await db.rawQuery(
              'SELECT item_key, content_hash, ord FROM items '
              'WHERE playlist_id = ? AND item_key IN '
              '(${List.filled(keyChunk.length, '?').join(', ')})',
              [playlistId, ...keyChunk],
            );
            for (final row in found) {
              previous[row['item_key']! as int] = (
                row['content_hash']! as int,
                row['ord']! as int,
              );
            }
          }

          final requested = <int>[];
          final seenValues = <(int, int?)>[];
          for (var index = 0; index < batch.itemKeys.length; index++) {
            final key = batch.itemKeys[index];
            final old = previous[key];
            if (old == null) {
              newCount++;
              requested.add(index);
              seenValues.add((key, null));
            } else if (old.$1 != batch.contentHashes[index]) {
              changedCount++;
              requested.add(index);
              seenValues.add((key, null));
            } else if (old.$2 != batch.ordinals[index]) {
              movedCount++;
              seenValues.add((key, batch.ordinals[index]));
            } else {
              seenValues.add((key, null));
            }
          }

          await _databaseAdapter.transaction((txn) async {
            for (final valueChunk in _warmChunks(seenValues, 300)) {
              final placeholders = List.filled(valueChunk.length, '(?, ?, ?)');
              final values = <Object?>[];
              for (final value in valueChunk) {
                values
                  ..add(sessionId)
                  ..add(value.$1)
                  ..add(value.$2);
              }
              await txn.rawInsert(
                'INSERT INTO import_seen(import_id, item_key, new_ord) '
                'VALUES ${placeholders.join(', ')}',
                values,
              );
            }
          });
          return requested;
        },
        onRows: (_, rows) async {
          if (rows.isEmpty) return;
          await _stageWarmRows(db, importId: sessionId, rows: rows);
        },
        onHeaders: (headers) {
          bytesTotal = headers.contentLength;
        },
        onProgress: (received, total, parsed) {
          bytesReceived = received;
          bytesTotal = total ?? bytesTotal;
          parsedItems = parsed;
          reporter.emit(
            CatalogImportProgress(
              phase: CatalogImportPhase.downloading,
              startedAt: reporter.startedAt,
              current: received,
              total: bytesTotal,
              parsedItems: parsed,
              currentOperation: 'downloading',
            ),
          );
          reporter.emit(
            CatalogImportProgress(
              phase: CatalogImportPhase.parsing,
              startedAt: reporter.startedAt,
              current: parsed,
              parsedItems: parsed,
              currentOperation: 'parsing',
            ),
          );
        },
      );
      reporter.onCancel(worker.cancel);
      final result = await worker.done;
      bytesReceived = result.bytesReceived;
      bytesTotal = result.headers.contentLength;
      parsedItems = result.itemsParsed;
      if (result.itemsParsed == 0 ||
          result.itemsRejected == result.itemsParsed) {
        throw FormatException('Playlist contains no valid entries.');
      }

      reporter.emit(
        CatalogImportProgress(
          phase: CatalogImportPhase.importing,
          startedAt: reporter.startedAt,
          current: parsedItems,
          total: parsedItems,
          parsedItems: parsedItems,
          stagedItems: newCount + changedCount,
          acceptedItems: parsedItems - result.itemsRejected,
          rejectedItems: result.itemsRejected,
          currentOperation: 'finalizing_diff',
        ),
      );
      final reconciliation = await _finalizeWarmImport(
        db,
        playlistId: playlistId,
        sessionId: sessionId,
        result: result,
        newCount: newCount,
        changedCount: changedCount,
        movedCount: movedCount,
        totalStopwatch: totalStopwatch,
      );
      reporter.emit(
        CatalogImportProgress(
          phase: CatalogImportPhase.indexing,
          startedAt: reporter.startedAt,
          current: parsedItems - result.itemsRejected,
          total: parsedItems - result.itemsRejected,
          indexedItems: newCount + changedCount,
          currentOperation: 'indexed',
        ),
      );
      return CatalogImportResult(
        playlistId: playlistId,
        importSessionId: sessionId,
        itemCount: reconciliation.itemCount,
        groupCount: reconciliation.groupCount,
        rejectedCount: result.itemsRejected,
        bodyHash: result.bodyHash,
        newCount: newCount,
        changedCount: changedCount,
        movedCount: movedCount,
        removedCount: reconciliation.removedCount,
      );
    } catch (error) {
      await worker?.cancel();
      await _cleanupWarmImport(
        db,
        sessionId: sessionId,
        error: error,
        bytesReceived: bytesReceived,
        bytesTotal: bytesTotal,
        parsedItems: parsedItems,
        newCount: newCount,
        changedCount: changedCount,
        movedCount: movedCount,
      );
      rethrow;
    }
  }

  Future<void> _stageWarmRows(
    DatabaseExecutor db, {
    required int importId,
    required List<CatalogImportRow> rows,
  }) => _databaseAdapter.transaction((txn) async {
    const columns = 19;
    for (final chunk in _warmChunks(rows, 40)) {
      final placeholders = List.filled(
        chunk.length,
        '(${List.filled(columns, '?').join(', ')})',
      );
      final values = <Object?>[];
      for (final row in chunk) {
        values
          ..add(importId)
          ..add(row.itemKey)
          ..add(row.contentHash)
          ..add(row.ordinal)
          ..add(_warmItemKindValue(row.itemKind))
          ..add(_warmGroupKindValue(row.groupKind))
          ..add(row.groupTitle)
          ..add(row.title)
          ..add(CatalogNormalizer.normalizeText(row.title))
          ..add(row.streamUrl)
          ..add(row.logoUrl)
          ..add(row.metadata['tvg-id'])
          ..add(row.metadata['tvg-name'])
          ..add(row.metadata['tvg-chno'])
          ..add(row.metadata['xui-id'])
          ..add(row.seriesKey)
          ..add(row.seriesTitle)
          ..add(row.seasonNumber)
          ..add(row.episodeNumber);
      }
      await txn.rawInsert(
        'INSERT INTO import_rows '
        '(import_id, item_key, content_hash, ord, kind, group_kind, group_title, '
        'title, sort_title, stream_url, logo_url, tvg_id, tvg_name, tvg_chno, '
        'xui_id, series_key, series_title, season_number, episode_number) '
        'VALUES ${placeholders.join(', ')}',
        values,
      );
    }
  });

  Future<({int itemCount, int groupCount, int removedCount})>
  _finalizeWarmImport(
    DatabaseExecutor db, {
    required String playlistId,
    required int sessionId,
    required CatalogImportWorkerResult result,
    required int newCount,
    required int changedCount,
    required int movedCount,
    required Stopwatch totalStopwatch,
  }) => _databaseAdapter.transaction((txn) async {
    await txn.update(
      'import_sessions',
      {
        'state': 'reconciling',
        'items_parsed': result.itemsParsed,
        'items_rejected': result.itemsRejected,
        'items_new': newCount,
        'items_changed': changedCount,
        'items_moved': movedCount,
        'bytes_received': result.bytesReceived,
        'bytes_total': result.headers.contentLength,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    final episodeChanges = await txn.rawQuery(
      'SELECT EXISTS(SELECT 1 FROM import_rows WHERE import_id = ? AND kind = 3) '
      'OR EXISTS(SELECT 1 FROM items i WHERE i.playlist_id = ? AND i.kind = 3 '
      'AND NOT EXISTS(SELECT 1 FROM import_seen s WHERE s.import_id = ? AND s.item_key = i.item_key)) '
      'AS has_episode_changes',
      [sessionId, playlistId, sessionId],
    );
    final rebuildSeries =
        (episodeChanges.single['has_episode_changes'] as int) == 1;
    final removedRows = result.itemsRejected == 0
        ? await txn.rawQuery(
            'SELECT COUNT(*) AS total FROM items i WHERE i.playlist_id = ? '
            'AND NOT EXISTS(SELECT 1 FROM import_seen s WHERE s.import_id = ? AND s.item_key = i.item_key)',
            [playlistId, sessionId],
          )
        : const <Map<String, Object?>>[];
    final removedCount = removedRows.isEmpty
        ? 0
        : (removedRows.single['total'] as num).toInt();

    await txn.rawInsert(
      '''
INSERT INTO groups(playlist_id, kind, title, sort_title, ord)
SELECT ?, group_kind, group_title, LOWER(TRIM(group_title)), MIN(ord)
FROM import_rows
WHERE import_id = ?
GROUP BY group_kind, group_title
ON CONFLICT(playlist_id, kind, title) DO UPDATE SET
  sort_title = excluded.sort_title,
  ord = excluded.ord
''',
      [playlistId, sessionId],
    );

    await txn.rawInsert(
      '''
INSERT INTO items_fts_queue(
  item_id, playlist_id, operation, old_title, priority, queued_at
)
SELECT i.id, i.playlist_id, 'upsert', i.title, r.kind, ?
FROM items i
JOIN import_rows r ON r.item_key = i.item_key AND r.import_id = ?
WHERE i.playlist_id = ?
ON CONFLICT(item_id) DO UPDATE SET
  operation = 'upsert',
  old_title = CASE
    WHEN items_fts_queue.operation = 'upsert'
      AND items_fts_queue.old_title IS NULL THEN NULL
    ELSE COALESCE(items_fts_queue.old_title, excluded.old_title)
  END,
  priority = excluded.priority,
  queued_at = excluded.queued_at
''',
      [DateTime.now().millisecondsSinceEpoch, sessionId, playlistId],
    );
    if (result.itemsRejected == 0) {
      await txn.rawInsert(
        '''
INSERT INTO items_fts_queue(
  item_id, playlist_id, operation, old_title, priority, queued_at
)
SELECT i.id, i.playlist_id, 'delete', i.title, i.kind, ?
FROM items i
WHERE i.playlist_id = ? AND NOT EXISTS(
  SELECT 1 FROM import_seen s WHERE s.import_id = ? AND s.item_key = i.item_key
)
ON CONFLICT(item_id) DO UPDATE SET
  operation = 'delete',
  old_title = CASE
    WHEN items_fts_queue.operation = 'upsert'
      AND items_fts_queue.old_title IS NULL THEN NULL
    ELSE COALESCE(items_fts_queue.old_title, excluded.old_title)
  END,
  priority = excluded.priority,
  queued_at = excluded.queued_at
''',
        [DateTime.now().millisecondsSinceEpoch, playlistId, sessionId],
      );
    }

    await txn.rawInsert(
      '''
INSERT INTO items(
  playlist_id, item_key, content_hash, ord, kind, group_id, title, sort_title,
  stream_url, logo_url, tvg_id, tvg_name, tvg_chno, xui_id, series_key,
  series_title, season_number, episode_number
)
SELECT ?, r.item_key, r.content_hash, r.ord, r.kind, g.id, r.title, r.sort_title,
  r.stream_url, r.logo_url, r.tvg_id, r.tvg_name, r.tvg_chno, r.xui_id,
  r.series_key, r.series_title, r.season_number, r.episode_number
FROM import_rows r
JOIN groups g ON g.playlist_id = ? AND g.kind = r.group_kind AND g.title = r.group_title
WHERE r.import_id = ?
ON CONFLICT(playlist_id, item_key) DO UPDATE SET
  content_hash = excluded.content_hash,
  ord = excluded.ord,
  kind = excluded.kind,
  group_id = excluded.group_id,
  title = excluded.title,
  sort_title = excluded.sort_title,
  stream_url = excluded.stream_url,
  logo_url = excluded.logo_url,
  tvg_id = excluded.tvg_id,
  tvg_name = excluded.tvg_name,
  tvg_chno = excluded.tvg_chno,
  xui_id = excluded.xui_id,
  series_key = excluded.series_key,
  series_title = excluded.series_title,
  season_number = excluded.season_number,
  episode_number = excluded.episode_number
''',
      [playlistId, playlistId, sessionId],
    );
    await txn.rawInsert(
      '''
INSERT INTO items_fts_queue(
  item_id, playlist_id, operation, old_title, priority, queued_at
)
SELECT i.id, i.playlist_id, 'upsert', NULL, i.kind, ?
FROM items i
JOIN import_rows r ON r.item_key = i.item_key AND r.import_id = ?
WHERE i.playlist_id = ?
ON CONFLICT(item_id) DO UPDATE SET
  operation = 'upsert',
  old_title = CASE
    WHEN items_fts_queue.operation = 'upsert'
      AND items_fts_queue.old_title IS NULL THEN NULL
    ELSE COALESCE(items_fts_queue.old_title, excluded.old_title)
  END,
  priority = excluded.priority,
  queued_at = excluded.queued_at
''',
      [DateTime.now().millisecondsSinceEpoch, sessionId, playlistId],
    );

    await txn.rawUpdate(
      '''
UPDATE items
SET ord = (
  SELECT s.new_ord FROM import_seen s
  WHERE s.import_id = ? AND s.item_key = items.item_key
)
WHERE playlist_id = ? AND item_key IN (
  SELECT item_key FROM import_seen WHERE import_id = ? AND new_ord IS NOT NULL
)
''',
      [sessionId, playlistId, sessionId],
    );

    if (result.itemsRejected == 0) {
      await txn.rawDelete(
        '''
DELETE FROM items WHERE playlist_id = ? AND NOT EXISTS (
  SELECT 1 FROM import_seen s WHERE s.import_id = ? AND s.item_key = items.item_key
)
''',
        [playlistId, sessionId],
      );
    }

    await txn.rawUpdate(
      '''
UPDATE groups SET item_count = (
  SELECT COUNT(*) FROM items i WHERE i.group_id = groups.id
) WHERE playlist_id = ?
''',
      [playlistId],
    );
    await txn.rawUpdate(
      '''
UPDATE groups SET ord = (
  SELECT COALESCE(MIN(i.ord), groups.ord) FROM items i WHERE i.group_id = groups.id
) WHERE playlist_id = ?
''',
      [playlistId],
    );
    await txn.delete(
      'groups',
      where: 'playlist_id = ? AND item_count = 0',
      whereArgs: [playlistId],
    );

    if (rebuildSeries) {
      await txn.delete(
        'series_v8',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.rawInsert(
        '''
INSERT INTO series_v8(
  series_key, playlist_id, group_id, title, sort_title, artwork_url,
  season_count, episode_count, ord
)
SELECT series_key, playlist_id, group_id, MIN(series_title),
  LOWER(TRIM(MIN(series_title))), NULL,
  COUNT(DISTINCT season_number), COUNT(*), MIN(ord)
FROM items
WHERE playlist_id = ? AND kind = 3 AND series_key IS NOT NULL
GROUP BY series_key, playlist_id, group_id
''',
        [playlistId],
      );
    }

    final counts = await txn.rawQuery(
      'SELECT (SELECT COUNT(*) FROM items WHERE playlist_id = ?) AS item_count, '
      '(SELECT COUNT(*) FROM groups WHERE playlist_id = ?) AS group_count',
      [playlistId, playlistId],
    );
    final itemCount = (counts.single['item_count'] as num).toInt();
    final groupCount = (counts.single['group_count'] as num).toInt();
    final finishedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
    await txn.update(
      'import_sessions',
      {
        'state': 'done',
        'finished_at': finishedAt,
        'items_removed': removedCount,
        'stage_timings': jsonEncode({
          'total': totalStopwatch.elapsedMilliseconds,
        }),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    await txn.update(
      'playlists',
      {
        'source_content_hash': result.bodyHash,
        'source_content_length': result.bytesReceived,
        'source_etag': result.headers.etag,
        'source_last_modified': result.headers.lastModified,
        'last_checked_at': finishedAt,
        'last_changed_at': finishedAt,
      },
      where: 'id = ?',
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
    return (
      itemCount: itemCount,
      groupCount: groupCount,
      removedCount: removedCount,
    );
  });

  Future<void> _cleanupWarmImport(
    DatabaseExecutor db, {
    required int sessionId,
    required Object error,
    required int bytesReceived,
    required int? bytesTotal,
    required int parsedItems,
    required int newCount,
    required int changedCount,
    required int movedCount,
  }) async {
    await _databaseAdapter.transaction((txn) async {
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
      await txn.update(
        'import_sessions',
        {
          'state': error is CatalogImportCancelledException
              ? 'cancelled'
              : 'failed',
          'finished_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          'bytes_received': bytesReceived,
          'bytes_total': bytesTotal,
          'items_parsed': parsedItems,
          'items_new': newCount,
          'items_changed': changedCount,
          'items_moved': movedCount,
          'error': redactSensitiveText(error.toString()),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  Iterable<List<T>> _warmChunks<T>(List<T> values, int size) sync* {
    for (var offset = 0; offset < values.length; offset += size) {
      final end = (offset + size).clamp(0, values.length);
      yield values.sublist(offset, end);
    }
  }

  int _warmItemKindValue(CatalogItemKind kind) => switch (kind) {
    CatalogItemKind.live => 1,
    CatalogItemKind.movie => 2,
    CatalogItemKind.episode => 3,
    CatalogItemKind.unknown => throw StateError('Unknown catalog item kind.'),
  };

  int _warmGroupKindValue(CatalogGroupKind kind) => switch (kind) {
    CatalogGroupKind.live => 1,
    CatalogGroupKind.movie => 2,
    CatalogGroupKind.series => 3,
  };
}
