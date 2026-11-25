import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/storage/catalog_sort_v13_migration.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/movie_metadata_v14_migration.dart';
import 'package:iptv_flutter/services/storage/series_membership_v17_migration.dart';
import 'package:iptv_flutter/services/storage/series_metadata_v15_migration.dart';
import 'package:iptv_flutter/services/storage/series_metadata_v16_migration.dart';
import 'package:iptv_flutter/services/storage/source_verification_v12_migration.dart';
import 'package:iptv_flutter/services/storage/storage_contracts.dart';
import 'package:iptv_flutter/services/storage/storage_migrations.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../support/database_adapter.dart';

// Historical fixtures must not inherit future migrations from the default adapter.
const _history = <StorageMigration>[
  InitialSchemaV1Migration(),
  PlaylistImportMetricsV2Migration(),
  PlaylistScopedIdentityV3Migration(),
  MediaItemXuiIdV4Migration(),
  PaginatedCatalogV5Migration(),
  ImportStagingSqlReconcileV6Migration(),
  ImportPerformanceV7Migration(),
  ImportSessionsV8Migration(),
  CatalogImportV9Migration(),
  CatalogSearchV10Migration(),
  DropLegacyCatalogV11Migration(),
  SourceVerificationV12Migration(),
  CatalogSortV13Migration(),
  MovieMetadataV14Migration(),
  SeriesMetadataV15Migration(),
  SeriesMetadataV16Migration(),
  SeriesMembershipV17Migration(),
];

