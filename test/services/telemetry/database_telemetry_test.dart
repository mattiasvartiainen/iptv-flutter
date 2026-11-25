import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/catalog/catalog_search_indexer.dart';
import 'package:iptv_flutter/services/catalog/sqlite_catalog_query_service.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/storage_contracts.dart';
import 'package:iptv_flutter/services/storage/storage_migrations.dart';
import 'package:iptv_flutter/services/telemetry/app_telemetry.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../support/database_adapter.dart';

const _sensitive = 'private-user-password-token';
const _streamUrl = 'https://user:password@provider.test/private?token=secret';

void main() {
  late _RecordingTelemetry telemetry;

  setUp(() {
    telemetry = _RecordingTelemetry();
  });

  test(
    'open awaits directory lookup, configuration and all migrations',
    () async {
      final directoryReady = Completer<void>();
      final directoryRequested = Completer<void>();
      final adapter = await _createAdapter(
        telemetry,
        beforeDirectory: () async {
          directoryRequested.complete();
          await directoryReady.future;
        },
      );
      final opening = adapter.initialize();
      await directoryRequested.future;
      expect(telemetry.started, ['db.open']);
      expect(telemetry.measurements, isEmpty);
      directoryReady.complete();
      await opening;

      final migrations = telemetry.measurements.where(
        (measurement) => measurement.operation == 'db.migration',
      );
      expect(migrations.map((measurement) => measurement.attributes), [
        for (var version = 1; version <= 14; version++) {'version': version},
      ]);
      expect(telemetry.measurements.last.operation, 'db.open');
      expect(
        telemetry.measurements.every((entry) => entry.elapsed >= Duration.zero),
        isTrue,
      );
      final db = await adapter.database;
      expect(
        (await db.rawQuery('PRAGMA foreign_keys')).single.values.single,
        1,
      );
      expect((await db.rawQuery('PRAGMA synchronous')).single.values.single, 1);
      expect(
        (await db.rawQuery('PRAGMA cache_size')).single.values.single,
        -8000,
      );
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        14,
      );
      _expectSafePayloads(telemetry);
    },
  );

  test(
    'directory failure is measured and preserves the original error',
    () async {
      final error = StateError(_sensitive);
      final adapter = await _createAdapter(
        telemetry,
        beforeDirectory: () async => throw error,
      );
      await expectLater(adapter.initialize(), throwsA(same(error)));
      expect(telemetry.failures.single.operation, 'db.open');
      expect(telemetry.measurements.single.failed, isTrue);
      _expectSafePayloads(telemetry);
    },
  );

  test('live migrations are timed once with version only', () async {
    final migrations = <StorageMigration>[const InitialSchemaV1Migration()];
    final adapter = await _createAdapter(telemetry, migrations: migrations);
    await adapter.initialize();
    migrations.add(const PlaylistImportMetricsV2Migration());
    await adapter.initialize();
    await adapter.initialize();
    expect(
      telemetry.measurements
          .where((entry) => entry.operation == 'db.migration')
          .map((entry) => entry.attributes),
      [
        {'version': 1},
        {'version': 2},
      ],
    );
    final db = await adapter.database;
    expect((await db.rawQuery('PRAGMA user_version')).single.values.single, 2);
    _expectSafePayloads(telemetry);
  });

  test('migration SQL failure is recorded by migration and open', () async {
    final adapter = await _createAdapter(
      telemetry,
      migrations: [const InitialSchemaV1Migration(), _FailingMigration()],
    );
    await expectLater(adapter.initialize(), throwsA(isA<DatabaseException>()));
    expect(telemetry.failures.map((entry) => entry.operation), [
      'db.migration',
      'db.open',
    ]);
    expect(
      telemetry.measurements
          .singleWhere(
            (entry) => entry.operation == 'db.migration' && entry.failed,
          )
          .attributes,
      {'version': 2},
    );
    _expectSafePayloads(telemetry);
  });

  test(
    'transaction timing spans completion and SQL failures still roll back',
    () async {
      final adapter = await _createAdapter(telemetry);
      await adapter.initialize();
      telemetry.clear();
      final entered = Completer<void>();
      final release = Completer<void>();
      final transaction = adapter.transaction((txn) async {
        await txn.update(
          'app_settings',
          {'value': _sensitive},
          where: 'key = ?',
          whereArgs: ['animations_enabled'],
        );
        entered.complete();
        await release.future;
        return 42;
      });
      await entered.future;
      expect(telemetry.started, contains('db.transaction'));
      expect(
        telemetry.measurements.map((entry) => entry.operation),
        isNot(contains('db.transaction')),
      );
      release.complete();
      expect(await transaction, 42);
      expect(telemetry.measurements.last.operation, 'db.transaction');
      final db = await adapter.database;
      Future<String> value() async =>
          (await db.query(
                'app_settings',
                where: 'key = ?',
                whereArgs: ['animations_enabled'],
              )).single['value']!
              as String;
      expect(await value(), _sensitive);
      await expectLater(
        adapter.transaction((txn) async {
          await txn.update(
            'app_settings',
            {'value': 'rolled-back'},
            where: 'key = ?',
            whereArgs: ['animations_enabled'],
          );
          await txn.rawInsert('INSERT INTO missing_$_sensitive VALUES (?)', [
            _streamUrl,
          ]);
        }),
        throwsA(isA<DatabaseException>()),
      );
      expect(await value(), _sensitive);
      expect(telemetry.failures.single.operation, 'db.transaction');
      _expectSafePayloads(telemetry);
    },
  );

  test(
    'all public reads and counts are measured without SQL or values',
    () async {
      final adapter = await _createAdapter(telemetry);
      final db = await adapter.database;
      final groupId = await db.insert('groups', {
        'playlist_id': _sensitive,
        'kind': 3,
        'title': _sensitive,
        'sort_title': _sensitive,
        'ord': 0,
        'item_count': 1,
      });
      final itemId = await db.insert('items', {
        'playlist_id': _sensitive,
        'item_key': 91,
        'content_hash': 7,
        'ord': 0,
        'kind': 3,
        'group_id': groupId,
        'title': _sensitive,
        'sort_title': _sensitive,
        'stream_url': _streamUrl,
        'series_key': 73,
        'season_number': 1,
        'episode_number': 1,
      });
      await db.insert('series_v8', {
        'series_key': 73,
        'playlist_id': _sensitive,
        'group_id': groupId,
        'title': _sensitive,
        'sort_title': _sensitive,
        'ord': 0,
        'season_count': 1,
        'episode_count': 1,
      });
      await db.rawInsert('INSERT INTO items_fts(rowid, title) VALUES (?, ?)', [
        itemId,
        _sensitive,
      ]);
      final queries = _queries(adapter, telemetry);
      telemetry.clear();

      expect(
        (await queries.queryItems(
          const CatalogQuery(
            playlistId: _sensitive,
            searchTerm: _sensitive,
            group: _sensitive,
          ),
        )).total,
        1,
      );
      expect(
        (await queries.homePreview(
          _sensitive,
          kind: CatalogItemKind.episode,
        )).single.title,
        _sensitive,
      );
      expect(
        (await queries.querySeries(_sensitive, searchTerm: _sensitive)).total,
        1,
      );
      expect((await queries.seasons('73')).single.episodeCount, 1);
      expect((await queries.episodes('73:1')).total, 1);
      expect(
        await queries.groups(_sensitive, kinds: [CatalogItemKind.episode]),
        [_sensitive],
      );
      expect(
        (await queries.queryGroups(
          _sensitive,
          kind: CatalogGroupKind.series,
          profileId: _sensitive,
        )).single.id,
        groupId,
      );
      expect((await queries.itemsInGroup(_sensitive, groupId)).total, 1);
      expect(
        (await queries.seriesInGroup(
          _sensitive,
          groupId,
          searchTerm: _sensitive,
        )).total,
        1,
      );
      expect((await queries.itemById('$itemId'))!.streamUrl, _streamUrl);
      await queries.searchIndexStatus(_sensitive);

      expect(
        telemetry.measurements
            .where((entry) => entry.operation.startsWith('db.query.'))
            .map((entry) => entry.operation)
            .toSet(),
        {
          'db.query.items',
          'db.query.home_preview',
          'db.query.series',
          'db.query.seasons',
          'db.query.episodes',
          'db.query.groups',
          'db.query.group_summaries',
          'db.query.items_in_group',
          'db.query.series_in_group',
          'db.query.item_by_id',
          'db.query.search_index_status',
          'db.query.count',
        },
      );
      expect(telemetry.failures, isEmpty);
      _expectSafePayloads(telemetry);
    },
  );

  test(
    'query failures and invalid lookup results preserve semantics',
    () async {
      final adapter = await _createAdapter(telemetry);
      final db = await adapter.database;
      final queries = _queries(adapter, telemetry);
      telemetry.clear();
      expect(await queries.itemById(_sensitive), isNull);
      expect(await queries.seasons(_sensitive), isEmpty);
      expect((await queries.episodes(_sensitive, offset: 9)).offset, 9);
      expect((await queries.itemsInGroup(_sensitive, -1)).items, isEmpty);
      expect(
        (await queries.seriesInGroup(_sensitive, -1, offset: 9)).offset,
        9,
      );
      await db.execute('DROP TABLE items');
      await expectLater(
        queries.queryItems(const CatalogQuery(playlistId: _sensitive)),
        throwsA(isA<DatabaseException>()),
      );
      expect(telemetry.failures.map((entry) => entry.operation), [
        'db.query.count',
        'db.query.items',
      ]);
      _expectSafePayloads(telemetry);
    },
  );
}

