import 'package:sqflite_common/sqlite_api.dart';

import 'storage_contracts.dart';

class SourceVerificationV12Migration implements StorageMigration {
  const SourceVerificationV12Migration();

  @override
  int get version => 12;

  @override
  String get name => 'source_verification_v12';

  @override
  Future<void> up(DatabaseExecutor db) async {
    for (final statement in const [
      'ALTER TABLE playlists ADD COLUMN source_revision INTEGER NOT NULL '
          'DEFAULT 0 CHECK (source_revision >= 0)',
      'ALTER TABLE playlists ADD COLUMN source_verification TEXT '
          'CHECK (source_verification IN (\'unchecked\', \'checking\', '
          '\'verified\', \'invalidCredentials\', \'unsupported\', '
          '\'temporarilyUnavailable\'))',
      'ALTER TABLE playlists ADD COLUMN source_account_state TEXT '
          'CHECK (source_account_state IN (\'active\', \'expired\', '
          '\'disabled\', \'banned\', \'unknown\'))',
      'ALTER TABLE playlists ADD COLUMN source_checked_at TEXT',
      'ALTER TABLE playlists ADD COLUMN source_api_enabled INTEGER '
          'CHECK (source_api_enabled IN (0, 1))',
      'CREATE TABLE source_secret_journal ('
          'secret_key TEXT PRIMARY KEY NOT NULL)',
    ]) {
      await db.execute(statement);
    }
  }
}
