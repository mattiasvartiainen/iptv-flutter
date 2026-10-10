import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../security/url_redaction.dart';
import '../storage/storage_contracts.dart';
import 'catalog_import_coordinator.dart';
import 'catalog_import_progress.dart';
import 'catalog_import_protocol.dart' hide CatalogImportProgressCallback;
import 'catalog_import_worker.dart';
import 'catalog_normalizer.dart';
import 'catalog_query.dart';

part 'catalog_importer_warm.dart';

class CatalogImportResult {
  const CatalogImportResult({
    required this.playlistId,
    required this.importSessionId,
    required this.itemCount,
    required this.groupCount,
    required this.rejectedCount,
    required this.bodyHash,
    this.newCount = 0,
    this.changedCount = 0,
    this.movedCount = 0,
    this.removedCount = 0,
  });

  final String playlistId;
  final int importSessionId;
  final int itemCount;
  final int groupCount;
  final int rejectedCount;
  final int bodyHash;
  final int newCount;
  final int changedCount;
  final int movedCount;
  final int removedCount;
}

class CatalogImporter {
  CatalogImporter({
    required DatabaseAdapter databaseAdapter,
    CatalogImportCoordinator? coordinator,
  }) : _databaseAdapter = databaseAdapter,
       _coordinator = coordinator ?? CatalogImportCoordinator();

  final DatabaseAdapter _databaseAdapter;
  final CatalogImportCoordinator _coordinator;

  Future<void> cancel(String playlistId) => _coordinator.cancel(playlistId);

  Future<CatalogImportResult> importPlaylist({
    required String playlistId,
    required String playlistUrl,
    CatalogImportProgressCallback? onProgress,
  }) => _coordinator.run<CatalogImportResult>(
    playlistId: playlistId,
    onProgress: onProgress,
    operation: (reporter) => _importPlaylist(
      playlistId: playlistId,
      playlistUrl: playlistUrl,
      reporter: reporter,
    ),
  );

  Future<CatalogImportResult> _importPlaylist({
    required String playlistId,
    required String playlistUrl,
    required CatalogImportReporter reporter,
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM items WHERE playlist_id = ?',
      [playlistId],
    );
    final count = (rows.single['total'] as num).toInt();
    if (count == 0) {
      return _importCold(
        playlistId: playlistId,
        playlistUrl: playlistUrl,
        reporter: reporter,
      );
    }
    return _importWarm(
      playlistId: playlistId,
      playlistUrl: playlistUrl,
      reporter: reporter,
    );
  }

  Future<CatalogImportResult> importCold({
    required String playlistId,
    required String playlistUrl,
    CatalogImportProgressCallback? onProgress,
  }) => _coordinator.run<CatalogImportResult>(
    playlistId: playlistId,
    onProgress: onProgress,
    operation: (reporter) => _importCold(
      playlistId: playlistId,
      playlistUrl: playlistUrl,
      reporter: reporter,
    ),
  );

  Future<CatalogImportResult> _importCold({
    required String playlistId,
    required String playlistUrl,
    required CatalogImportReporter reporter,
  }) async {
    final db = await _databaseAdapter.database;
    final existingRows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM items WHERE playlist_id = ?',
      [playlistId],
    );
    final existingCount = (existingRows.single['total'] as num).toInt();
    if (existingCount != 0) {
      throw StateError(
        'Cold catalog import requires an empty catalog; found $existingCount existing items.',
      );
    }

    final totalStopwatch = Stopwatch()..start();
    final sessionId = await db.insert('import_sessions', {
      'playlist_id': playlistId,
      'started_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      'state': 'running',
      'tier': 'cold_import',
    });
    reporter.attachSession(sessionId);

    var bytesReceived = 0;
    int? bytesTotal;
    var parsedItems = 0;
    var acceptedItems = 0;
    var lastProgressWrite = DateTime.fromMillisecondsSinceEpoch(0);
    CatalogImportWorkerHandle? worker;

    Future<void> updateSessionProgress({bool force = false}) async {
      final now = DateTime.now();
      if (!force &&
          now.difference(lastProgressWrite) < const Duration(seconds: 1)) {
        return;
      }
      lastProgressWrite = now;
      await db.update(
        'import_sessions',
        {
          'bytes_received': bytesReceived,
          'bytes_total': bytesTotal,
          'items_parsed': parsedItems,
          'items_new': acceptedItems,
        },
        where: 'id = ? AND state IN (?, ?)',
        whereArgs: [sessionId, 'running', 'reconciling'],
      );
    }