Future<SqfliteDatabaseAdapter> _createAdapter(
  AppTelemetry telemetry, {
  List<StorageMigration>? migrations,
  Future<void> Function()? beforeDirectory,
}) async {
  final directory = await Directory.systemTemp.createTemp('db_telemetry_');
  final adapter = SqfliteDatabaseAdapter(
    databaseFactory: testDatabaseFactory,
    databaseDirectoryProvider: () async {
      await beforeDirectory?.call();
      return directory.path;
    },
    fileName: '$_sensitive.sqlite',
    migrations: migrations,
    telemetry: telemetry,
  );
  addTearDown(() async {
    await adapter.close();
    await directory.delete(recursive: true);
  });
  return adapter;
}

SqliteCatalogQueryService _queries(
  DatabaseAdapter adapter,
  AppTelemetry telemetry,
) => SqliteCatalogQueryService(
  databaseAdapter: adapter,
  searchIndexer: SqliteCatalogSearchIndexer(
    databaseAdapter: adapter,
    autoStartWorker: false,
  ),
  telemetry: telemetry,
);

void _expectSafePayloads(_RecordingTelemetry telemetry) {
  for (final entry in telemetry.measurements) {
    expect(
      entry.attributes,
      entry.operation == 'db.migration' ? {'version': isA<int>()} : isEmpty,
    );
    expect(entry.operation, matches(r'^db\.[a-z_.]+$'));
  }
  final exported =
      '${telemetry.started} ${telemetry.measurements.map((entry) => '${entry.operation} ${entry.attributes}')} ${telemetry.failures}';
  for (final forbidden in [
    _sensitive,
    _streamUrl,
    '.sqlite',
    'SELECT',
    'INSERT',
    'whereArgs',
    'schema_meta',
    'stream_url',
    Directory.systemTemp.path,
  ]) {
    expect(exported, isNot(contains(forbidden)));
  }
}

