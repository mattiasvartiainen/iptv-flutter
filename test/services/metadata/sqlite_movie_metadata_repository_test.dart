import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/metadata/movie_metadata.dart';
import 'package:iptv_flutter/services/metadata/sqlite_movie_metadata_repository.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';
import 'package:iptv_flutter/services/sources/source_contracts.dart';
import 'package:iptv_flutter/services/sources/source_verification_record.dart';
import 'package:iptv_flutter/services/storage/database_adapter.dart';
import 'package:iptv_flutter/services/storage/movie_metadata_v14_migration.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';
import 'package:iptv_flutter/services/xtream/stored_xtream_credentials.dart';
import 'package:iptv_flutter/services/xtream/xtream_api_client.dart';
import 'package:iptv_flutter/services/xtream/xtream_authentication.dart';
import 'package:iptv_flutter/services/xtream/xtream_movie_metadata_provider.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../support/database_adapter.dart';

void main() {
  late SqfliteDatabaseAdapter adapter;
  late SqliteSettingsRepository settings;
  late _Provider provider;
  late SqliteMovieMetadataRepository repository;
  late DateTime now;
  const subject = MovieMetadataSubject(playlistId: 'p', itemId: '42');

  setUp(() async {
    adapter = createTestDatabaseAdapter(
      fileName:
          'movie_metadata_${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    settings = SqliteSettingsRepository(
      databaseAdapter: adapter,
      secretStore: _Secrets(),
    );
    await settings.upsertPlaylist(_config('p'));
    final db = await adapter.database;
    await _item(db, 'p', 42);
    provider = _Provider();
    now = DateTime.utc(2026, 11, 25);
    repository = SqliteMovieMetadataRepository(
      database: adapter,
      resolveCredentials: StoredXtreamCredentials(settings).resolve,
      providers: [provider],
      now: () => now,
    );
  });
  tearDown(() async {
    final path = (await adapter.database).path;
    await adapter.close();
    await testDatabaseFactory.deleteDatabase(path);
  });

  Future<List<MovieMetadataResult>> resolve({
    MovieMetadataSubject target = subject,
    bool force = false,
  }) => repository
      .resolve(
        target,
        cancellation: MetadataCancellation(),
        forceRefresh: force,
      )
      .toList();

  test(
    'persists verified identity/cache without changing local catalog',
    () async {
      final db = await adapter.database;
      final before = await db.query('items');
      final result = (await resolve()).single;
      expect(result.metadata![MovieMetadataField.plot], 'Provider plot');
      expect(await db.query('items'), before);
      final binding = (await db.query('movie_provider_bindings')).single;
      expect(binding['provider_id'], '42');
      expect(binding['evidence'], 'verifiedDetail');
      final payload =
          (await db.query('movie_metadata_cache')).single['payload']! as String;
      expect(payload, isNot(contains('account-name')));
      expect(payload, isNot(contains('private-password')));
      await adapter.close();
      final cached = (await resolve()).single;
      expect(cached.metadata![MovieMetadataField.plot], 'Provider plot');
      expect(provider.calls, 1);
    },
  );
  for (final corrupted in [
    {'payload': '{'},
    {
      'payload': jsonEncode({
        'fields': {'plot': 42},
        'sources': {},
      }),
    },
    {
      'payload': jsonEncode({
        'fields': {'poster': 'https://fixture.test/a?token=x'},
        'sources': {},
      }),
    },
    {'failure': 'invalid-failure'},
    {'expires_at': 'invalid-expiry'},
    {'payload': Uint8List.fromList([0, 1, 2])},
  ]) {
    test(
      'invalid movie cache is removed and Retry fetches again: $corrupted',
      () async {
        await resolve();
        final db = await adapter.database;
        await db.update('movie_metadata_cache', corrupted);
        expect((await resolve()).single.failure, MetadataFailure.storage);
        expect(await db.query('movie_metadata_cache'), isEmpty);
        expect(
          (await resolve(
            force: true,
          )).single.metadata![MovieMetadataField.plot],
          'Provider plot',
        );
        expect(provider.calls, 2);
      },
    );
  }
  test(
    'forced refresh can recover an already corrupt row immediately and preserves other locales',
    () async {
      await resolve();
      await resolve(
        target: const MovieMetadataSubject(
          playlistId: 'p',
          itemId: '42',
          locale: 'sv',
        ),
      );
      final db = await adapter.database;
      await db.update('movie_metadata_cache', {
        'payload': '{',
      }, where: "locale = 'en'");
      expect((await resolve(force: true)).single.metadata, isNotNull);
      expect(await db.query('movie_metadata_cache'), hasLength(2));
      expect(provider.calls, 3);
    },
  );

  test(
    'selected movie travels through stored credentials, API mapper and cache',
    () async {
      final credentials = StoredXtreamCredentials(settings);
      final transport = _VodTransport();
      repository = SqliteMovieMetadataRepository(
        database: adapter,
        resolveCredentials: credentials.resolve,
        providers: [
          XtreamMovieMetadataProvider(
            XtreamApiClient(
              resolveCredentials: credentials.resolve,
              createTransport: () => transport,
            ),
          ),
        ],
      );
      final result = (await resolve()).single;
      expect(result.metadata![MovieMetadataField.plot], 'API plot');
      expect(transport.uri!.queryParameters['action'], 'get_vod_info');
      expect(transport.uri!.queryParameters['vod_id'], '42');
      expect(transport.closed, isTrue);
      final db = await adapter.database;
      expect(
        (await db.query('movie_provider_bindings')).single['provider_id'],
        '42',
      );
      expect(
        (await resolve()).single.metadata![MovieMetadataField.plot],
        'API plot',
      );
      expect(transport.requests, 1);
    },
  );

  test(
    'fresh cache isolates locale and account; no cross-playlist item lookup',
    () async {
      await resolve();
      await resolve();
      expect(provider.calls, 1);
      await resolve(
        target: const MovieMetadataSubject(
          playlistId: 'p',
          itemId: '42',
          locale: 'sv',
        ),
      );
      expect(provider.calls, 2);
      await settings.upsertPlaylist(_config('q'));
      await _item(await adapter.database, 'q', 43);
      expect(
        (await resolve(
          target: const MovieMetadataSubject(playlistId: 'q', itemId: '42'),
        )).single.failure,
        MetadataFailure.notFound,
      );
      await resolve(
        target: const MovieMetadataSubject(playlistId: 'q', itemId: '43'),
      );
      expect(provider.calls, 3);
      expect(provider.subjects.last.playlistId, 'q');
    },
  );

  test(
    'stale cache survives network failure and manual retry refreshes it',
    () async {
      await resolve();
      now = now.add(const Duration(days: 8));
      provider.result = const MovieMetadataResult(
        failure: MetadataFailure.network,
      );
      final results = await resolve();
      expect(results, hasLength(2));
      expect(results.first.isRefreshing, isTrue);
      expect(results.last.isStale, isTrue);
      expect(results.last.failure, MetadataFailure.network);
      expect(results.last.metadata![MovieMetadataField.plot], 'Provider plot');
      provider.result = _metadata('Refreshed');
      expect(
        (await resolve(force: true)).last.metadata![MovieMetadataField.plot],
        'Refreshed',
      );
      expect((await resolve()).single.isStale, isFalse);
    },
  );

  test(
    'negative cache excludes auth failures and can be bypassed by retry',
    () async {
      provider.result = const MovieMetadataResult(
        failure: MetadataFailure.unsupported,
      );
      await resolve();
      await resolve();
      expect(provider.calls, 1);
      await resolve(force: true);
      expect(provider.calls, 2);
      now = now.add(const Duration(minutes: 16));
      provider.result = const MovieMetadataResult(
        failure: MetadataFailure.denied,
      );
      await resolve();
      await resolve();
      expect(provider.calls, 4);
    },
  );

  test(
    'deduplicates requests and cancels shared work only after last reader',
    () async {
      provider.gate = Completer<MovieMetadataResult>();
      final firstCancel = MetadataCancellation();
      final secondCancel = MetadataCancellation();
      final first = repository
          .resolve(subject, cancellation: firstCancel)
          .toList();
      final second = repository
          .resolve(subject, cancellation: secondCancel)
          .toList();
      await provider.started.future;
      // Wait until both readers have passed their database lookup.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      firstCancel.cancel();
      expect(await first, isEmpty);
      expect(provider.operation!.isCancelled, isFalse);
      provider.gate!.complete(_metadata('Shared'));
      expect(
        (await second).single.metadata![MovieMetadataField.plot],
        'Shared',
      );
      expect(provider.calls, 1);
      expect(provider.operation!.isCancelled, isTrue);
    },
  );

  test(
    'source edit invalidates caches/bindings and rejects old completion',
    () async {
      await resolve();
      provider.gate = Completer<MovieMetadataResult>();
      provider.started = Completer<void>();
      final refresh = resolve(force: true);
      await provider.started.future;
      await settings.upsertPlaylist(_config('p', password: 'new-password'));
      provider.gate!.complete(_metadata('Old account'));
      await refresh;
      final db = await adapter.database;
      expect(await db.query('movie_provider_bindings'), isEmpty);
      expect(await db.query('movie_metadata_cache'), isEmpty);
      expect((await resolve()).single.failure, MetadataFailure.unverified);
    },
  );

  test(
    'playlist deletion cascades metadata and rejects pending results',
    () async {
      await resolve();
      provider.gate = Completer<MovieMetadataResult>();
      provider.started = Completer<void>();
      final refresh = resolve(force: true);
      await provider.started.future;
      await settings.deletePlaylist('p');
      provider.gate!.complete(_metadata('Deleted'));
      await refresh;
      final db = await adapter.database;
      expect(await db.query('movie_provider_bindings'), isEmpty);
      expect(await db.query('movie_metadata_cache'), isEmpty);
    },
  );

  test(
    'ordinary M3U, episodes and unmapped numeric streams do not call API',
    () async {
      final db = await adapter.database;
      await db.update('items', {'kind': 3}, where: 'id = 42');
      expect((await resolve()).single.failure, MetadataFailure.notMovie);
      await db.update('items', {
        'kind': 2,
        'stream_url': 'https://provider.example/42',
      }, where: 'id = 42');
      expect((await resolve()).single.failure, MetadataFailure.unmapped);
      await settings.upsertPlaylist(
        const PlaylistSourceConfig.url(
          playlistId: 'p',
          name: 'Plain M3U',
          url: 'https://plain.example/list.m3u8',
        ),
      );
      expect((await resolve()).single.failure, MetadataFailure.unverified);
      expect(provider.calls, 0);
    },
  );

  test('verified URL input remains M3U but can resolve Xtream details', () async {
    final playlist = await settings.upsertPlaylist(
      PlaylistSourceConfig.url(
        playlistId: 'q',
        name: 'URL',
        url:
            'https://provider.example/get.php?username=account-name&password=private-password&type=m3u_plus',
        verificationRecord: SourceVerificationRecord(
          verification: SourceVerificationState.verified,
          accountState: SourceAccountState.active,
          checkedAt: now,
          apiEnabled: true,
        ),
      ),
    );
    expect(playlist.sourceKind, PlaylistSourceKind.url);
    await _item(await adapter.database, 'q', 43);
    expect(
      (await resolve(
        target: const MovieMetadataSubject(playlistId: 'q', itemId: '43'),
      )).single.failure,
      isNull,
    );
  });

  test(
    'fake second provider fills missing fields without replacing Xtream',
    () async {
      final second = _Provider(id: 'fake')
        ..result = MovieMetadataResult(
          metadata: MovieMetadata(
            fields: {
              MovieMetadataField.plot: 'External plot',
              MovieMetadataField.cast: 'External cast',
            },
            sources: {
              MovieMetadataField.plot: 'fake',
              MovieMetadataField.cast: 'fake',
            },
          ),
        );
      repository = SqliteMovieMetadataRepository(
        database: adapter,
        resolveCredentials: StoredXtreamCredentials(settings).resolve,
        providers: [provider, second],
      );
      final metadata = (await resolve()).single.metadata!;
      expect(metadata[MovieMetadataField.plot], 'Provider plot');
      expect(metadata[MovieMetadataField.cast], 'External cast');
      expect(metadata.sources[MovieMetadataField.plot], 'xtream');
      expect(metadata.sources[MovieMetadataField.cast], 'fake');
    },
  );

  test(
    'account requests serialize and respect Retry-After on manual retry',
    () async {
      provider.gate = Completer<MovieMetadataResult>();
      await _item(await adapter.database, 'p', 43);
      final first = resolve();
      await provider.started.future;
      final second = resolve(
        target: const MovieMetadataSubject(playlistId: 'p', itemId: '43'),
      );
      provider.gate!.complete(
        const MovieMetadataResult(
          failure: MetadataFailure.rateLimited,
          retryAfter: Duration(seconds: 30),
        ),
      );
      expect((await first).single.failure, MetadataFailure.rateLimited);
      expect((await second).single.failure, MetadataFailure.rateLimited);
      expect(provider.calls, 1);
      await resolve(force: true);
      expect(provider.calls, 1);
      now = now.add(const Duration(seconds: 31));
      provider.gate = null;
      provider.result = _metadata('Available');
      await resolve(force: true);
      expect(provider.calls, 2);
    },
  );

  test('cache stays within byte budget using LRU', () async {
    repository = SqliteMovieMetadataRepository(
      database: adapter,
      resolveCredentials: StoredXtreamCredentials(settings).resolve,
      providers: [provider],
      maxCacheBytes: 700,
      now: () => now,
    );
    await resolve();
    now = now.add(const Duration(seconds: 1));
    await _item(await adapter.database, 'p', 43);
    await resolve(
      target: const MovieMetadataSubject(playlistId: 'p', itemId: '43'),
    );
    final rows = await (await adapter.database).query('movie_metadata_cache');
    expect(rows, hasLength(1));
    expect(rows.single['item_id'], 43);
    expect(rows.single['byte_size']! as int, lessThanOrEqualTo(700));
  });

  test('v13 upgrade preserves catalog and user data', () async {
    final db = await adapter.database;
    await db.execute('DROP INDEX idx_items_series_membership');
    final before = await db.query('items');
    await db.execute('DROP TRIGGER invalidate_series_metadata_source');
    await db.execute('DROP TRIGGER invalidate_series_metadata_episode');
    await db.execute('DROP TRIGGER invalidate_series_metadata_episode_update');
    await db.execute('DROP TRIGGER invalidate_series_metadata_episode_insert');
    await db.execute('DROP TRIGGER invalidate_series_metadata_title');
    await db.execute('DROP TABLE series_metadata_cache');
    await db.execute('DROP TRIGGER invalidate_movie_metadata_source');
    await db.execute('DROP TABLE movie_provider_bindings');
    await db.execute('DROP TABLE movie_metadata_cache');
    await db.delete('schema_migrations', where: 'version = 14');
    await db.execute('PRAGMA user_version = 13');
    await adapter.close();
    final upgraded = await adapter.database;
    expect(
      (await upgraded.rawQuery('PRAGMA user_version')).single.values.single,
      17,
    );
    expect(await upgraded.query('items'), before);
    expect(
      (await upgraded.query(
        'schema_migrations',
        where: 'version = ?',
        whereArgs: [const MovieMetadataV14Migration().version],
      )).single['name'],
      'movie_metadata_v14',
    );
    await resolve();
  });
}

