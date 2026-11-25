import 'package:sqflite_common/sqlite_api.dart';

import 'storage_contracts.dart';

class CatalogSortV13Migration implements StorageMigration {
  const CatalogSortV13Migration();

  @override
  int get version => 13;

  @override
  String get name => 'catalog_sort_v13';

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.rawUpdate('''
UPDATE series_v8 SET ord = COALESCE(
  (SELECT MIN(i.ord) FROM items i WHERE i.series_key = series_v8.series_key),
  ord
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_series_v8_playlist_ord '
      'ON series_v8(playlist_id, ord, series_key)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_series_v8_group_ord '
      'ON series_v8(group_id, ord, series_key)',
    );
  }
}
