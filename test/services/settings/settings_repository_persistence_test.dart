import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/sources/source_verification_record.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';
import 'package:iptv_flutter/services/storage/storage_migrations.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../support/database_adapter.dart';

void main() {
  late SqfliteDatabaseAdapter adapter;
  late _ControlledSecrets secrets;
  late SqliteSettingsRepository repository;
  late Database database;

  setUp(() async {
    adapter = createTestDatabaseAdapter(
      fileName: 'xm03_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    secrets = _ControlledSecrets();
    repository = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: secrets,
    );
    database = await adapter.database;
  });

  tearDown(() async {
    final path = database.path;
    await adapter.close();
    await testDatabaseFactory.deleteDatabase(path);
  });

  PlaylistSourceConfig url({
    String? id = 'source',
    String name = 'Original',
    String address = 'https://provider.test/private/token/list?password=secret',
    bool enabled = true,
    SourceVerificationRecord? record,
  }) => PlaylistSourceConfig.url(
    playlistId: id,
    name: name,
    url: address,
    enabled: enabled,
    verificationRecord: record,
  );

  SourceVerificationRecord verified({int revision = 0}) =>
      SourceVerificationRecord(
        verification: SourceVerificationState.verified,
        accountState: SourceAccountState.active,
        checkedAt: DateTime.utc(2026, 10, 15, 12),
        connectionRevision: revision,
        apiEnabled: true,
      );

  Future<String> currentKey([String id = 'source']) async =>
      (await database.query(
            'playlists',
            where: 'id = ?',
            whereArgs: [id],
          )).single['secure_storage_key']!
          as String;

  Future<List<Map<String, Object?>>> journal() =>
      database.query('source_secret_journal');

  test(
    'verification is safe, separate from unchanged source JSON and M3U',
    () async {
      final config = url(record: verified());
      expect(
        config.toJson().keys,
        unorderedEquals([
          'kind',
          'name',
          'url',
          'server',
          'username',
          'password',
          'enabled',
        ]),
      );
      expect(config.toStorageValue(), isNot(contains('verification')));
      final saved = await repository.upsertPlaylist(config);
      final loaded = (await repository.listPlaylists()).single;
      expect(saved.connectionRevision, 0);
      expect(
        loaded.verificationRecord?.verification,
        SourceVerificationState.verified,
      );
      expect(
        loaded.verificationRecord?.accountState,
        SourceAccountState.active,
      );
      expect(loaded.verificationRecord?.checkedAt, verified().checkedAt);
      expect(loaded.verificationRecord?.apiEnabled, isTrue);
      expect(loaded.sourceConfig?.verificationRecord?.apiEnabled, isTrue);
      expect(loaded.connectionSummary?.catalogMode, CatalogSourceMode.m3u);
      for (final capability in SourceCapability.values) {
        expect(
          loaded.connectionSummary?.capability(capability),
          SourceCapabilityState.unknown,
        );
      }
      expect(loaded.sourceSummary, 'provider.test');
      expect(loaded.resolvedUrl, config.resolvedUrl);
      final row = (await database.query('playlists')).single;
      expect(row['source_verification'], 'verified');
      expect(row['source_account_state'], 'active');
      expect(row['source_api_enabled'], 1);
      expect(
        await secrets.read(key: await currentKey()),
        config.toStorageValue(),
      );
      expect(await journal(), isEmpty);
    },
  );

  test(
    'host summaries omit username, path, query and malformed fallback',
    () async {
      const config = PlaylistSourceConfig.xtream(
        name: 'Account',
        server: 'https://server.test/private/path',
        username: 'sensitive-user',
        password: 'sensitive-password',
      );
      expect(config.summary, 'server.test');
      expect(url(address: 'not a URI /private').summary, isEmpty);
      await repository.upsertPlaylist(url());
      secrets.values.clear();
      await database.update('playlists', {
        'source_url_redacted':
            'https://user:password@fallback.test/private/token?secret=value',
      });
      expect(
        (await repository.getPlaylist('source'))?.sourceSummary,
        'fallback.test',
      );
    },
  );

  test(
    'new saves retain generated and explicit playlist ID behavior',
    () async {
      final first = await repository.upsertPlaylist(url(id: null));
      final second = await repository.upsertPlaylist(url(id: null));
      expect(first.playlistId, startsWith('playlist-'));
      expect(second.playlistId, isNot(first.playlistId));
      final explicit = await repository.upsertPlaylist(url(id: 'explicit'));
      expect(explicit.playlistId, 'explicit');
      expect(await repository.listPlaylists(), hasLength(3));
    },
  );

  test(
    'rename and enabled changes preserve verification and rotate secret',
    () async {
      await repository.upsertPlaylist(url(record: verified()));
      final oldKey = await currentKey();
      final renamed = await repository.upsertPlaylist(
        url(name: 'Renamed', enabled: false),
      );
      expect(renamed.name, 'Renamed');
      expect(renamed.enabled, isFalse);
      expect(renamed.connectionRevision, 0);
      expect(
        renamed.verificationRecord?.verification,
        SourceVerificationState.verified,
      );
      expect(await currentKey(), isNot(oldKey));
      expect(await secrets.read(key: oldKey), isNull);
      expect(await journal(), isEmpty);
    },
  );

  test(
    'URL and kind edits advance revision and invalidate verification',
    () async {
      await repository.upsertPlaylist(url(record: verified()));
      final changed = await repository.upsertPlaylist(
        url(address: 'https://new.test/list'),
      );
      expect(changed.connectionRevision, 1);
      expect(changed.verificationRecord, isNull);
      final xtream = await repository.upsertPlaylist(
        const PlaylistSourceConfig.xtream(
          playlistId: 'source',
          name: 'Xtream',
          server: 'https://new.test',
          username: 'user',
          password: 'password',
        ),
      );
      expect(xtream.connectionRevision, 2);
      expect(xtream.verificationRecord, isNull);
    },
  );

  for (final field in ['server', 'username', 'password']) {
    test(
      '$field edit invalidates verification without trimming password',
      () async {
        PlaylistSourceConfig account({bool edit = false}) =>
            PlaylistSourceConfig.xtream(
              playlistId: 'source',
              name: 'Account',
              server: edit && field == 'server'
                  ? 'https://other.test'
                  : 'https://account.test',
              username: edit && field == 'username' ? 'other' : 'user',
              password: edit && field == 'password' ? ' pass ' : 'pass',
            );
        await repository.upsertPlaylist(account());
        expect(
          await repository.saveSourceVerification('source', 0, verified()),
          isTrue,
        );
        final changed = await repository.upsertPlaylist(account(edit: true));
        expect(changed.connectionRevision, 1);
        expect(changed.verificationRecord, isNull);
        if (field == 'password') {
          expect(changed.sourceConfig?.password, ' pass ');
        }
      },
    );
  }

  test(
    'explicit matching verification replaces record, stale records cannot',
    () async {
      await repository.upsertPlaylist(url(record: verified()));
      final changed = await repository.upsertPlaylist(
        url(address: 'https://other.test/list', record: verified(revision: 1)),
      );
      expect(changed.verificationRecord?.connectionRevision, 1);
      final stale = await repository.upsertPlaylist(
        url(
          address: 'https://other.test/list',
          record: verified(),
          name: 'Renamed',
        ),
      );
      expect(stale.verificationRecord?.connectionRevision, 1);
      final invalidated = await repository.upsertPlaylist(
        url(record: verified()),
      );
      expect(invalidated.connectionRevision, 2);
      expect(invalidated.verificationRecord, isNull);
    },
  );

  test(
    'expected revision updates reject stale, mismatched and deleted sources',
    () async {
      await repository.upsertPlaylist(url());
      final SourceVerificationRepository verificationRepository = repository;
      expect(
        await verificationRepository.saveSourceVerification(
          'source',
          0,
          verified(),
        ),
        isTrue,
      );
      await repository.upsertPlaylist(
        url(address: 'https://changed.test/list'),
      );
      expect(
        await verificationRepository.saveSourceVerification(
          'source',
          0,
          verified(),
        ),
        isFalse,
      );
      expect(
        await verificationRepository.saveSourceVerification(
          'source',
          1,
          verified(),
        ),
        isFalse,
      );
      expect(
        await verificationRepository.saveSourceVerification(
          'source',
          1,
          verified(revision: 1),
        ),
        isTrue,
      );
      await repository.deletePlaylist('source');
      expect(
        await verificationRepository.saveSourceVerification(
          'source',
          1,
          verified(revision: 1),
        ),
        isFalse,
      );
      expect(await database.query('playlists'), isEmpty);
    },
  );

  test(
    'journal is durable before secure write, including a partially failed write',
    () async {
      await repository.upsertPlaylist(url(record: verified()));
      final oldKey = await currentKey();
      secrets.beforeWrite = (key) async {
        expect((await journal()).single['secret_key'], key);
        expect(await currentKey(), oldKey);
      };
      secrets.failWriteAfterStoring = true;
      await expectLater(
        repository.upsertPlaylist(url(name: 'Failed')),
        throwsStateError,
      );
      expect(await currentKey(), oldKey);
      expect(await journal(), hasLength(1));
      final loaded = await repository.getPlaylist('source');
      expect(loaded?.name, 'Original');
      expect(
        loaded?.verificationRecord?.verification,
        SourceVerificationState.verified,
      );
      expect(secrets.values.keys, [oldKey]);
      expect(await journal(), isEmpty);
    },
  );

  test('secure failure before write cannot create a playlist', () async {
    secrets.failWrite = true;
    await expectLater(repository.upsertPlaylist(url()), throwsStateError);
    expect(await database.query('playlists'), isEmpty);
    expect(await journal(), hasLength(1));
    expect(await repository.listPlaylists(), isEmpty);
    expect(await journal(), isEmpty);
  });

  test(
    'DB failure after secure write keeps old config, revision and refresh settings',
    () async {
      await repository.upsertPlaylist(url(record: verified()));
      final oldKey = await currentKey();
      await database.update('playlist_settings', {'refresh_mode': 'daily'});
      await database.execute('''
CREATE TRIGGER fail_source_update BEFORE UPDATE ON playlists
BEGIN SELECT RAISE(ABORT, 'injected database failure'); END
''');
      await expectLater(
        repository.upsertPlaylist(url(address: 'https://changed.test/list')),
        throwsA(isA<DatabaseException>()),
      );
      expect(await currentKey(), oldKey);
      expect(secrets.values, hasLength(2));
      expect(await journal(), hasLength(1));
      final loaded = await repository.getPlaylist('source');
      expect(loaded?.sourceConfig?.url, url().url);
      expect(loaded?.connectionRevision, 0);
      expect(loaded?.verificationRecord?.apiEnabled, isTrue);
      expect(loaded?.refreshSettings?.refreshMode, RefreshMode.daily);
      expect(secrets.values.keys, [oldKey]);
      expect(await journal(), isEmpty);
    },
  );

  test(
    'transaction failure on create rolls back playlist and settings',
    () async {
      await database.execute('''
CREATE TRIGGER fail_settings_insert BEFORE INSERT ON playlist_settings
BEGIN SELECT RAISE(ABORT, 'injected settings failure'); END
''');
      await expectLater(
        repository.upsertPlaylist(url()),
        throwsA(isA<DatabaseException>()),
      );
      expect(await database.query('playlists'), isEmpty);
      expect(await database.query('playlist_settings'), isEmpty);
      expect(secrets.values, hasLength(1));
      expect(await repository.listPlaylists(), isEmpty);
      expect(secrets.values, isEmpty);
    },
  );

  for (final operation in ['list', 'get', 'upsert', 'delete']) {
    test(
      '$operation recovers interrupted staging without applying pending config',
      () async {
        await repository.upsertPlaylist(url());
        final oldKey = await currentKey();
        await database.insert('source_secret_journal', {
          'secret_key': 'abandoned',
        });
        secrets.values['abandoned'] = url(name: 'Uncommitted').toStorageValue();
        await database.insert('source_secret_journal', {'secret_key': oldKey});
        await database.insert('source_secret_journal', {
          'secret_key': 'never-written',
        });
        await adapter.close();
        database = await adapter.database;
        final reopened = SqliteSettingsRepository(
          databaseAdapter: adapter,
          secretStore: secrets,
        );
        switch (operation) {
          case 'list':
            await reopened.listPlaylists();
          case 'get':
            await reopened.getPlaylist('source');
          case 'upsert':
            await reopened.upsertPlaylist(url(id: 'another'));
          case 'delete':
            await reopened.deletePlaylist('missing');
        }
        expect((await reopened.getPlaylist('source'))?.name, 'Original');
        expect(await currentKey(), oldKey);
        expect(secrets.values[oldKey], isNotNull);
        expect(secrets.values['abandoned'], isNull);
        expect(await journal(), isEmpty);
      },
    );
  }

  test(
    'failed old-secret cleanup survives restart and protects committed source',
    () async {
      await repository.upsertPlaylist(url());
      final oldKey = await currentKey();
      secrets.failDelete = true;
      await repository.upsertPlaylist(url(name: 'Committed'));
      final committedKey = await currentKey();
      expect(committedKey, isNot(oldKey));
      expect((await journal()).single['secret_key'], oldKey);
      expect((await repository.getPlaylist('source'))?.name, 'Committed');
      secrets.failDelete = false;
      await adapter.close();
      database = await adapter.database;
      final reopened = SqliteSettingsRepository(
        databaseAdapter: adapter,
        secretStore: secrets,
      );
      expect((await reopened.listPlaylists()).single.name, 'Committed');
      expect(secrets.values.keys, [committedKey]);
      expect(await journal(), isEmpty);
    },
  );

  test(
    'delete journals cleanup transactionally and retries secure deletion failure',
    () async {
      await repository.upsertPlaylist(url());
      final key = await currentKey();
      secrets.failDelete = true;
      await repository.deletePlaylist('source');
      expect(await database.query('playlists'), isEmpty);
      expect((await journal()).single['secret_key'], key);
      expect(secrets.values[key], isNotNull);
      secrets.failDelete = false;
      expect(await repository.getPlaylist('source'), isNull);
      expect(secrets.values, isEmpty);
      expect(await journal(), isEmpty);
    },
  );

  test('failed DB delete leaves current secret and row intact', () async {
    await repository.upsertPlaylist(url());
    final key = await currentKey();
    await database.execute('''
CREATE TRIGGER fail_source_delete BEFORE DELETE ON playlists
BEGIN SELECT RAISE(ABORT, 'injected deletion failure'); END
''');
    await expectLater(
      repository.deletePlaylist('source'),
      throwsA(isA<DatabaseException>()),
    );
    expect(await currentKey(), key);
    expect(secrets.values[key], isNotNull);
    expect(await journal(), isEmpty);
    expect((await repository.getPlaylist('source'))?.name, 'Original');
  });

  test('queued read cannot clean an in-flight secret write', () async {
    await repository.upsertPlaylist(url());
    final entered = Completer<void>();
    final release = Completer<void>();
    secrets.beforeWrite = (key) async {
      entered.complete();
      await release.future;
    };
    final saving = repository.upsertPlaylist(url(name: 'Committed'));
    await entered.future;
    final reading = repository.listPlaylists();
    release.complete();
    await saving;
    expect((await reading).single.name, 'Committed');
    expect(secrets.values.keys, [await currentKey()]);
    expect(await journal(), isEmpty);
  });

  test('queued delete and verification cannot resurrect a source', () async {
    await repository.upsertPlaylist(url());
    final entered = Completer<void>();
    final release = Completer<void>();
    secrets.beforeWrite = (_) async {
      entered.complete();
      await release.future;
    };
    final saving = repository.upsertPlaylist(url(name: 'Committed'));
    await entered.future;
    final deleting = repository.deletePlaylist('source');
    final verifying = repository.saveSourceVerification(
      'source',
      0,
      verified(),
    );
    release.complete();
    await saving;
    await deleting;
    expect(await verifying, isFalse);
    expect(await repository.listPlaylists(), isEmpty);
    expect(secrets.values, isEmpty);
  });

  test(
    'source edits preserve catalog, user data, import state and refresh settings',
    () async {
      await repository.upsertPlaylist(url());
      await _seedCatalogAndUserData(database, 'source');
      await database.update('playlists', {
        'last_import_status': 'success',
        'last_import_staged_rows': 42,
      });
      await database.update('playlist_settings', {
        'refresh_mode': 'daily',
        'refresh_interval_hours': 24,
      });
      final tables = [
        'groups',
        'items',
        'series_v8',
        'favorites_v8',
        'playback_progress_v8',
        'watch_history_v8',
        'hidden_groups_v8',
        'playlist_settings',
        'items_fts_queue',
      ];
      final before = {
        for (final table in tables) table: await database.query(table),
      };
      await repository.upsertPlaylist(url(name: 'Renamed'));
      await repository.upsertPlaylist(
        url(address: 'https://changed.test/list'),
      );
      for (final table in tables) {
        expect(await database.query(table), before[table], reason: table);
      }
      final row = (await database.query('playlists')).single;
      expect(row['last_import_status'], 'success');
      expect(row['last_import_staged_rows'], 42);
      expect(
        await database.rawQuery(
          "SELECT rowid FROM items_fts WHERE items_fts MATCH 'Channel'",
        ),
        hasLength(1),
      );
    },
  );

  test(
    'v11 upgrade preserves legacy source references and raw URL secret',
    () async {
      const legacyMigrations = [
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
      ];
      final fileName =
          'xm03_legacy_${DateTime.now().microsecondsSinceEpoch}.sqlite';
      final legacy = createTestDatabaseAdapter(
        fileName: fileName,
        migrations: legacyMigrations,
      );
      final oldDatabase = await legacy.database;
      final oldPath = oldDatabase.path;
      final now = DateTime.now().toUtc().toIso8601String();
      await oldDatabase.insert('playlists', {
        'id': 'legacy',
        'name': 'Legacy',
        'secure_storage_key': 'playlist:legacy',
        'created_at': now,
        'updated_at': now,
      });
      await _seedCatalogAndUserData(oldDatabase, 'legacy');
      secrets.values['playlist:legacy'] = 'https://legacy.test/private/list';
      await legacy.close();
      final upgraded = createTestDatabaseAdapter(fileName: fileName);
      addTearDown(() async {
        await upgraded.close();
        await testDatabaseFactory.deleteDatabase(oldPath);
      });
      final upgradedRepo = SqliteSettingsRepository(
        databaseAdapter: upgraded,
        secretStore: secrets,
      );
      final loaded = await upgradedRepo.getPlaylist('legacy');
      expect(loaded?.connectionRevision, 0);
      expect(loaded?.verificationRecord, isNull);
      expect(loaded?.sourceConfig?.url, 'https://legacy.test/private/list');
      expect(loaded?.sourceSummary, 'legacy.test');
      final upgradedDb = await upgraded.database;
      expect(
        (await upgradedDb.query('playlists')).single['secure_storage_key'],
        'playlist:legacy',
      );
      expect(await upgradedDb.query('items'), hasLength(1));
      expect(await upgradedDb.query('favorites_v8'), hasLength(1));
      expect(await upgradedDb.query('source_secret_journal'), isEmpty);
      expect(secrets.writeCount, 0);
    },
  );
}