class _FailingMigration implements StorageMigration {
  @override
  int get version => 2;

  @override
  String get name => _sensitive;

  @override
  Future<void> up(DatabaseExecutor db) async {
    await db.rawInsert('INSERT INTO missing_$_sensitive VALUES (?)', [
      _streamUrl,
    ]);
  }
}

class _Measurement {
  _Measurement(this.operation, this.attributes, this.elapsed, this.failed);

  final String operation;
  final Map<String, Object?> attributes;
  final Duration elapsed;
  final bool failed;
}

class _RecordingTelemetry extends AppTelemetry {
  final started = <String>[];
  final measurements = <_Measurement>[];
  final failures = <({String operation, Type errorType})>[];

  void clear() {
    started.clear();
    measurements.clear();
    failures.clear();
  }

  @override
  Future<T> measure<T>(
    String operation,
    Future<T> Function() action, {
    Map<String, Object?> attributes = const {},
  }) async {
    started.add(operation);
    final stopwatch = Stopwatch()..start();
    var failed = false;
    try {
      return await action();
    } catch (error, stackTrace) {
      failed = true;
      failure(operation, error, stackTrace);
      rethrow;
    } finally {
      stopwatch.stop();
      measurements.add(
        _Measurement(operation, Map.of(attributes), stopwatch.elapsed, failed),
      );
    }
  }

  @override
  void event(String name, {Map<String, Object?> attributes = const {}}) {
    fail('Database instrumentation should use measure only');
  }

  @override
  void failure(String name, Object error, StackTrace stackTrace) {
    failures.add((operation: name, errorType: error.runtimeType));
  }
}