PlaylistSourceConfig _config(
  String id, {
  String password = 'private-password',
}) => PlaylistSourceConfig.xtream(
  playlistId: id,
  name: 'Fixture',
  server: 'https://provider.example',
  username: 'account-name',
  password: password,
  verificationRecord: SourceVerificationRecord(
    verification: SourceVerificationState.verified,
    accountState: SourceAccountState.active,
    checkedAt: DateTime.utc(2026, 11, 25),
    apiEnabled: true,
  ),
);

Future<void> _item(Database db, String playlist, int id) async {
  await db.insert('groups', {
    'id': id,
    'playlist_id': playlist,
    'kind': 2,
    'title': 'Movies $id',
    'sort_title': 'movies',
    'ord': 0,
  });
  await db.insert('items', {
    'id': id,
    'playlist_id': playlist,
    'item_key': id,
    'content_hash': 123,
    'ord': 0,
    'kind': 2,
    'group_id': id,
    'title': 'Fixture Movie',
    'sort_title': 'fixture movie',
    'stream_url':
        'https://provider.example/movie/account-name/private-password/$id.mp4',
  });
  await db.rawInsert('INSERT INTO items_fts(rowid, title) VALUES (?, ?)', [
    id,
    'Fixture Movie',
  ]);
}

MovieMetadataResult _metadata(String plot) => MovieMetadataResult(
  metadata: MovieMetadata(
    fields: {MovieMetadataField.plot: plot},
    sources: {MovieMetadataField.plot: 'xtream'},
  ),
);