class _ControlledSecrets implements PlaylistSecretStore {
  final Map<String, String> values = {};
  bool failWrite = false;
  bool failWriteAfterStoring = false;
  bool failDelete = false;
  int writeCount = 0;
  Future<void> Function(String key)? beforeWrite;

  @override
  Future<void> write({required String key, required String value}) async {
    writeCount++;
    await beforeWrite?.call(key);
    if (failWrite) throw StateError('secure write unavailable');
    values[key] = value;
    if (failWriteAfterStoring) throw StateError('secure write interrupted');
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> delete({required String key}) async {
    if (failDelete) throw StateError('secure cleanup unavailable');
    values.remove(key);
  }
}

Future<void> _seedCatalogAndUserData(Database db, String playlistId) async {
  final groupId = await db.insert('groups', {
    'playlist_id': playlistId,
    'kind': 1,
    'title': 'News',
    'sort_title': 'news',
    'ord': 0,
  });
  final itemId = await db.insert('items', {
    'playlist_id': playlistId,
    'item_key': 1,
    'content_hash': 2,
    'ord': 0,
    'kind': 1,
    'group_id': groupId,
    'title': 'Channel',
    'sort_title': 'channel',
    'stream_url': 'https://stream.test/channel',
  });
  await db.insert('items_fts', {'rowid': itemId, 'title': 'Channel'});
  await db.insert('series_v8', {
    'series_key': 3,
    'playlist_id': playlistId,
    'group_id': groupId,
    'title': 'Series',
    'sort_title': 'series',
    'ord': 0,
  });
  final identity = {
    'profile_id': 'default',
    'playlist_id': playlistId,
    'item_key': 1,
  };
  await db.insert('favorites_v8', {...identity, 'created_at': 1});
  await db.insert('playback_progress_v8', {
    ...identity,
    'position_ms': 100,
    'updated_at': 1,
  });
  await db.insert('watch_history_v8', {...identity, 'watched_at': 1});
  await db.insert('hidden_groups_v8', {
    'profile_id': 'default',
    'playlist_id': playlistId,
    'kind': 1,
    'group_title': 'Hidden',
  });
  await db.insert('items_fts_queue', {
    'playlist_id': playlistId,
    'item_id': itemId,
    'operation': 'upsert',
    'priority': 1,
    'queued_at': 1,
  });
}
