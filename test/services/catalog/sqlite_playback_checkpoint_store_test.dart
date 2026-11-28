import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/models/library_identity.dart';
import 'package:iptv_flutter/services/catalog/sqlite_playback_checkpoint_store.dart';
import 'package:iptv_flutter/services/playback/playback_progress_foundation.dart';

import '../../support/database_adapter.dart';

void main() {
  test('checkpoints update one session history row atomically', () async {
    final db = createTestDatabaseAdapter(
      fileName: 'checkpoint_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    addTearDown(db.close);
    final store = SqlitePlaybackCheckpointStore(db);
    final writer = store.newSession();
    const identity = LibraryIdentity(
      playlistId: 'p',
      profileId: 'a',
      itemKey: 1,
    );
    PlaybackCheckpoint checkpoint(int seconds, bool completed) =>
        PlaybackCheckpoint(
          identity: identity,
          position: Duration(seconds: seconds),
          duration: const Duration(seconds: 100),
          completed: completed,
        );
    await writer.write(checkpoint(30, false));
    await writer.write(checkpoint(90, true));
    final database = await db.database;
    final progress = await database.query('playback_progress_v8');
    final history = await database.query('watch_history_v8');
    expect(progress.single['position_ms'], 90000);
    expect(history.single['position_ms'], 90000);
    expect(history.single['completed'], 1);
    await database.delete('watch_history_v8');
    await expectLater(writer.write(checkpoint(95, true)), throwsStateError);
    expect(
      (await database.query('playback_progress_v8')).single['position_ms'],
      90000,
    );
  });
}