void main() {
  late List<Map<String, Object?>> expectedSchema;
  late List<Map<String, Object?>> expectedLedger;

  SqfliteDatabaseAdapter temporaryAdapter({
    List<StorageMigration>? migrations,
    String? fileName,
  }) {
    final adapter = createTestDatabaseAdapter(
      fileName:
          fileName ??
          'migration_matrix_${DateTime.now().microsecondsSinceEpoch}.sqlite',
      migrations: migrations,
    );
    addTearDown(adapter.close);
    return adapter;
  }

  setUpAll(() async {
    final adapter = createTestDatabaseAdapter(
      fileName:
          'migration_reference_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    final db = await adapter.database;
    try {
      expectedSchema = await _schema(db);
      expectedLedger = await db.query(
        'schema_migrations',
        columns: ['version', 'name'],
        orderBy: 'version',
      );
      expect(
        expectedLedger,
        [
          for (final migration in _history)
            {'version': migration.version, 'name': migration.name},
        ],
        reason:
            'Add new migrations to the historical matrix when production registration changes.',
      );
      expect(
        (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
        'ok',
      );
    } finally {
      final path = db.path;
      await adapter.close();
      await testDatabaseFactory.deleteDatabase(path);
    }
  });

  for (final migration in _history) {
    final version = migration.version;
    test(
      'persisted v$version upgrades to current schema, preserves data and reopens unchanged',
      () async {
        final historical = temporaryAdapter(
          migrations: _history
              .where((entry) => entry.version <= version)
              .toList(),
        );
        final oldDb = await historical.database;
        addTearDown(() async {
          await historical.close();
          await testDatabaseFactory.deleteDatabase(oldDb.path);
        });
        expect(
          (await oldDb.rawQuery('PRAGMA user_version')).single.values.single,
          version,
        );
        await _seed(oldDb, version);
        final preserved = <String, List<Map<String, Object?>>>{
          for (final table in [
            'profiles',
            'profile_settings',
            'app_settings',
            'playlist_settings',
            if (version >= 9) ...['items', 'groups', 'series_v8'],
            if (version >= 14) ...[
              'movie_metadata_cache',
              'movie_provider_bindings',
            ],
            if (version >= 15) 'series_metadata_cache',
          ])
            table: await oldDb.query(table),
        };
        final playlist = (await oldDb.query('playlists')).single;
        final oldLedger = await oldDb.query(
          'schema_migrations',
          orderBy: 'version',
        );
        await historical.close();

        final upgraded = temporaryAdapter(fileName: historical.fileName);
        final db = await upgraded.database;
        expect(await _schema(db), expectedSchema);
        expect(
          await db.query(
            'schema_migrations',
            columns: ['version', 'name'],
            orderBy: 'version',
          ),
          expectedLedger,
        );
        expect(
          await db.query(
            'schema_migrations',
            where: 'version <= ?',
            whereArgs: [version],
            orderBy: 'version',
          ),
          oldLedger,
          reason: 'Already applied migrations must not run again.',
        );
        expect(
          (await db.rawQuery('PRAGMA user_version')).single.values.single,
          _history.last.version,
        );
        expect(
          (await db.query(
            'schema_meta',
            where: "key = 'schema_version'",
          )).single['value'],
          '${_history.last.version}',
        );
        final upgradedPlaylist = (await db.query('playlists')).single;
        for (final entry in playlist.entries) {
          if (entry.key == 'search_index_dirty' && version < 7) {
            expect(
              upgradedPlaylist[entry.key],
              1,
              reason:
                  'v7 deliberately marks the replaced search index for rebuilding.',
            );
            continue;
          }
          expect(
            upgradedPlaylist[entry.key],
            entry.value,
            reason: 'Playlist field ${entry.key}',
          );
        }
        for (final entry in preserved.entries) {
          expect(
            await db.query(
              entry.key,
              columns: entry.value.isEmpty
                  ? null
                  : entry.value.first.keys.toList(),
            ),
            entry.value,
            reason: '${entry.key} data must survive.',
          );
        }
        expect(
          (await db.rawQuery('PRAGMA integrity_check')).single.values.single,
          'ok',
        );
        expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
        await db.execute(
          "INSERT INTO items_fts(items_fts, rank) VALUES ('integrity-check', 1)",
        );

        final ledger = await db.query('schema_migrations', orderBy: 'version');
        await upgraded.close();
        final reopened = await upgraded.database;
        expect(await _schema(reopened), expectedSchema);
        expect(
          await reopened.query('schema_migrations', orderBy: 'version'),
          ledger,
        );
      },
    );
  }

  test(
    'failed SQL upgrade rolls back schema/data/version and can be retried',
    () async {
      final original = temporaryAdapter();
      final db = await original.database;
      await _seed(db, _history.last.version);
      final playlist = await db.query('playlists');
      final ledger = await db.query('schema_migrations', orderBy: 'version');
      final path = db.path;
      await original.close();
      final failing = createTestDatabaseAdapter(
        fileName: original.fileName,
        migrations: [..._history, const _ProbeMigration(fail: true)],
      );
      try {
        await expectLater(failing.database, throwsA(isA<DatabaseException>()));
      } finally {
        await failing.close();
      }
      final rolledBack = await original.database;
      expect(await _schema(rolledBack), expectedSchema);
      expect(await rolledBack.query('playlists'), playlist);
      expect(
        await rolledBack.query('schema_migrations', orderBy: 'version'),
        ledger,
      );
      expect(
        (await rolledBack.rawQuery('PRAGMA user_version')).single.values.single,
        _history.last.version,
      );
      expect(
        (await rolledBack.query(
          'schema_meta',
          where: "key = 'schema_version'",
        )).single['value'],
        '${_history.last.version}',
      );
      await original.close();

      final retry = createTestDatabaseAdapter(
        fileName: original.fileName,
        migrations: [..._history, const _ProbeMigration(fail: false)],
      );
      try {
        final recovered = await retry.database;
        expect(await recovered.query('migration_probe'), isEmpty);
        expect(await recovered.query('playlists'), playlist);
        expect(
          (await recovered.rawQuery(
            'PRAGMA user_version',
          )).single.values.single,
          _history.last.version + 1,
        );
        expect(
          (await recovered.rawQuery(
            'PRAGMA integrity_check',
          )).single.values.single,
          'ok',
        );
      } finally {
        await retry.close();
        await testDatabaseFactory.deleteDatabase(path);
      }
    },
  );
}

Future<List<Map<String, Object?>>> _schema(Database db) => db.rawQuery(
  "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name",
);

Future<void> _seed(Database db, int version) async {
  const timestamp = '2026-11-25T00:00:00Z';
  await db.update('profiles', {
    'name': 'Fixture profile',
  }, where: "id = 'default'");
  await db.update('profile_settings', {
    'audio_language': 'sv',
    'autoplay_enabled': 0,
  }, where: "profile_id = 'default'");
  await db.update('app_settings', {
    'value': 'false',
  }, where: "key = 'animations_enabled'");
  await db.insert('playlists', {
    'id': 'p',
    'name': 'Fixture playlist',
    'secure_storage_key': 'fixture-secret-reference',
    'created_at': timestamp,
    'updated_at': timestamp,
    if (version >= 12) ...{
      'source_revision': 3,
      'source_verification': 'verified',
      'source_api_enabled': 1,
    },
  });
  await db.insert('playlist_settings', {
    'playlist_id': 'p',
    'refresh_mode': 'manual',
    'refresh_enabled': 0,
    'updated_at': timestamp,
  });
  if (version < 9) return;
  await db.insert('groups', {
    'id': 1,
    'playlist_id': 'p',
    'kind': 3,
    'title': 'Series',
    'sort_title': 'series',
    'ord': 0,
  });
  await db.insert('series_v8', {
    'series_key': 7,
    'playlist_id': 'p',
    'group_id': 1,
    'title': 'Fixture show',
    'sort_title': 'fixture show',
    'ord': 0,
    'episode_count': 1,
    'season_count': 1,
  });
  for (final id in [42, 43]) {
    final title = id == 42 ? 'Fixture movie' : 'Fixture show S01E01';
    await db.insert('items', {
      'id': id,
      'playlist_id': 'p',
      'item_key': id,
      'content_hash': id,
      'ord': 0,
      'kind': id == 42 ? 2 : 3,
      'group_id': 1,
      'title': title,
      'sort_title': title.toLowerCase(),
      'stream_url': 'https://fixture.test/$id',
      if (id == 43) ...{
        'series_key': 7,
        'season_number': 1,
        'episode_number': 1,
      },
    });
    await db.rawInsert('INSERT INTO items_fts(rowid, title) VALUES (?, ?)', [
      id,
      title,
    ]);
  }
  if (version >= 14) {
    await db.insert('movie_provider_bindings', {
      'playlist_id': 'p',
      'item_id': 42,
      'revision': 3,
      'provider': 'xtream',
      'provider_id': '99',
      'evidence': 'verifiedDetail',
    });
    await db.insert('movie_metadata_cache', {
      'playlist_id': 'p',
      'item_id': 42,
      'revision': 3,
      'locale': 'en',
      'payload': '{"fields":{"plot":"Fixture"},"sources":{}}',
      'fetched_at': 1,
      'expires_at': 2,
      'accessed_at': 1,
      'byte_size': 600,
    });
  }
  if (version >= 15) {
    await db.insert('series_metadata_cache', {
      'playlist_id': 'p',
      'series_key': 7,
      'revision': 3,
      'locale': 'sv',
      'provider_id': '100',
      'payload': '{"plot":"Fixture"}',
      'fetched_at': 1,
      'accessed_at': 1,
      'byte_size': 600,
    });
  }
}

class _ProbeMigration implements StorageMigration {
  const _ProbeMigration({required this.fail});
  final bool fail;
  @override
  int get version => _history.last.version + 1;
  @override
  String get name => 'test_upgrade_probe';
  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE migration_probe (id INTEGER PRIMARY KEY)');
    await db.update('playlists', {'name': 'Must roll back'}, where: "id = 'p'");
    if (fail) {
      await db.execute('INSERT INTO nonexistent_migration_fixture VALUES (1)');
    }
    await db.update('playlists', {
      'name': 'Fixture playlist',
    }, where: "id = 'p'");
  }
}
