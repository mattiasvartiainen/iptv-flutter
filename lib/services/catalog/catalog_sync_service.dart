import 'package:sqflite_common/sqlite_api.dart';

import '../storage/storage_contracts.dart';
import 'catalog_importer.dart';
import 'catalog_repository.dart';
import 'catalog_search_indexer.dart';
import 'id_identity.dart';

/// Decides when a playlist is imported and runs the v9 [CatalogImporter].
///
/// Concurrent loads for one playlist share a single import through the
/// importer's coordinator; search indexing is paused for the duration.
class CatalogSyncService implements CatalogRepository {
  CatalogSyncService({
    required DatabaseAdapter databaseAdapter,
    required CatalogImporter importer,
    required CatalogSearchIndexer searchIndexer,
  }) : _databaseAdapter = databaseAdapter,
       _importer = importer,
       _searchIndexer = searchIndexer;

  final DatabaseAdapter _databaseAdapter;
  final CatalogImporter _importer;
  final CatalogSearchIndexer _searchIndexer;

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
    final cachedItems = await _countItems(db, resolvedPlaylistId);
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
    final imported = await _searchIndexer.whilePaused(
      resolvedPlaylistId,
      () async {
        final result = await _importer.importPlaylist(
          playlistId: resolvedPlaylistId,
          playlistUrl: playlistUrl,
          onProgress: onProgress,
        );
        await _markRefreshSuccess(
          db,
          playlistId: resolvedPlaylistId,
          completedAt: DateTime.now().toUtc(),
        );
        return result;
      },
    );
    _searchIndexer.scheduleIndexing(resolvedPlaylistId);
    return CatalogLoadResult(
      playlistId: imported.playlistId,
      itemCount: imported.itemCount,
    );
  }

  Future<void> cancelImport(String playlistId) => _importer.cancel(playlistId);

  /// Aborts sessions left `running`/`reconciling` by a previous process,
  /// discarding a partial cold catalog and any warm-refresh scratch rows.
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
      final isColdImport = tier == 'cold_import';
      final isWarmImport = tier == 'row_diff';
      await _databaseAdapter.transaction((txn) async {
        if (isColdImport) {
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
        } else if (isWarmImport) {
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

  Future<int> _countItems(DatabaseExecutor db, String playlistId) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS item_count FROM items WHERE playlist_id = ?',
      [playlistId],
    );
    return (rows.single['item_count'] as num).toInt();
  }

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
