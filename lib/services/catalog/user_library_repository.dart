import 'package:sqflite_common/sqlite_api.dart';

import '../storage/storage_contracts.dart';
import 'catalog_item_sql.dart';
import 'catalog_query.dart';

/// Per-profile favorites, playback progress and watch history.
///
/// Rows are keyed by `(playlist_id, item_key)` rather than item row ids, so
/// they survive catalog refreshes that renumber or temporarily remove items.
abstract interface class UserLibraryRepository {
  Future<void> setFavorite({
    required String playlistId,
    required int itemKey,
    required bool favorite,
    String profileId = 'default',
  });

  Future<List<CatalogItemSummary>> favoriteItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kCatalogPageSize,
  });

  Future<void> savePlaybackProgress({
    required String playlistId,
    required int itemKey,
    required int positionMs,
    int? durationMs,
    String profileId = 'default',
  });

  Future<CatalogPlaybackProgress?> playbackProgress({
    required String playlistId,
    required int itemKey,
    String profileId = 'default',
  });

  Future<void> recordWatchHistory({
    required String playlistId,
    required int itemKey,
    required bool completed,
    int? positionMs,
    int? durationMs,
    String profileId = 'default',
  });

  Future<List<CatalogItemSummary>> recentlyWatchedItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kHomePreviewCount,
  });
}

class SqliteUserLibraryRepository implements UserLibraryRepository {
  SqliteUserLibraryRepository({required DatabaseAdapter databaseAdapter})
    : _databaseAdapter = databaseAdapter;

  final DatabaseAdapter _databaseAdapter;

  @override
  Future<void> setFavorite({
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

  @override
  Future<List<CatalogItemSummary>> favoriteItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kCatalogPageSize,
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT $catalogItemSummaryColumns FROM favorites_v8 f '
      'JOIN items m ON m.playlist_id = f.playlist_id AND m.item_key = f.item_key '
      'JOIN groups g ON g.id = m.group_id '
      'WHERE f.playlist_id = ? AND f.profile_id = ? '
      'ORDER BY f.created_at DESC, m.id LIMIT ?',
      [playlistId, profileId, limit],
    );
    return rows.map(CatalogItemSummary.fromRow).toList(growable: false);
  }

  @override
  Future<void> savePlaybackProgress({
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

  @override
  Future<CatalogPlaybackProgress?> playbackProgress({
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

  @override
  Future<void> recordWatchHistory({
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

  @override
  Future<List<CatalogItemSummary>> recentlyWatchedItems({
    required String playlistId,
    String profileId = 'default',
    int limit = kHomePreviewCount,
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT $catalogItemSummaryColumns FROM watch_history_v8 h '
      'JOIN items m ON m.playlist_id = h.playlist_id AND m.item_key = h.item_key '
      'JOIN groups g ON g.id = m.group_id '
      'WHERE h.playlist_id = ? AND h.profile_id = ? '
      'GROUP BY m.id ORDER BY MAX(h.watched_at) DESC LIMIT ?',
      [playlistId, profileId, limit],
    );
    return rows.map(CatalogItemSummary.fromRow).toList(growable: false);
  }
}
