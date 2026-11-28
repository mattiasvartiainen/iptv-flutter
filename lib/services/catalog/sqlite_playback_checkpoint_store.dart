import 'package:sqflite_common/sqlite_api.dart';

import '../playback/playback_progress_foundation.dart';
import '../storage/storage_contracts.dart';

/// Stores a playback session's progress and history in one transaction.
class SqlitePlaybackCheckpointStore implements PlaybackCheckpointStore {
  SqlitePlaybackCheckpointStore(this._database);

  final DatabaseAdapter _database;

  @override
  PlaybackCheckpointWriter newSession() => _SqliteCheckpointWriter(_database);
}

class _SqliteCheckpointWriter implements PlaybackCheckpointWriter {
  _SqliteCheckpointWriter(this._database);

  final DatabaseAdapter _database;
  int? _historyId;

  @override
  Future<void> write(PlaybackCheckpoint checkpoint) async {
    final identity = checkpoint.identity;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final row = <String, Object?>{
      'profile_id': identity.profileId,
      'playlist_id': identity.playlistId,
      'item_key': identity.itemKey,
      'position_ms': checkpoint.position.inMilliseconds,
      'duration_ms': checkpoint.duration?.inMilliseconds,
    };
    final historyId = await _database.transaction((txn) async {
      await txn.insert('playback_progress_v8', {
        ...row,
        'updated_at': timestamp,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      final history = {
        ...row,
        'watched_at': timestamp,
        'completed': checkpoint.completed ? 1 : 0,
      };
      final id = _historyId;
      if (id == null) return txn.insert('watch_history_v8', history);
      final count = await txn.update(
        'watch_history_v8',
        history,
        where: 'id = ? AND profile_id = ? AND playlist_id = ? AND item_key = ?',
        whereArgs: [
          id,
          identity.profileId,
          identity.playlistId,
          identity.itemKey,
        ],
      );
      if (count != 1) {
        throw StateError('Playback history checkpoint no longer exists.');
      }
      return id;
    });
    _historyId = historyId;
  }
}
