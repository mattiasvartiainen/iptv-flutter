import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/metadata/series_metadata.dart';
import 'package:iptv_flutter/services/metadata/sqlite_series_metadata_repository.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/sources/source_verification_record.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';
import 'package:iptv_flutter/services/storage/storage_contracts.dart';
import 'package:iptv_flutter/services/xtream/bounded_xtream_json.dart';
import 'package:iptv_flutter/services/xtream/stored_xtream_credentials.dart';
import 'package:iptv_flutter/services/xtream/xtream_api_client.dart';
import 'package:iptv_flutter/services/xtream/xtream_authentication.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../support/database_adapter.dart';

void main() {
  late SqfliteDatabaseAdapter adapter;
  late SqliteSettingsRepository settings;
  late SqliteSeriesMetadataRepository repository;
  late _Server server;
  late DateTime now;
  const subject = SeriesMetadataSubject(playlistId: 'p', seriesId: '7');
  setUp(() async {
    adapter = createTestDatabaseAdapter(fileName: 'series_metadata_${DateTime.now().microsecondsSinceEpoch}.sqlite');
    settings = SqliteSettingsRepository(databaseAdapter: adapter, secretStore: _Secrets());
    await settings.upsertPlaylist(config());
    final db = await adapter.database;
    await db.insert('groups', {'id': 1, 'playlist_id': 'p', 'kind': 3, 'title': 'Series', 'sort_title': 'series', 'ord': 0});
    await db.insert('series_v8', {'series_key': 7, 'playlist_id': 'p', 'group_id': 1,
      'title': 'Fixture Show', 'sort_title': 'fixture show', 'ord': 0, 'episode_count': 1, 'season_count': 1});
    await db.insert('items', {'id': 42, 'playlist_id': 'p', 'item_key': 42, 'content_hash': 1, 'ord': 0,
      'kind': 3, 'group_id': 1, 'title': 'Fixture Show S01E01', 'sort_title': 'fixture show s01e01',
      'stream_url': 'https://provider.test/series/fixture-account/fixture-password/42.mkv',
      'series_key': 7, 'season_number': 1, 'episode_number': 1});
    await db.rawInsert('INSERT INTO items_fts(rowid, title) VALUES (42, ?)', ['Fixture Show S01E01']);
    server = _Server();
    now = DateTime.utc(2026, 11, 25);
    final resolver = StoredXtreamCredentials(settings);
    repository = SqliteSeriesMetadataRepository(database: adapter, resolveCredentials: resolver.resolve,
      client: XtreamApiClient(resolveCredentials: resolver.resolve, createTransport: () => _Transport(server)),
      now: () => now);
  });
  tearDown(() async {
    final path = (await adapter.database).path;
    await adapter.close();
    await testDatabaseFactory.deleteDatabase(path);
  });
  Future<List<SeriesMetadataResult>> resolve({bool force = false, SeriesMetadataSubject target = subject,
    MetadataCancellation? cancellation}) => repository.resolve(target,
      cancellation: cancellation ?? MetadataCancellation(), forceRefresh: force).toList();

  test('selected show validates membership and persists sanitized restart cache', () async {
    final db = await adapter.database;
    final before = await db.query('items');
    expect((await resolve()).single.metadata![ContentMetadataField.plot], 'Provider synopsis');
    expect(server.actions, ['get_series_categories', 'get_series', 'get_series_info']);
    expect(server.uris[1].queryParameters['category_id'], '3');
    expect(server.uris.last.queryParameters['series_id'], '99');
    expect(await db.query('items'), before);
    final row = (await db.query('series_metadata_cache')).single;
    expect(row['provider_id'], '99');
    expect(row['payload'], isNot(contains('fixture-password')));
    await adapter.close();
    expect((await resolve()).single.metadata, isNotNull);
    expect(server.actions, hasLength(3));
  });
  test('locale/account isolation and ordinary M3U skip all API work', () async {
    await resolve();
    await resolve(target: const SeriesMetadataSubject(playlistId: 'p', seriesId: '7', locale: 'sv'));
    expect(server.actions, hasLength(6));
    expect((await resolve(target: const SeriesMetadataSubject(playlistId: 'q', seriesId: '7'))).single.failure,
      MetadataFailure.unverified);
    await settings.upsertPlaylist(PlaylistSourceConfig.url(playlistId: 'p', name: 'M3U',
      url: 'https://fixture.test/playlist.m3u'));
    expect((await resolve()).single.failure, MetadataFailure.unverified);
    expect(server.actions, hasLength(6));
    expect(await (await adapter.database).query('series_metadata_cache'), isEmpty);
  });
  test('stale data survives provider failure; validated binding avoids rediscovery', () async {
    await resolve();
    now = now.add(const Duration(days: 8));
    server.status = 503;
    final results = await resolve();
    expect(results, hasLength(2));
    expect(results.first.isRefreshing, isTrue);
    expect(results.last.isStale, isTrue);
    expect(results.last.failure, MetadataFailure.network);
    expect(results.last.metadata![ContentMetadataField.plot], 'Provider synopsis');
    expect(server.actions.last, 'get_series_info');
  });
  test('ambiguous titles and unrelated members never create bindings', () async {
    server.ambiguous = true;
    expect((await resolve()).single.failure, MetadataFailure.unmapped);
    expect(server.actions, hasLength(2));
    server.ambiguous = false;
    server.episodeId = '123';
    expect((await resolve()).single.failure, MetadataFailure.unmapped);
    expect(await (await adapter.database).query('series_metadata_cache'), isEmpty);
  });
  test('stream replacement/deletion and source edit invalidate cache', () async {
    await resolve();
    final db = await adapter.database;
    await db.update('items', {'stream_url': 'https://fixture.test/plain.mkv'}, where: 'id = 42');
    expect(await db.query('series_metadata_cache'), isEmpty);
    expect((await resolve()).single.failure, MetadataFailure.unmapped);
    await db.update('items', {'stream_url': 'https://provider.test/series/fixture-account/fixture-password/42.mkv'}, where: 'id = 42');
    await resolve();
    await settings.upsertPlaylist(config(password: 'new-password'));
    expect(await db.query('series_metadata_cache'), isEmpty);
    expect((await resolve()).single.failure, MetadataFailure.unverified);
  });
  test('two readers share one fetch and one cancellation cannot cancel the other', () async {
    server.gate = Completer<void>();
    final cancellation = MetadataCancellation();
    final first = resolve(cancellation: cancellation);
    await server.started.future;
    final second = resolve();
    try {
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (repository.debugActiveReaders(subject, 0) != 2 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(repository.debugActiveReaders(subject, 0), 2,
        reason: 'both readers must attach before the first is cancelled');
      cancellation.cancel();
      expect(await first, isEmpty);
      expect(repository.debugActiveReaders(subject, 0), 1);
      server.gate!.complete();
      expect((await second).single.metadata![ContentMetadataField.plot], 'Provider synopsis');
      expect(server.actions, ['get_series_categories', 'get_series', 'get_series_info']);
    } finally {
      cancellation.cancel();
      if (!server.gate!.isCompleted) server.gate!.complete();
      await Future.wait([first, second]);
    }
  });
  test('cancelled/deleted subjects cannot write a late result', () async {
    server.gate = Completer<void>();
    final cancellation = MetadataCancellation();
    final loading = resolve(cancellation: cancellation);
    await server.started.future;
    await (await adapter.database).delete('series_v8', where: 'series_key = 7');
    cancellation.cancel();
    expect(await loading, isEmpty);
    server.gate!.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await (await adapter.database).query('series_metadata_cache'), isEmpty);
  });
  test('rate limits honor Retry-After without repeated provider work', () async {
    server.status = 429;
    expect((await resolve()).single.failure, MetadataFailure.rateLimited);
    expect((await resolve()).single.failure, MetadataFailure.rateLimited);
    expect(server.actions, hasLength(1));
    now = now.add(const Duration(seconds: 31));
    server.status = 200;
    expect((await resolve()).single.metadata, isNotNull);
  });
  test('v14 upgrade preserves local series and episodes', () async {
    final db = await adapter.database;
    await db.execute('DROP INDEX idx_items_series_membership');
    final before = await db.query('items');
    await db.execute('DROP TRIGGER invalidate_series_metadata_source');
    await db.execute('DROP TRIGGER invalidate_series_metadata_episode');
    await db.execute('DROP TRIGGER invalidate_series_metadata_episode_update');
    await db.execute('DROP TRIGGER invalidate_series_metadata_episode_insert');
    await db.execute('DROP TRIGGER invalidate_series_metadata_title');
    await db.execute('DROP TABLE series_metadata_cache');
    await db.delete('schema_migrations', where: 'version = 15');
    await db.execute('PRAGMA user_version = 14');
    await adapter.close();
    final upgraded = await adapter.database;
    expect((await upgraded.rawQuery('PRAGMA user_version')).single.values.single, 17);
    expect(await upgraded.query('items'), before);
    expect((await resolve()).single.metadata, isNotNull);
  });
  test('membership checks every local episode, not just the identity sample', () async {
    final db = await adapter.database;
    final template = (await db.query('items')).single;
    for (var index = 1; index <= 20; index++) {
      await db.insert('items', {...template, 'id': 42 + index, 'item_key': 42 + index,
        'stream_url': 'https://provider.test/series/fixture-account/fixture-password/${42 + index}.mkv'});
    }
    server.extraEpisodes = List.generate(19, (index) => 43 + index);
    expect((await resolve()).single.failure, MetadataFailure.unmapped);
    expect(await db.query('series_metadata_cache'), isEmpty);
    server.extraEpisodes.add(62);
    expect((await resolve()).single.metadata, isNotNull);
  });
  test('250 members are validated once in bounded keyset pages inside the cache transaction', () async {
    final db = await adapter.database;
    final template = (await db.query('items')).single;
    await db.transaction((txn) async {
      for (var index = 1; index < 250; index++) {
        await txn.insert('items', {...template, 'id': 42 + index * 2,
          'item_key': 42 + index * 2,
          'stream_url': 'https://provider.test/series/fixture-account/fixture-password/${42 + index * 2}.mkv'});
      }
    });
    server.extraEpisodes = List.generate(249, (index) => 44 + index * 2);
    final recorded = _RecordingAdapter(adapter);
    final resolver = StoredXtreamCredentials(settings);
    repository = SqliteSeriesMetadataRepository(database: recorded,
      resolveCredentials: resolver.resolve,
      client: XtreamApiClient(resolveCredentials: resolver.resolve, createTransport: () => _Transport(server)));
    expect((await resolve()).single.metadata, isNotNull);
    expect(recorded.pageSizes, [100, 100, 50]);
    expect(recorded.cursors, [null, 240, 440]);
    expect(await db.query('series_metadata_cache'), hasLength(1));
  });
  test('episode changed beyond identity sample during provider request cannot create cache', () async {
    final db = await adapter.database;
    final template = (await db.query('items')).single;
    for (var index = 1; index < 125; index++) {
      await db.insert('items', {...template, 'id': 42 + index, 'item_key': 42 + index,
        'stream_url': 'https://provider.test/series/fixture-account/fixture-password/${42 + index}.mkv'});
    }
    server.extraEpisodes = List.generate(124, (index) => 43 + index);
    server.gate = Completer<void>();
    final result = resolve();
    await server.started.future;
    await db.update('items', {'stream_url': 'https://fixture.test/not-a-provider-episode'},
      where: 'id = 166');
    server.gate!.complete();
    expect((await result).single.failure, MetadataFailure.unmapped);
    expect(await db.query('series_metadata_cache'), isEmpty);
  });
  test('cancelling membership paging releases the transaction without storing metadata', () async {
    final db = await adapter.database;
    final template = (await db.query('items')).single;
    for (var index = 1; index < 125; index++) {
      await db.insert('items', {...template, 'id': 42 + index, 'item_key': 42 + index,
        'stream_url': 'https://provider.test/series/fixture-account/fixture-password/${42 + index}.mkv'});
    }
    server.extraEpisodes = List.generate(124, (index) => 43 + index);
    final cancellation = MetadataCancellation();
    final recorded = _RecordingAdapter(adapter)..onPage = cancellation.cancel;
    final resolver = StoredXtreamCredentials(settings);
    repository = SqliteSeriesMetadataRepository(database: recorded,
      resolveCredentials: resolver.resolve,
      client: XtreamApiClient(resolveCredentials: resolver.resolve, createTransport: () => _Transport(server)));
    expect(await resolve(cancellation: cancellation), isEmpty);
    await recorded.finished.future;
    expect(recorded.pageSizes.first, 100);
    expect(recorded.pageSizes.length, lessThanOrEqualTo(2));
    expect(await db.query('series_metadata_cache'), isEmpty);
    await db.transaction((txn) => txn.update('series_v8', {'ord': 1}, where: 'series_key = 7'));
  });
  test('oversized detail, malformed data and sparse responses remain explicit', () async {
    server.oversized = true;
    expect((await resolve()).single.failure, MetadataFailure.tooLarge);
    server.oversized = false;
    server.malformed = true;
    expect((await resolve()).single.failure, MetadataFailure.malformed);
    expect(await (await adapter.database).query('series_metadata_cache'), isEmpty);
  });
  test('corrupt cache is removed so explicit retry can recover', () async {
    await resolve();
    final db = await adapter.database;
    await db.update('series_metadata_cache', {'payload': '{'});
    expect((await resolve()).single.failure, MetadataFailure.storage);
    expect(await db.query('series_metadata_cache'), isEmpty);
    expect((await resolve(force: true)).single.metadata, isNotNull);
  });
  test('Series JSON complexity limits remain explicit and do not affect local episodes', () async {
    final db = await adapter.database;
    final before = await db.query('items');
    server.detailOverride = List.filled(maxXtreamJsonNodes, 0);
    expect((await resolve()).single.failure, MetadataFailure.tooLarge);
    expect(await db.query('series_metadata_cache'), isEmpty);
    expect(await db.query('items'), before);
  });
  test('local-title edits, inserted episodes and playlist deletion invalidate persisted identity', () async {
    await resolve();
    final db = await adapter.database;
    await db.update('series_v8', {'title': 'Changed title'}, where: 'series_key = 7');
    expect(await db.query('series_metadata_cache'), isEmpty);
    await db.update('series_v8', {'title': 'Fixture Show'}, where: 'series_key = 7');
    await resolve();
    final template = (await db.query('items')).single;
    await db.insert('items', {...template, 'id': 43, 'item_key': 43,
      'stream_url': 'https://provider.test/series/fixture-account/fixture-password/43.mkv'});
    await db.rawInsert('INSERT INTO items_fts(rowid, title) VALUES (43, ?)', ['Fixture Show S01E01']);
    expect(await db.query('series_metadata_cache'), isEmpty);
    server.extraEpisodes = [43];
    await resolve();
    await settings.deletePlaylist('p');
    expect(await db.query('series_metadata_cache'), isEmpty);
    expect((await resolve()).single.failure, MetadataFailure.unverified);
  });
  test('cache maintenance enforces the actual 50 MiB payload budget and 30-day age', () async {
    final db = await adapter.database;
    for (final id in [8, 9]) {
      await db.insert('series_v8', {'series_key': id, 'playlist_id': 'p', 'group_id': 1,
        'title': 'Other $id', 'sort_title': 'other', 'ord': id});
    }
    final timestamp = now.millisecondsSinceEpoch;
    await db.rawInsert('''
INSERT INTO series_metadata_cache
(playlist_id, series_key, revision, locale, provider_id, payload, fetched_at, accessed_at, byte_size)
SELECT 'p', 8, 0, 'en', '100', payload, ?, ?, length(CAST(payload AS BLOB)) + 512
FROM (SELECT json_object('plot', replace(hex(zeroblob(26214400)), '0', 'x')) AS payload)
''', [timestamp, timestamp - 1000]);
    final before = (await db.rawQuery('SELECT SUM(byte_size) AS bytes FROM series_metadata_cache')).single['bytes']! as int;
    expect(before, greaterThan(50 * 1024 * 1024));
    await db.insert('series_metadata_cache', {'playlist_id': 'p', 'series_key': 9,
      'revision': 0, 'locale': 'en', 'provider_id': '101', 'payload': '{}',
      'fetched_at': timestamp - const Duration(days: 31).inMilliseconds,
      'accessed_at': timestamp + 1000, 'byte_size': 514});
    await resolve();
    final rows = await db.query('series_metadata_cache');
    expect(rows.map((row) => row['series_key']), [7]);
    final after = (await db.rawQuery('SELECT SUM(byte_size) AS bytes FROM series_metadata_cache')).single['bytes']! as int;
    expect(after, lessThanOrEqualTo(50 * 1024 * 1024));
  });
}

