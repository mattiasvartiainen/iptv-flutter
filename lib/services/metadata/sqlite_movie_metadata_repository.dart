import 'dart:async';
import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../logging/app_logger.dart';
import '../storage/storage_contracts.dart';
import '../xtream/xtream_authentication.dart';
import '../xtream/xtream_movie_metadata_provider.dart';
import 'movie_metadata.dart';

class SqliteMovieMetadataRepository implements MovieMetadataRepository {
  SqliteMovieMetadataRepository({
    required DatabaseAdapter database,
    required XtreamCredentialResolver resolveCredentials,
    required List<MovieMetadataProvider> providers,
    AppLogger logger = const DebugAppLogger(),
    DateTime Function()? now,
    this.maxCacheBytes = 50 * 1024 * 1024,
  }) : _database = database,
       _resolveCredentials = resolveCredentials,
       _providers = List.unmodifiable(providers),
       _logger = logger,
       _now = now ?? DateTime.now {
    if (maxCacheBytes < 1) throw ArgumentError('Cache limit must be positive.');
  }

  final DatabaseAdapter _database;
  final XtreamCredentialResolver _resolveCredentials;
  final List<MovieMetadataProvider> _providers;
  final AppLogger _logger;
  final DateTime Function() _now;
  final int maxCacheBytes;
  final _pending = <(String, String, int, String), _PendingMovie>{};
  final _accountTails = <(String, int), Future<void>>{};
  final _retryAt = <(String, int), DateTime>{};

  @override
  Stream<MovieMetadataResult> resolve(
    MovieMetadataSubject subject, {
    required MetadataCancellation cancellation,
    bool forceRefresh = false,
  }) async* {
    _PendingMovie? lease;
    (String, String, int, String)? key;
    try {
      final db = await _database.database;
      final rows = await db.rawQuery(
        '''
SELECT i.stream_url, i.kind, p.source_revision, p.source_api_enabled,
       p.source_verification, p.enabled
FROM items i JOIN playlists p ON p.id = i.playlist_id
WHERE i.id = ? AND i.playlist_id = ?
''',
        [subject.itemId, subject.playlistId],
      );
      if (cancellation.isCancelled) return;
      if (rows.isEmpty) {
        yield const MovieMetadataResult(failure: MetadataFailure.notFound);
        return;
      }
      final row = rows.single;
      if (row['kind'] != 2) {
        yield const MovieMetadataResult(failure: MetadataFailure.notMovie);
        return;
      }
      if (row['source_api_enabled'] != 1 ||
          row['source_verification'] != 'verified' ||
          row['enabled'] != 1) {
        yield const MovieMetadataResult(failure: MetadataFailure.unverified);
        return;
      }
      final revision = row['source_revision']! as int;
      final credentials = await Future.any<XtreamCredentials?>([
        _resolveCredentials(subject.playlistId, revision),
        cancellation.whenCancelled.then((_) => null),
      ]);
      if (cancellation.isCancelled) return;
      if (credentials == null) {
        yield const MovieMetadataResult(failure: MetadataFailure.unverified);
        return;
      }
      final movieId = xtreamMovieId(row['stream_url']! as String, credentials);
      if (movieId == null) {
        yield const MovieMetadataResult(failure: MetadataFailure.unmapped);
        return;
      }
      final prepared = MovieMetadataSubject(
        playlistId: subject.playlistId,
        itemId: subject.itemId,
        locale: subject.locale,
        connectionRevision: revision,
        providerMovieId: movieId,
      );
      key = (subject.playlistId, subject.itemId, revision, subject.locale);
      final args = [
        subject.playlistId,
        subject.itemId,
        revision,
        subject.locale,
      ];
      final cached = await db.query(
        'movie_metadata_cache',
        where:
            'playlist_id = ? AND item_id = ? AND revision = ? AND locale = ?',
        whereArgs: args,
      );
      MovieMetadata? stale;
      if (cached.isNotEmpty) {
        final cache = cached.single;
        MetadataFailure? cachedFailure;
        var fresh = false;
        try {
          final payload = cache['payload'];
          final expiresAt = cache['expires_at'];
          if ((payload != null && payload is! String) || expiresAt is! int) {
            throw const FormatException('Invalid cache row');
          }
          stale = _decodeCache(payload is String ? payload : null);
          fresh = expiresAt > _now().millisecondsSinceEpoch;
          final failure = cache['failure'];
          if (failure != null) {
            cachedFailure = MetadataFailure.values
                .where((value) => value.name == failure)
                .firstOrNull;
            if (cachedFailure == null) {
              throw const FormatException('Invalid cached failure');
            }
          }
        } on FormatException {
          _logger.error('movie_metadata_cache_invalid');
          await db.delete(
            'movie_metadata_cache',
            where:
                'playlist_id = ? AND item_id = ? AND revision = ? AND locale = ?',
            whereArgs: args,
          );
          if (!forceRefresh) {
            if (!cancellation.isCancelled) {
              yield const MovieMetadataResult(failure: MetadataFailure.storage);
            }
            return;
          }
          stale = null;
          fresh = false;
        }
        await db.update(
          'movie_metadata_cache',
          {'accessed_at': _now().millisecondsSinceEpoch},
          where:
              'playlist_id = ? AND item_id = ? AND revision = ? AND locale = ?',
          whereArgs: args,
        );
        if (!await _current(prepared) || cancellation.isCancelled) return;
        if (fresh && !forceRefresh) {
          yield MovieMetadataResult(metadata: stale, failure: cachedFailure);
          return;
        }
        if (stale != null) {
          yield MovieMetadataResult(
            metadata: stale,
            isStale: true,
            isRefreshing: true,
          );
        }
      }
      if (cancellation.isCancelled) return;
      lease = _pending.putIfAbsent(key, () {
        final operation = MetadataCancellation();
        return _PendingMovie(operation, _schedule(prepared, operation));
      });
      lease.readers++;
      final result = await Future.any([
        lease.future,
        cancellation.whenCancelled.then(
          (_) => const MovieMetadataResult(failure: MetadataFailure.cancelled),
        ),
      ]);
      if (cancellation.isCancelled || !await _current(prepared)) return;
      yield MovieMetadataResult(
        metadata: result.metadata ?? stale,
        failure: result.failure,
        isStale: result.metadata == null && stale != null,
      );
    } on DatabaseException {
      _logger.error('movie_metadata_storage_failed');
      if (!cancellation.isCancelled) {
        yield const MovieMetadataResult(failure: MetadataFailure.storage);
      }
    } on FormatException {
      _logger.error('movie_metadata_cache_invalid');
      if (!cancellation.isCancelled) {
        yield const MovieMetadataResult(failure: MetadataFailure.storage);
      }
    } finally {
      if (lease != null && --lease.readers == 0) {
        lease.cancellation.cancel();
        if (identical(_pending[key], lease)) _pending.remove(key);
      }
    }
  }

