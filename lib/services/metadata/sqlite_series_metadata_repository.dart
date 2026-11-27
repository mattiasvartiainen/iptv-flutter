import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite_common/sqlite_api.dart';

import '../logging/app_logger.dart';
import '../storage/storage_contracts.dart';
import '../xtream/xtream_api_client.dart';
import '../xtream/xtream_authentication.dart';
import '../xtream/xtream_movie_metadata_provider.dart';
import '../xtream/xtream_series_metadata.dart';
import 'series_metadata.dart';

class SqliteSeriesMetadataRepository implements SeriesMetadataRepository {
  SqliteSeriesMetadataRepository({
    required this.database,
    required this.resolveCredentials,
    required this.client,
    this.logger = const DebugAppLogger(),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final DatabaseAdapter database;
  final XtreamCredentialResolver resolveCredentials;
  final XtreamApiClient client;
  final AppLogger logger;
  final DateTime Function() now;
  final _pending = <(String, String, int, String), _SeriesWork>{};
  final _tails = <(String, int), Future<void>>{};
  final _retryAt = <(String, int), DateTime>{};

  @visibleForTesting
  int debugActiveReaders(SeriesMetadataSubject subject, int revision) =>
      _pending[(subject.playlistId, subject.seriesId, revision, subject.locale)]
          ?.readers ??
      0;

  @override
  Stream<SeriesMetadataResult> resolve(
    SeriesMetadataSubject subject, {
    required MetadataCancellation cancellation,
    bool forceRefresh = false,
  }) async* {
    _SeriesWork? work;
    (String, String, int, String)? key;
    try {
      final db = await database.database;
      final rows = await db.rawQuery(
        '''
SELECT s.title, g.title AS group_title, p.source_revision
FROM series_v8 s JOIN playlists p ON p.id = s.playlist_id
JOIN groups g ON g.id = s.group_id
WHERE s.series_key = ? AND s.playlist_id = ? AND p.enabled = 1
  AND p.source_api_enabled = 1 AND p.source_verification = 'verified'
''',
        [subject.seriesId, subject.playlistId],
      );
      if (cancellation.isCancelled) return;
      if (rows.isEmpty) {
        yield const SeriesMetadataResult(failure: MetadataFailure.unverified);
        return;
      }
      final revision = rows.single['source_revision']! as int;
      final credentials = await Future.any<XtreamCredentials?>([
        resolveCredentials(subject.playlistId, revision),
        cancellation.whenCancelled.then((_) => null),
      ]);
      if (cancellation.isCancelled) return;
      if (credentials == null) {
        yield const SeriesMetadataResult(failure: MetadataFailure.unverified);
        return;
      }
      final episodes = await db.query(
        'items',
        columns: ['id', 'stream_url'],
        where: 'playlist_id = ? AND series_key = ? AND kind = 3',
        whereArgs: [subject.playlistId, subject.seriesId],
        orderBy: 'id',
        limit: 20,
      );
      final ids = <String>{};
      for (final episode in episodes) {
        final id = xtreamStreamId(
          episode['stream_url']! as String,
          credentials,
          kind: 'series',
        );
        if (id != null) ids.add(id);
      }
      if (ids.isEmpty || ids.length != episodes.length) {
        yield const SeriesMetadataResult(failure: MetadataFailure.unmapped);
        return;
      }
      final binding = _SeriesBinding(
        subject,
        revision,
        rows.single['title']! as String,
        rows.single['group_title']! as String,
        ids,
        jsonEncode(episodes),
        credentials,
      );
      if (!await _current(binding) || cancellation.isCancelled) return;
      final cached = await db.query(
        'series_metadata_cache',
        where:
            'playlist_id = ? AND series_key = ? AND revision = ? AND locale = ?',
        whereArgs: [
          subject.playlistId,
          subject.seriesId,
          revision,
          subject.locale,
        ],
      );
      SeriesMetadataResult? stale;
      if (cached.isNotEmpty) {
        final row = cached.single;
        final decoded = jsonDecode(row['payload']! as String);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid series cache');
        }
        final fields = <ContentMetadataField, String>{};
        for (final entry in decoded.entries) {
          final field = ContentMetadataField.values
              .where((field) => field.name == entry.key)
              .firstOrNull;
          if (field == null || entry.value is! String) {
            throw const FormatException('Invalid field');
          }
          final value = entry.value as String;
          if (const [
                ContentMetadataField.poster,
                ContentMetadataField.backdrop,
              ].contains(field) &&
              safeArtworkUrl(value) == null) {
            throw const FormatException('Invalid artwork');
          }
          fields[field] = value;
        }
        stale = SeriesMetadataResult(
          metadata: ContentMetadata(
            fields: fields,
            sources: {for (final field in fields.keys) field: 'xtream'},
          ),
          providerSeriesId: row['provider_id']! as String,
          isStale: true,
          isRefreshing: true,
        );
        final fresh =
            now().millisecondsSinceEpoch - (row['fetched_at']! as int) <
            const Duration(days: 7).inMilliseconds;
        await db.update(
          'series_metadata_cache',
          {'accessed_at': now().millisecondsSinceEpoch},
          where:
              'playlist_id = ? AND series_key = ? AND revision = ? AND locale = ?',
          whereArgs: [
            subject.playlistId,
            subject.seriesId,
            revision,
            subject.locale,
          ],
        );
        if (!await _current(binding) || cancellation.isCancelled) return;
        if (fresh && !forceRefresh) {
          yield SeriesMetadataResult(
            metadata: stale.metadata,
            providerSeriesId: stale.providerSeriesId,
          );
          return;
        }
        yield stale;
      }
      key = (subject.playlistId, subject.seriesId, revision, subject.locale);
      work = _pending.putIfAbsent(key, () {
        final operation = XtreamCancellation();
        return _SeriesWork(
          operation,
          _fetch(binding, operation, stale?.providerSeriesId),
        );
      });
      work.readers++;
      final result = await Future.any([
        work.future,
        cancellation.whenCancelled.then(
          (_) => const SeriesMetadataResult(failure: MetadataFailure.cancelled),
        ),
      ]);
      if (cancellation.isCancelled || !await _current(binding)) return;
      yield SeriesMetadataResult(
        metadata: result.metadata ?? stale?.metadata,
        failure: result.failure,
        providerSeriesId: result.providerSeriesId ?? stale?.providerSeriesId,
        isStale: result.metadata == null && stale != null,
      );
    } on DatabaseException {
      logger.error('series_metadata_storage_failed');
      if (!cancellation.isCancelled) {
        yield const SeriesMetadataResult(failure: MetadataFailure.storage);
      }
    } on FormatException {
      logger.error('series_metadata_cache_invalid');
      try {
        await (await database.database).delete('series_metadata_cache',
          where: 'playlist_id = ? AND series_key = ? AND locale = ?',
          whereArgs: [subject.playlistId, subject.seriesId, subject.locale]);
      } on DatabaseException {
        logger.error('series_metadata_cache_cleanup_failed');
      }
      if (!cancellation.isCancelled) {
        yield const SeriesMetadataResult(failure: MetadataFailure.storage);
      }
    } finally {
      if (work != null && --work.readers == 0) {
        work.cancellation.cancel();
        if (identical(_pending[key], work)) _pending.remove(key);
      }
    }
  }

  Future<bool> _current(_SeriesBinding binding) async {
    final db = await database.database;
    final rows = await db.rawQuery(
      '''
SELECT 1 FROM series_v8 s JOIN playlists p ON p.id = s.playlist_id
WHERE s.series_key = ? AND s.playlist_id = ? AND s.title = ?
AND p.source_revision = ? AND p.source_api_enabled = 1
AND p.source_verification = 'verified' AND p.enabled = 1
''',
      [
        binding.subject.seriesId,
        binding.subject.playlistId,
        binding.title,
        binding.revision,
      ],
    );
    if (rows.isEmpty) return false;
    final episodes = await db.query(
      'items',
      columns: ['id', 'stream_url'],
      where: 'playlist_id = ? AND series_key = ? AND kind = 3',
      whereArgs: [binding.subject.playlistId, binding.subject.seriesId],
      orderBy: 'id',
      limit: 20,
    );
    return jsonEncode(episodes) == binding.evidence;
  }

  Future<SeriesMetadataResult> _fetch(
    _SeriesBinding binding,
    XtreamCancellation operation,
    String? knownId,
  ) async {
    final account = (binding.subject.playlistId, binding.revision);
    final previous = _tails[account];
    final completed = Completer<void>();
    _tails[account] = completed.future;
    try {
      if (previous != null) await previous;
      if (operation.isCancelled || !await _current(binding)) {
        return const SeriesMetadataResult(failure: MetadataFailure.cancelled);
      }
      final retry = _retryAt[account];
      if (retry != null && retry.isAfter(now())) {
        return const SeriesMetadataResult(failure: MetadataFailure.rateLimited);
      }
      _retryAt.remove(account);
      Future<XtreamSeriesResponse> request(
        String action, {
        String? category,
        String? id,
      }) async {
        final result = await client.seriesRequest(
          playlistId: binding.subject.playlistId,
          connectionRevision: binding.revision,
          action: action,
          cancellation: operation,
          title: binding.title,
          group: binding.group,
          categoryId: category,
          seriesId: id,
          episodeIds: binding.ids,
        );
        if (result.retryAfter case final delay? when delay > Duration.zero) {
          _retryAt[account] = now().add(delay);
        }
        return result;
      }

      final candidates = <String>{};
      if (knownId != null) {
        candidates.add(knownId);
      } else {
        final categories = await request('get_series_categories');
        if (categories.failure != null) {
          return SeriesMetadataResult(failure: categories.failure);
        }
        for (final category in categories.ids) {
          if (operation.isCancelled || !await _current(binding)) {
            return const SeriesMetadataResult(
              failure: MetadataFailure.cancelled,
            );
          }
          final shows = await request('get_series', category: category);
          if (shows.failure != null) {
            return SeriesMetadataResult(failure: shows.failure);
          }
          candidates.addAll(shows.ids);
        }
      }
      // A title is only a suggestion; episode membership validates the selected show.
      if (candidates.length != 1) {
        return const SeriesMetadataResult(failure: MetadataFailure.unmapped);
      }
      final response = await request('get_series_info', id: candidates.single);
      final result =
          response.result ?? SeriesMetadataResult(failure: response.failure);
      if (result.failure != null) {
        logger.info(
          'series_metadata_unavailable',
          context: {'failure': result.failure!.name},
        );
        return result;
      }
      if (operation.isCancelled || !await _current(binding)) {
        return const SeriesMetadataResult(failure: MetadataFailure.cancelled);
      }
      return await _store(binding, result, response.episodeIds, operation);
    } on DatabaseException {
      logger.error('series_metadata_storage_failed');
      return const SeriesMetadataResult(failure: MetadataFailure.storage);
    } finally {
      completed.complete(null);
      if (identical(_tails[account], completed.future)) {
        unawaited(_tails.remove(account));
      }
    }
  }

  Future<SeriesMetadataResult> _store(
    _SeriesBinding binding,
    SeriesMetadataResult result,
    Set<String> providerEpisodes,
    XtreamCancellation operation,
  ) async {
    final metadata = result.metadata;
    final payload = metadata == null ? null : jsonEncode({
      for (final entry in metadata.fields.entries)
        entry.key.name: entry.value,
    });
    return database.transaction((txn) async {
      final current = await txn.rawQuery(
        '''
SELECT 1 FROM playlists p JOIN series_v8 s ON s.playlist_id = p.id
WHERE p.id = ? AND p.source_revision = ? AND p.source_api_enabled = 1
AND p.source_verification = 'verified' AND s.series_key = ? AND p.enabled = 1
AND s.title = ?
''',
        [
          binding.subject.playlistId,
          binding.revision,
          binding.subject.seriesId,
          binding.title,
        ],
      );
      final episodes = await txn.query(
        'items',
        columns: ['id', 'stream_url'],
        where: 'playlist_id = ? AND series_key = ? AND kind = 3',
        whereArgs: [binding.subject.playlistId, binding.subject.seriesId],
        orderBy: 'id',
        limit: 20,
      );
      if (operation.isCancelled || current.isEmpty || jsonEncode(episodes) != binding.evidence) {
        return const SeriesMetadataResult(failure: MetadataFailure.cancelled);
      }
      final matches = await _membersMatch(txn, binding, providerEpisodes, operation);
      if (!matches) {
        return SeriesMetadataResult(failure: operation.isCancelled ?
          MetadataFailure.cancelled : MetadataFailure.unmapped);
      }
      if (operation.isCancelled) {
        return const SeriesMetadataResult(failure: MetadataFailure.cancelled);
      }
      if (payload == null) return result;
      final timestamp = now().millisecondsSinceEpoch;
      await txn.insert('series_metadata_cache', {
        'playlist_id': binding.subject.playlistId,
        'series_key': binding.subject.seriesId,
        'revision': binding.revision,
        'locale': binding.subject.locale,
        'provider_id': result.providerSeriesId,
        'payload': payload,
        'fetched_at': timestamp,
        'accessed_at': timestamp,
        'byte_size': utf8.encode(payload).length + 512,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.rawDelete('''
DELETE FROM series_metadata_cache WHERE fetched_at < ?
''', [timestamp - const Duration(days: 30).inMilliseconds]);
      await txn.rawDelete('''
DELETE FROM series_metadata_cache WHERE rowid IN (
SELECT rowid FROM (SELECT rowid, SUM(byte_size) OVER (
ORDER BY accessed_at DESC, rowid DESC) AS total FROM series_metadata_cache)
WHERE total > 52428800)
''');
      return result;
    });
  }

  Future<bool> _membersMatch(DatabaseExecutor db, _SeriesBinding binding,
    Set<String> providerEpisodes, XtreamCancellation operation) async {
    if (providerEpisodes.isEmpty) return false;
    int? lastId;
    while (true) {
      if (operation.isCancelled) return false;
      final rows = await db.query('items', columns: ['id', 'stream_url'],
        where: 'playlist_id = ? AND series_key = ? AND kind = 3'
          '${lastId == null ? '' : ' AND id > ?'}',
        whereArgs: [binding.subject.playlistId, binding.subject.seriesId, ?lastId],
        orderBy: 'id', limit: 100);
      for (final row in rows) {
        final id = xtreamStreamId(row['stream_url']! as String, binding.credentials, kind: 'series');
        if (id == null || !providerEpisodes.contains(id)) return false;
      }
      if (rows.length < 100) return lastId != null || rows.isNotEmpty;
      lastId = rows.last['id']! as int;
    }
  }
}

class _SeriesBinding {
  const _SeriesBinding(
    this.subject,
    this.revision,
    this.title,
    this.group,
    this.ids,
    this.evidence,
    this.credentials,
  );
  final SeriesMetadataSubject subject;
  final int revision;
  final String title;
  final String group;
  final Set<String> ids;
  final String evidence;
  final XtreamCredentials credentials;
}

class _SeriesWork {
  _SeriesWork(this.cancellation, this.future);
  final XtreamCancellation cancellation;
  final Future<SeriesMetadataResult> future;
  int readers = 0;
}