PlaylistSourceConfig config({String password = 'fixture-password'}) => PlaylistSourceConfig.xtream(
  playlistId: 'p', name: 'Fixture', server: 'https://provider.test', username: 'fixture-account', password: password,
  verificationRecord: SourceVerificationRecord(verification: SourceVerificationState.verified,
    accountState: SourceAccountState.active, checkedAt: DateTime.utc(2026, 11, 25), apiEnabled: true));

class _Secrets implements PlaylistSecretStore {
  final values = <String, String>{};
  @override
  Future<void> write({required String key, required String value}) async { values[key] = value; }
  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> delete({required String key}) async { values.remove(key); }
}

class _RecordingAdapter implements DatabaseAdapter {
  _RecordingAdapter(this.delegate);
  final DatabaseAdapter delegate;
  final pageSizes = <int>[];
  final cursors = <int?>[];
  void Function()? onPage;
  final finished = Completer<void>();
  @override
  Future<Database> get database => delegate.database;
  @override
  Future<void> initialize() => delegate.initialize();
  @override
  Future<void> close() => delegate.close();
  @override
  Future<T> transaction<T>(Future<T> Function(DatabaseExecutor) action) async {
    try {
      return await delegate.transaction((txn) => action(_RecordingExecutor(txn, this)));
    } finally {
      finished.complete();
    }
  }
}

