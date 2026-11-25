import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';

import '../../support/database_adapter.dart';

void main() {
  late SqfliteDatabaseAdapter adapter;
  setUp(() {
    adapter = createTestDatabaseAdapter(fileName: 'membership_${DateTime.now().microsecondsSinceEpoch}.sqlite');
  });
  tearDown(() async {
    final path = (await adapter.database).path;
    await adapter.close();
    await testDatabaseFactory.deleteDatabase(path);
  });
  test('membership samples and subsequent pages use index without sorting', () async {
    final db = await adapter.database;
    for (final cursor in [null, 100]) {
      final rows = await db.rawQuery('''
EXPLAIN QUERY PLAN SELECT id, stream_url FROM items
WHERE playlist_id = ? AND series_key = ? AND kind = 3
${cursor == null ? '' : 'AND id > ?'}
ORDER BY id LIMIT 100
''', ['p', 7, ?cursor]);
      final plan = rows.map((row) => row['detail']).join(' ');
      expect(plan, contains('SEARCH items USING INDEX idx_items_series_membership'));
      expect(plan, isNot(contains('TEMP B-TREE')));
      if (cursor != null) expect(plan, contains('id>'));
    }
  });
  test('v16 upgrade creates partial episode index without altering catalog or cache', () async {
    final db = await adapter.database;
    final schema = await db.query('sqlite_master', where: "type = 'table'");
    await db.execute('DROP INDEX idx_items_series_membership');
    await db.delete('schema_migrations', where: 'version = 17');
    await db.execute('PRAGMA user_version = 16');
    await adapter.close();
    final upgraded = await adapter.database;
    expect((await upgraded.rawQuery('PRAGMA user_version')).single.values.single, 17);
    expect(await upgraded.query('sqlite_master', where: "type = 'table'"), schema);
    final index = (await upgraded.query('sqlite_master', where: "name = 'idx_items_series_membership'")).single;
    expect(index['sql'], contains('WHERE kind = 3 AND series_key IS NOT NULL'));
  });
}