class _Provider implements MovieMetadataProvider {
  _Provider({this.id = 'xtream'});
  @override
  final String id;
  int calls = 0;
  final subjects = <MovieMetadataSubject>[];
  MetadataCancellation? operation;
  Completer<void> started = Completer<void>();
  Completer<MovieMetadataResult>? gate;
  MovieMetadataResult result = _metadata('Provider plot');
  @override
  bool supports(MovieMetadataSubject subject) => true;
  @override
  Future<MovieMetadataResult> fetch(
    MovieMetadataSubject subject,
    MetadataCancellation cancellation,
  ) async {
    calls++;
    subjects.add(subject);
    operation = cancellation;
    if (!started.isCompleted) started.complete();
    return gate?.future ?? result;
  }
}

class _Secrets implements PlaylistSecretStore {
  final values = <String, String>{};
  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => values[key];
  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }
}

class _VodTransport implements XtreamAuthTransport {
  Uri? uri;
  bool closed = false;
  int requests = 0;
  @override
  Future<XtreamAuthResponse> get(Uri authenticatedUri) async {
    uri = authenticatedUri;
    requests++;
    return XtreamAuthResponse(
      statusCode: 200,
      body: Stream.value(
        utf8.encode(
          jsonEncode({
            'movie_data': {'stream_id': '42'},
            'info': {'plot': 'API plot'},
          }),
        ),
      ),
    );
  }

  @override
  void close() {
    closed = true;
  }
}
