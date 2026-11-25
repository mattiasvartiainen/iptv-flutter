import 'package:sqflite_common/sqlite_api.dart';

import 'storage_contracts.dart';

class SeriesMembershipV17Migration implements StorageMigration {
  const SeriesMembershipV17Migration();

  @override
  int get version => 17;

  @override
  String get name => 'series_membership_v17';

  @override
  Future<void> up(DatabaseExecutor db) => db.execute('''
CREATE INDEX idx_items_series_membership ON items(series_key, id)
WHERE kind = 3 AND series_key IS NOT NULL
''');
}