class _RecordingExecutor implements DatabaseExecutor {
  _RecordingExecutor(this.delegate, this.recorded);
  final DatabaseExecutor delegate;
  final _RecordingAdapter recorded;
  @override
  Future<List<Map<String, Object?>>> query(String table, {
    bool? distinct, List<String>? columns, String? where, List<Object?>? whereArgs,
    String? groupBy, String? having, String? orderBy, int? limit, int? offset,
  }) async {
    final rows = await delegate.query(table, distinct: distinct, columns: columns,
      where: where, whereArgs: whereArgs, groupBy: groupBy, having: having,
      orderBy: orderBy, limit: limit, offset: offset);
    if (table == 'items' && limit == 100) {
      expect(offset, isNull);
      recorded.pageSizes.add(rows.length);
      recorded.cursors.add(whereArgs!.length == 3 ? whereArgs.last as int : null);
      recorded.onPage?.call();
    }
    return rows;
  }
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) =>
    delegate.rawQuery(sql, arguments);
  @override
  Future<int> insert(String table, Map<String, Object?> values, {
    String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm,
  }) => delegate.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
    delegate.rawDelete(sql, arguments);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Server {
  final actions = <String>[];
  final uris = <Uri>[];
  int status = 200;
  bool ambiguous = false;
  String episodeId = '42';
  List<int> extraEpisodes = [];
  bool oversized = false;
  bool malformed = false;
  Object? detailOverride;
  Completer<void>? gate;
  final started = Completer<void>();
}