    try {
      reporter.emit(
        CatalogImportProgress(
          phase: CatalogImportPhase.downloading,
          startedAt: reporter.startedAt,
          current: 0,
          currentOperation: 'downloading',
        ),
      );
      worker = await CatalogImportWorker.start(
        playlistId: playlistId,
        playlistUrl: playlistUrl,
        selectRows: (batch) async =>
            List<int>.generate(batch.itemKeys.length, (index) => index),
        onRows: (_, rows) async {
          if (rows.isEmpty) return;
          await _insertBatch(db, playlistId: playlistId, rows: rows);
          acceptedItems += rows.length;
          reporter.emit(
            CatalogImportProgress(
              phase: CatalogImportPhase.importing,
              startedAt: reporter.startedAt,
              current: acceptedItems,
              parsedItems: parsedItems,
              stagedItems: acceptedItems,
              acceptedItems: acceptedItems,
              currentOperation: 'writing_items',
            ),
          );
          await updateSessionProgress(force: true);
        },
        onHeaders: (headers) {
          bytesTotal = headers.contentLength;
          reporter.emit(
            CatalogImportProgress(
              phase: CatalogImportPhase.downloading,
              startedAt: reporter.startedAt,
              current: 0,
              total: bytesTotal,
              currentOperation: 'response_headers',
            ),
          );
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
          unawaited(updateSessionProgress());
        },
      );
      reporter.onCancel(worker.cancel);
      final result = await worker.done;
      bytesReceived = result.bytesReceived;
      parsedItems = result.itemsParsed;
      bytesTotal = result.headers.contentLength;
      if (acceptedItems == 0) {
        throw FormatException(
          result.itemsParsed == 0
              ? 'Playlist contains no playable entries.'
              : 'Playlist contains no valid entries.',
        );
      }

      reporter.emit(
        CatalogImportProgress(
          phase: CatalogImportPhase.importing,
          startedAt: reporter.startedAt,
          current: acceptedItems,
          total: acceptedItems,
          parsedItems: parsedItems,
          stagedItems: acceptedItems,
          acceptedItems: acceptedItems,
          rejectedItems: result.itemsRejected,
          currentOperation: 'finalizing',
        ),
      );
      final groupCount = await _finalizeColdImport(
        db,
        playlistId: playlistId,
        sessionId: sessionId,
        acceptedItems: acceptedItems,
        result: result,
        totalStopwatch: totalStopwatch,
      );
      reporter.emit(
        CatalogImportProgress(
          phase: CatalogImportPhase.indexing,
          startedAt: reporter.startedAt,
          current: 0,
          total: acceptedItems,
          indexedItems: 0,
          currentOperation: 'queued',
          message: 'Search indexing is queued.',
        ),
      );
      return CatalogImportResult(
        playlistId: playlistId,
        importSessionId: sessionId,
        itemCount: acceptedItems,
        groupCount: groupCount,
        rejectedCount: result.itemsRejected,
        bodyHash: result.bodyHash,
      );
    } catch (error) {
      await worker?.cancel();
      await _cleanupFailedColdImport(
        db,
        playlistId: playlistId,
        sessionId: sessionId,
        error: error,
        bytesReceived: bytesReceived,
        bytesTotal: bytesTotal,
        parsedItems: parsedItems,
        acceptedItems: acceptedItems,
      );
      rethrow;
    }
  }

  Future<void> _insertBatch(
    DatabaseExecutor db, {
    required String playlistId,
    required List<CatalogImportRow> rows,
  }) async {
    await _databaseAdapter.transaction((txn) async {
      final groupKinds = <(int, String)>{};
      final firstOrdinalByGroup = <(int, String), int>{};
      for (final row in rows) {
        final group = (_groupKindValue(row.groupKind), row.groupTitle);
        groupKinds.add(group);
        firstOrdinalByGroup.putIfAbsent(group, () => row.ordinal);
      }

      for (final chunk in _chunks(groupKinds.toList(), 100)) {
        final values = <Object?>[];
        final placeholders = <String>[];
        for (final group in chunk) {
          placeholders.add('(?, ?, ?, ?, ?)');
          values
            ..add(playlistId)
            ..add(group.$1)
            ..add(group.$2)
            ..add(CatalogNormalizer.normalizeText(group.$2))
            ..add(firstOrdinalByGroup[group]);
        }
        await txn.rawInsert(
          'INSERT OR IGNORE INTO groups '
          '(playlist_id, kind, title, sort_title, ord) VALUES ${placeholders.join(', ')}',
          values,
        );
      }

      final groupIds = <(int, String), int>{};
      final groupList = groupKinds.toList(growable: false);
      for (final chunk in _chunks(groupList, 400)) {
        final predicates = List.filled(
          chunk.length,
          '(kind = ? AND title = ?)',
        );
        final args = <Object?>[playlistId];
        for (final group in chunk) {
          args
            ..add(group.$1)
            ..add(group.$2);
        }
        final found = await txn.rawQuery(
          'SELECT id, kind, title FROM groups WHERE playlist_id = ? '
          'AND (${predicates.join(' OR ')})',
          args,
        );
        for (final row in found) {
          groupIds[(row['kind']! as int, row['title']! as String)] =
              row['id']! as int;
        }
      }

      for (final chunk in _chunks(rows, 40)) {
        final values = <Object?>[];
        final placeholders = <String>[];
        for (final row in chunk) {
          placeholders.add('(${List.filled(18, '?').join(', ')})');
          values
            ..add(playlistId)
            ..add(row.itemKey)
            ..add(row.contentHash)
            ..add(row.ordinal)
            ..add(_itemKindValue(row.itemKind))
            ..add(groupIds[(_groupKindValue(row.groupKind), row.groupTitle)])
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
          'INSERT INTO items '
          '(playlist_id, item_key, content_hash, ord, kind, group_id, title, '
          'sort_title, stream_url, logo_url, tvg_id, tvg_name, tvg_chno, xui_id, '
          'series_key, series_title, season_number, episode_number) '
          'VALUES ${placeholders.join(', ')}',
          values,
        );
      }
      final itemKeys = rows.map((row) => row.itemKey).toList(growable: false);
      for (final keyChunk in _chunks(itemKeys, 500)) {
        await txn.rawInsert(
          '''
INSERT INTO items_fts_queue(
  item_id, playlist_id, operation, old_title, priority, queued_at
)
SELECT id, playlist_id, 'upsert', NULL, kind, ?
FROM items WHERE playlist_id = ?
  AND item_key IN (${List.filled(keyChunk.length, '?').join(', ')})
ON CONFLICT(item_id) DO UPDATE SET
  operation = 'upsert',
  priority = excluded.priority,
  queued_at = excluded.queued_at
''',
          [DateTime.now().millisecondsSinceEpoch, playlistId, ...keyChunk],
        );
      }
    });
  }

  Future<int> _finalizeColdImport(
    DatabaseExecutor db, {
    required String playlistId,
    required int sessionId,
    required int acceptedItems,
    required CatalogImportWorkerResult result,
    required Stopwatch totalStopwatch,
  }) => _databaseAdapter.transaction((txn) async {
    await txn.update(
      'import_sessions',
      {
        'state': 'reconciling',
        'items_parsed': result.itemsParsed,
        'items_rejected': result.itemsRejected,
        'items_new': acceptedItems,
        'items_changed': 0,
        'items_moved': 0,
        'items_removed': 0,
        'bytes_received': result.bytesReceived,
        'bytes_total': result.headers.contentLength,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    await txn.rawUpdate(
      '''
UPDATE groups
SET item_count = (
  SELECT COUNT(*) FROM items i WHERE i.group_id = groups.id
)
WHERE playlist_id = ?
''',
      [playlistId],
    );
    await txn.delete(
      'series_v8',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    await txn.rawInsert(
      '''
INSERT INTO series_v8 (
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
    final groups = await txn.rawQuery(
      'SELECT COUNT(*) AS group_count FROM groups WHERE playlist_id = ?',
      [playlistId],
    );
    final groupCount = (groups.single['group_count'] as num).toInt();
    await txn.update(
      'import_sessions',
      {
        'state': 'done',
        'finished_at': DateTime.now().toUtc().millisecondsSinceEpoch,
        'stage_timings': jsonEncode({
          'total': totalStopwatch.elapsedMilliseconds,
        }),
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    return groupCount;
  });

  Future<void> _cleanupFailedColdImport(
    DatabaseExecutor db, {
    required String playlistId,
    required int sessionId,
    required Object error,
    required int bytesReceived,
    required int? bytesTotal,
    required int parsedItems,
    required int acceptedItems,
  }) async {
    await _databaseAdapter.transaction((txn) async {
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
          'items_new': acceptedItems,
          'error': redactSensitiveText(error.toString()),
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    });
  }

  static int _itemKindValue(CatalogItemKind kind) => switch (kind) {
    CatalogItemKind.live => 1,
    CatalogItemKind.movie => 2,
    CatalogItemKind.episode => 3,
    CatalogItemKind.unknown => throw StateError('Unknown catalog item kind.'),
  };

  static int _groupKindValue(CatalogGroupKind kind) => switch (kind) {
    CatalogGroupKind.live => 1,
    CatalogGroupKind.movie => 2,
    CatalogGroupKind.series => 3,
  };

  static Iterable<List<T>> _chunks<T>(List<T> values, int size) sync* {
    for (var offset = 0; offset < values.length; offset += size) {
      final end = (offset + size).clamp(0, values.length);
      yield values.sublist(offset, end);
    }
  }
}