  Future<bool> _current(MovieMetadataSubject subject) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
SELECT 1 FROM playlists p JOIN items i ON i.playlist_id = p.id
WHERE p.id = ? AND p.source_revision = ? AND p.source_api_enabled = 1
  AND p.source_verification = 'verified' AND p.enabled = 1
  AND i.id = ? AND i.kind = 2
''',
      [subject.playlistId, subject.connectionRevision, subject.itemId],
    );
    return rows.isNotEmpty;
  }

  Future<MovieMetadataResult> _schedule(
    MovieMetadataSubject subject,
    MetadataCancellation cancellation,
  ) async {
    final account = (subject.playlistId, subject.connectionRevision);
    final previous = _accountTails[account];
    final finished = Completer<void>();
    _accountTails[account] = finished.future;
    try {
      if (previous != null) await previous;
      if (cancellation.isCancelled || !await _current(subject)) {
        return const MovieMetadataResult(failure: MetadataFailure.cancelled);
      }
      final retryAt = _retryAt[account];
      if (retryAt != null && retryAt.isAfter(_now())) {
        return MovieMetadataResult(
          failure: MetadataFailure.rateLimited,
          retryAfter: retryAt.difference(_now()),
        );
      }
      _retryAt.remove(account);
      MovieMetadata? metadata;
      MetadataFailure? failure;
      var verified = false;
      for (final provider in _providers) {
        if (!provider.supports(subject)) continue;
        final result = await provider.fetch(subject, cancellation);
        if (cancellation.isCancelled || !await _current(subject)) {
          return const MovieMetadataResult(failure: MetadataFailure.cancelled);
        }
        if (result.failure != null) {
          failure ??= result.failure;
          if (result.retryAfter case final delay? when delay > Duration.zero) {
            _retryAt[account] = _now().add(delay);
          }
          _logger.info(
            'movie_metadata_provider_unavailable',
            context: {'provider': provider.id, 'failure': result.failure!.name},
          );
        }
        if (result.metadata != null) {
          metadata = metadata?.fillMissing(result.metadata!) ?? result.metadata;
          if (provider.id == 'xtream' && result.failure == null) {
            verified = true;
          }
        }
      }
      failure ??= metadata == null ? MetadataFailure.unsupported : null;
      final result = MovieMetadataResult(metadata: metadata, failure: failure);
      if (metadata != null ||
          const [
            MetadataFailure.unsupported,
            MetadataFailure.notFound,
          ].contains(failure)) {
        await _store(subject, result, verified: verified);
      }
      return result;
    } on DatabaseException {
      _logger.error('movie_metadata_storage_failed');
      return const MovieMetadataResult(failure: MetadataFailure.storage);
    } finally {
      finished.complete(null);
      if (identical(_accountTails[account], finished.future)) {
        unawaited(_accountTails.remove(account));
      }
    }
  }

  Future<void> _store(
    MovieMetadataSubject subject,
    MovieMetadataResult result, {
    required bool verified,
  }) => _database.transaction((txn) async {
    final current = await txn.rawQuery(
      '''
SELECT 1 FROM playlists p JOIN items i ON i.playlist_id = p.id
WHERE p.id = ? AND p.source_revision = ? AND p.source_api_enabled = 1
  AND p.source_verification = 'verified' AND p.enabled = 1 AND i.id = ? AND i.kind = 2
''',
      [subject.playlistId, subject.connectionRevision, subject.itemId],
    );
    if (current.isEmpty) return;
    final metadata = result.metadata;
    final payload = metadata == null
        ? null
        : jsonEncode({
            'fields': {
              for (final entry in metadata.fields.entries)
                entry.key.name: entry.value,
            },
            'sources': {
              for (final entry in metadata.sources.entries)
                entry.key.name: entry.value,
            },
          });
    final size = (payload == null ? 0 : utf8.encode(payload).length) + 512;
    final now = _now().millisecondsSinceEpoch;
    if (verified) {
      await txn.insert('movie_provider_bindings', {
        'playlist_id': subject.playlistId,
        'item_id': subject.itemId,
        'revision': subject.connectionRevision,
        'provider': 'xtream',
        'provider_id': subject.providerMovieId,
        'evidence': 'verifiedDetail',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    if (size > maxCacheBytes) {
      _logger.info('movie_metadata_cache_entry_too_large');
      return;
    }
    await txn.insert('movie_metadata_cache', {
      'playlist_id': subject.playlistId,
      'item_id': subject.itemId,
      'revision': subject.connectionRevision,
      'locale': subject.locale,
      'payload': payload,
      'failure': result.failure?.name,
      'fetched_at': now,
      'accessed_at': now,
      'byte_size': size,
      'expires_at':
          now +
          (metadata == null
                  ? const Duration(minutes: 15)
                  : const Duration(days: 7))
              .inMilliseconds,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    await txn.delete(
      'movie_metadata_cache',
      where: 'fetched_at < ?',
      whereArgs: [now - const Duration(days: 30).inMilliseconds],
    );
    await txn.rawDelete(
      '''
DELETE FROM movie_metadata_cache WHERE rowid IN (
  SELECT rowid FROM (
    SELECT rowid, SUM(byte_size) OVER (
      ORDER BY accessed_at DESC, rowid DESC
    ) AS running_size FROM movie_metadata_cache
  ) WHERE running_size > ?
)
''',
      [maxCacheBytes],
    );
  });
}

MovieMetadata? _decodeCache(String? payload) {
  if (payload == null) return null;
  final decoded = jsonDecode(payload);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Invalid metadata');
  }
  Map<MovieMetadataField, String> fields(String key) {
    final values = decoded[key];
    if (values is! Map<String, dynamic>) {
      throw const FormatException('Invalid metadata');
    }
    final result = <MovieMetadataField, String>{};
    for (final entry in values.entries) {
      final field = MovieMetadataField.values
          .where((field) => field.name == entry.key)
          .firstOrNull;
      if (field == null || entry.value is! String) {
        throw const FormatException('Invalid metadata');
      }
      final value = entry.value as String;
      if (key == 'fields' &&
          const [
            MovieMetadataField.poster,
            MovieMetadataField.backdrop,
          ].contains(field) &&
          safeArtworkUrl(value) == null) {
        throw const FormatException('Invalid artwork');
      }
      result[field] = value;
    }
    return result;
  }

  return MovieMetadata(fields: fields('fields'), sources: fields('sources'));
}

class _PendingMovie {
  _PendingMovie(this.cancellation, this.future);
  final MetadataCancellation cancellation;
  final Future<MovieMetadataResult> future;
  int readers = 0;
}