class _Transport implements XtreamAuthTransport {
  _Transport(this.server);
  final _Server server;
  @override
  Future<XtreamAuthResponse> get(Uri uri) async {
    final action = uri.queryParameters['action']!;
    server.actions.add(action);
    server.uris.add(uri);
    if (action == 'get_series_info' && server.gate != null) {
      if (!server.started.isCompleted) server.started.complete();
      await server.gate!.future;
    }
    final Object payload = (action == 'get_series_info' ? server.detailOverride : null) ?? switch (action) {
      'get_series_categories' => [{'category_id': 3, 'category_name': 'Series'}],
      'get_series' => [
        {'series_id': 99, 'name': 'Fixture Show'},
        if (server.ambiguous) {'series_id': 100, 'name': 'Fixture Show'},
      ],
      _ => {
        'info': {'name': 'Fixture Show', 'plot': 'Provider synopsis'},
        'episodes': {'1': [{'id': server.episodeId, 'season': 1, 'episode_num': 1},
          for (final id in server.extraEpisodes) {'id': id, 'season': 1, 'episode_num': id}]},
      },
    };
    return XtreamAuthResponse(statusCode: server.status, retryAfter: '30',
      contentLength: server.oversized && action == 'get_series_info' ? 10 * 1024 * 1024 + 1 : null,
      body: Stream.value(utf8.encode(server.malformed ? '{' : jsonEncode(payload))));
  }
  @override
  void close() {}
}
