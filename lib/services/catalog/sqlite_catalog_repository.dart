import 'dart:async';
import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../models/content_item.dart';
import '../errors/app_issue.dart';
import '../storage/database_adapter.dart';
import '../storage/secure_storage_service.dart';
import '../storage/storage_contracts.dart';
import 'catalog_normalizer.dart';
import 'catalog_query.dart';
import 'catalog_query_service.dart';
import 'catalog_repository.dart';
import 'id_identity.dart';
import 'm3u_parser.dart';

class _ValidatedPlaylistItems {
  const _ValidatedPlaylistItems({
    required this.items,
    required this.rejections,
  });

  final List<ContentItem> items;
  final List<String> rejections;
}

class _ReconcileOutcome {
  const _ReconcileOutcome({
    required this.acceptedCount,
    required this.rejections,
  });

  final int acceptedCount;
  final List<String> rejections;
}

class SqliteCatalogRepository
    implements CatalogRepository, CatalogQueryService {
  SqliteCatalogRepository({
    PlaylistSource? source,
    DatabaseAdapter? databaseAdapter,
    PlaylistSecretStore? secretStore,
    this.useStagingImport = true,
    this.autoStartSearchIndexWorker = true,
  }) : _source = source ?? const HttpPlaylistSource(),
       _databaseAdapter = databaseAdapter ?? SqfliteDatabaseAdapter(),
       _secretStore = secretStore ?? InMemoryPlaylistSecretStore();

  final PlaylistSource _source;
  final DatabaseAdapter _databaseAdapter;
  final PlaylistSecretStore _secretStore;
  final bool useStagingImport;

  /// When false, a successful import only queues search-index changes and
  /// leaves draining to an explicit [processSearchIndexQueue] call. Useful in
  /// tests that need to assert on queued-but-undrained state.
  final bool autoStartSearchIndexWorker;

  /// Playlists with a search-index drain already in flight; prevents a
  /// second refresh from starting a competing worker for the same playlist.
  final Set<String> _indexingPlaylists = {};

  final Set<String> _pausedIndexingPlaylists = {};

  /// Default batch size for [processSearchIndexQueue]. Each batch costs a
  /// fixed handful of set-based statements, so it is sized to bound the
  /// transaction rather than the statement count.
  static const int searchIndexBatchSize = 2000;

  /// Upper bound on operations queued into a single `Batch` during import.
  /// Keeps peak Dart-side memory and the platform-channel message size
  /// bounded regardless of playlist size (a 500k-item playlist would
  /// otherwise queue millions of operations into one commit).
  static const int _importBatchChunkSize = 2000;

  /// Upper bound on ids per `DELETE ... WHERE id IN (...)` statement, well
  /// under SQLite's default bound parameter limit.
  static const int _deleteChunkSize = 500;

  /// Staged rows per multi-row INSERT. With 24 columns this stays under the
  /// 999-parameter limit of older SQLite builds, which some TV platforms
  /// still ship.
  static const int _stagingRowsPerStatement = 40;

  /// In-flight imports keyed by resolved playlist id. A second call for the
  /// same playlist while one is running joins it instead of racing a second
  /// writer transaction on the shared connection (that race is what caused
  /// the "database has been locked" warning during concurrent refreshes).
  final Map<String, Future<CatalogLoadResult>> _inFlightLoads = {};

  /// When set, each reconcile stage prints its wall time. Used by
  /// tool/benchmark_import.dart to attribute import cost to a statement.
  static void Function(String stage, Duration elapsed)? onImportStageTiming;

  /// Notified when the set-based reconcile fails and the import degrades to
  /// the Dart-loop path. Correctness is preserved either way, but the slow
  /// path is orders of magnitude more expensive, so this must not go unseen.
  static void Function(Object error)? onStagingReconcileFallback;

  static Future<T> _stage<T>(String name, Future<T> Function() body) async {
    final report = onImportStageTiming;
    if (report == null) return body();
    final stopwatch = Stopwatch()..start();
    final result = await body();
    report(name, stopwatch.elapsed);
    return result;
  }

  @override
  Future<CatalogLoadResult> load({
    required String playlistUrl,
    String? playlistId,
    String? playlistName,
    CatalogLoadPolicy policy = CatalogLoadPolicy.cacheFirst,
    CatalogImportProgressCallback? onProgress,
  }) async {
    final resolvedPlaylistId =
        playlistId ?? await _resolvePlaylistId(playlistUrl);

    final inFlight = _inFlightLoads[resolvedPlaylistId];
    if (inFlight != null) return inFlight;

    _pausedIndexingPlaylists.add(resolvedPlaylistId);
    final future = _loadInternal(
      playlistUrl: playlistUrl,
      playlistId: resolvedPlaylistId,
      playlistName: playlistName,
      policy: policy,
      onProgress: onProgress,
    );
    _inFlightLoads[resolvedPlaylistId] = future;
    late final CatalogLoadResult result;
    try {
      result = await future;
    } finally {
      _inFlightLoads.remove(resolvedPlaylistId);
      _pausedIndexingPlaylists.remove(resolvedPlaylistId);
    }
    _startSearchIndexWorker(resolvedPlaylistId);
    return result;
  }

  Future<CatalogLoadResult> _loadInternal({
    required String playlistUrl,
    required String playlistId,
    String? playlistName,
    required CatalogLoadPolicy policy,
    CatalogImportProgressCallback? onProgress,
  }) async {
    final resolvedPlaylistId = playlistId;
    final resolvedPlaylistName = playlistName ?? 'Primary Playlist';
    final now = DateTime.now().toUtc().toIso8601String();
    final secureStorageKey = _secureStorageKey(resolvedPlaylistId);
    final db = await _databaseAdapter.database;
    final cachedItemCount = await _countCachedItems(
      db,
      playlistId: resolvedPlaylistId,
    );

    if (policy == CatalogLoadPolicy.cacheOnly) {
      return CatalogLoadResult(
        playlistId: resolvedPlaylistId,
        itemCount: cachedItemCount,
      );
    }

    if (policy == CatalogLoadPolicy.cacheFirst && cachedItemCount > 0) {
      final refreshDue = await _isRefreshDue(
        db,
        playlistId: resolvedPlaylistId,
      );
      if (!refreshDue) {
        return CatalogLoadResult(
          playlistId: resolvedPlaylistId,
          itemCount: cachedItemCount,
        );
      }
    }

    try {
      final refreshStartedAt = DateTime.now();
      final text = await _source.fetch(
        playlistUrl,
        onProgress: (received, total) => onProgress?.call(
          CatalogImportProgress(
            phase: CatalogImportPhase.downloading,
            startedAt: refreshStartedAt,
            current: received,
            total: total,
          ),
        ),
      );
      final parsed = const M3uParser().parse(text, sourceUrl: playlistUrl);

      if (parsed.isEmpty) {
        throw AppIssueException(
          const AppIssue(
            kind: AppIssueKind.playlistEmpty,
            source: AppIssueSource.playlistImport,
            title: 'Playlist is empty',
            message: 'The playlist did not contain any playable items.',
            retryable: false,
          ),
        );
      }
      final validated = _validateItems(parsed);
      if (validated.items.isEmpty) {
        throw AppIssueException(
          AppIssue(
            kind: AppIssueKind.playlistFormatInvalid,
            source: AppIssueSource.playlistImport,
            title: 'Playlist contains no valid items',
            message:
                'Every playlist entry was missing a valid title or stream URL.',
            details: validated.rejections.join('\n'),
            retryable: false,
          ),
        );
      }

      final storedSource = await _secretStore.read(key: secureStorageKey);
      if (storedSource == null || storedSource.isEmpty) {
        await _secretStore.write(key: secureStorageKey, value: playlistUrl);
      }

      var stagedRows = 0;
      var stagedDurationMs = 0;
      final startedImport = DateTime.now().toUtc();

      final updatedItems = await _databaseAdapter
          .transaction((db) async {
            await _upsertPlaylistRow(
              db,
              playlistId: resolvedPlaylistId,
              values: {
                'id': resolvedPlaylistId,
                'name': resolvedPlaylistName,
                'secure_storage_key': secureStorageKey,
                'source_url_redacted': _redactUrl(playlistUrl),
                'enabled': 1,
                'created_at': now,
                'updated_at': now,
                'last_import_started_at': now,
                'last_import_completed_at': null,
                'last_import_staged_rows': null,
                'last_import_staged_duration_ms': null,
                'last_import_status': 'running',
                'last_import_error': null,
              },
            );

            await db.insert('playlist_settings', {
              'playlist_id': resolvedPlaylistId,
              'refresh_enabled': 1,
              'refresh_mode': 'weekly',
              'refresh_interval_hours': 168,
              'last_refresh_at': null,
              'next_refresh_at': null,
              'last_refresh_status': null,
              'updated_at': now,
            }, conflictAlgorithm: ConflictAlgorithm.ignore);

            final outcome = await _reconcileResiliently(
              db: db,
              playlistId: resolvedPlaylistId,
              now: now,
              validated: validated,
              refreshStartedAt: refreshStartedAt,
              onProgress: onProgress,
            );

            final stageComplete = DateTime.now().toUtc();
            stagedRows = outcome.acceptedCount;
            stagedDurationMs = stageComplete
                .difference(startedImport)
                .inMilliseconds;

            await db.rawUpdate(
              '''
UPDATE playlists
SET name = ?,
    secure_storage_key = ?,
    source_url_redacted = ?,
    enabled = ?,
    created_at = ?,
    updated_at = ?,
    last_import_started_at = ?,
    last_import_completed_at = ?,
    last_import_staged_rows = ?,
    last_import_staged_duration_ms = ?,
    last_import_status = ?,
    last_import_error = ?,
    search_index_dirty = 1
WHERE id = ?
''',
              [
                resolvedPlaylistName,
                secureStorageKey,
                _redactUrl(playlistUrl),
                1,
                now,
                stageComplete.toIso8601String(),
                now,
                stageComplete.toIso8601String(),
                stagedRows,
                stagedDurationMs,
                'success',
                outcome.rejections.isEmpty
                    ? null
                    : '${outcome.rejections.length} invalid entries skipped: ${outcome.rejections.take(3).join('; ')}',
                resolvedPlaylistId,
              ],
            );

            await _markRefreshSuccess(
              db,
              playlistId: resolvedPlaylistId,
              completedAt: stageComplete,
            );

            return CatalogLoadResult(
              playlistId: resolvedPlaylistId,
              itemCount: outcome.acceptedCount,
            );
          })
          .catchError((Object error, StackTrace stackTrace) async {
            await _updateImportFailure(
              playlistId: resolvedPlaylistId,
              playlistUrl: playlistUrl,
              startedAt: startedImport,
              stagedRows: stagedRows,
              stagedDurationMs: stagedDurationMs,
              error: error,
            );
            throw error;
          });

      return updatedItems;
    } on AppIssueException {
      if (policy == CatalogLoadPolicy.cacheFirst && cachedItemCount > 0) {
        return CatalogLoadResult(
          playlistId: resolvedPlaylistId,
          itemCount: cachedItemCount,
        );
      }
      rethrow;
    } on TimeoutException catch (error, stackTrace) {
      if (policy == CatalogLoadPolicy.cacheFirst && cachedItemCount > 0) {
        return CatalogLoadResult(
          playlistId: resolvedPlaylistId,
          itemCount: cachedItemCount,
        );
      }
      throw AppIssueException(
        AppIssue(
          kind: AppIssueKind.timeout,
          source: AppIssueSource.playlistImport,
          title: 'Playlist timed out',
          message: 'The playlist took too long to download.',
          details: error.toString(),
        ),
        cause: error,
        stackTrace: stackTrace,
      );
    } on SocketException catch (error, stackTrace) {
      if (policy == CatalogLoadPolicy.cacheFirst && cachedItemCount > 0) {
        return CatalogLoadResult(
          playlistId: resolvedPlaylistId,
          itemCount: cachedItemCount,
        );
      }
      throw AppIssueException(
        AppIssue(
          kind: AppIssueKind.networkUnavailable,
          source: AppIssueSource.playlistImport,
          title: 'Network unavailable',
          message: 'Could not reach the playlist server.',
          details: error.toString(),
        ),
        cause: error,
        stackTrace: stackTrace,
      );
    } on HttpException catch (error, stackTrace) {
      if (policy == CatalogLoadPolicy.cacheFirst && cachedItemCount > 0) {
        return CatalogLoadResult(
          playlistId: resolvedPlaylistId,
          itemCount: cachedItemCount,
        );
      }
      throw AppIssueException(
        AppIssue(
          kind: AppIssueKind.networkUnavailable,
          source: AppIssueSource.playlistImport,
          title: 'Playlist request failed',
          message: 'The server returned an error while fetching the playlist.',
          details: error.toString(),
        ),
        cause: error,
        stackTrace: stackTrace,
      );
    } on FormatException catch (error, stackTrace) {
      if (policy == CatalogLoadPolicy.cacheFirst && cachedItemCount > 0) {
        return CatalogLoadResult(
          playlistId: resolvedPlaylistId,
          itemCount: cachedItemCount,
        );
      }
      throw AppIssueException(
        AppIssue(
          kind: AppIssueKind.playlistFormatInvalid,
          source: AppIssueSource.playlistImport,
          title: 'Playlist format invalid',
          message: 'The playlist could not be parsed.',
          details: error.toString(),
        ),
        cause: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      if (policy == CatalogLoadPolicy.cacheFirst && cachedItemCount > 0) {
        return CatalogLoadResult(
          playlistId: resolvedPlaylistId,
          itemCount: cachedItemCount,
        );
      }
      throw AppIssueException(
        AppIssue(
          kind: AppIssueKind.unknown,
          source: AppIssueSource.playlistImport,
          title: 'Import failed',
          message: 'Could not load that playlist. Try again.',
          details: error.toString(),
        ),
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<int> _countCachedItems(
    DatabaseExecutor db, {
    required String playlistId,
  }) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS item_count FROM media_items WHERE playlist_id = ?',
      [playlistId],
    );
    return (rows.single['item_count'] as num?)?.toInt() ?? 0;
  }

  // --- CatalogQueryService ---------------------------------------------------

  static const String _summaryColumns =
      'm.id AS id, m.title AS title, m.sort_title AS sort_title, '
      'm.content_type AS content_type, m.group_title AS group_title, '
      'm.logo_url AS logo_url, m.artwork_url AS artwork_url, '
      'm.source_index AS source_index';

  @override
  Future<CatalogPage<CatalogItemSummary>> queryItems(CatalogQuery query) async {
    final db = await _databaseAdapter.database;
    final ftsExpression = query.hasSearchTerm
        ? buildFtsPrefixQuery(query.searchTerm!)
        : null;

    // A search term that survives sanitising means no rows can match.
    if (query.hasSearchTerm && ftsExpression == null) {
      return CatalogPage<CatalogItemSummary>(
        items: const [],
        offset: query.offset,
        total: 0,
      );
    }

    final clauses = <String>['m.playlist_id = ?'];
    final args = <Object?>[query.playlistId];

    if (ftsExpression != null) {
      clauses.add('media_items_fts MATCH ?');
      args.add(ftsExpression);
    }
    if (query.kinds.isNotEmpty) {
      clauses.add(
        'm.content_type IN (${List.filled(query.kinds.length, '?').join(', ')})',
      );
      args.addAll(query.kinds.map((kind) => kind.storageValue));
    }
    if (query.group != null) {
      clauses.add('m.group_title = ?');
      args.add(query.group);
    }

    final from = ftsExpression != null
        ? 'media_items_fts JOIN media_items m ON m.id = media_items_fts.media_item_id'
        : 'media_items m';
    final where = clauses.join(' AND ');
    final orderBy = switch ((ftsExpression != null, query.sort)) {
      (true, _) => 'bm25(media_items_fts), m.sort_title, m.id',
      (false, CatalogSort.title) => 'm.sort_title, m.id',
      (false, CatalogSort.playlistOrder) => 'm.source_index, m.id',
    };

    final total = await _countRows(db, from: from, where: where, args: args);
    if (total == 0 || query.offset >= total) {
      return CatalogPage<CatalogItemSummary>(
        items: const [],
        offset: query.offset,
        total: total,
      );
    }

    final rows = await db.rawQuery(
      'SELECT $_summaryColumns FROM $from WHERE $where '
      'ORDER BY $orderBy LIMIT ? OFFSET ?',
      [...args, query.limit, query.offset],
    );

    return CatalogPage<CatalogItemSummary>(
      items: rows.map(CatalogItemSummary.fromRow).toList(growable: false),
      offset: query.offset,
      total: total,
    );
  }

  @override
  Future<List<CatalogItemSummary>> homePreview(
    String playlistId, {
    required CatalogItemKind kind,
    int limit = kHomePreviewCount,
  }) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT $_summaryColumns FROM media_items m '
      'WHERE m.playlist_id = ? AND m.content_type = ? '
      'ORDER BY m.sort_title, m.id LIMIT ?',
      [playlistId, kind.storageValue, limit],
    );
    return rows.map(CatalogItemSummary.fromRow).toList(growable: false);
  }

  @override
  Future<CatalogPage<SeriesSummary>> querySeries(
    String playlistId, {
    int offset = 0,
    int limit = kCatalogPageSize,
    String? searchTerm,
  }) async {
    final db = await _databaseAdapter.database;
    final clauses = <String>['s.playlist_id = ?'];
    final args = <Object?>[playlistId];

    final term = searchTerm?.trim();
    if (term != null && term.isNotEmpty) {
      clauses.add('s.sort_title LIKE ? ESCAPE ?');
      args
        ..add('%${_escapeLike(CatalogNormalizer.normalizeText(term))}%')
        ..add(r'\');
    }

    final where = clauses.join(' AND ');
    final total = await _countRows(
      db,
      from: 'series s',
      where: where,
      args: args,
    );
    if (total == 0 || offset >= total) {
      return CatalogPage<SeriesSummary>(
        items: const [],
        offset: offset,
        total: total,
      );
    }

    final rows = await db.rawQuery(
      'SELECT s.id AS id, s.title AS title, s.sort_title AS sort_title, '
      's.artwork_url AS artwork_url, '
      '(SELECT COUNT(*) FROM seasons se WHERE se.series_id = s.id) AS season_count, '
      '(SELECT COUNT(*) FROM episodes e WHERE e.series_id = s.id) AS episode_count '
      'FROM series s WHERE $where ORDER BY s.sort_title, s.id LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );

    return CatalogPage<SeriesSummary>(
      items: rows.map(SeriesSummary.fromRow).toList(growable: false),
      offset: offset,
      total: total,
    );
  }

  @override
  Future<List<SeasonSummary>> seasons(String seriesId) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      'SELECT se.id AS id, se.series_id AS series_id, '
      'se.season_number AS season_number, '
      '(SELECT COUNT(*) FROM episodes e WHERE e.season_id = se.id) AS episode_count '
      'FROM seasons se WHERE se.series_id = ? ORDER BY se.season_number',
      [seriesId],
    );
    return rows.map(SeasonSummary.fromRow).toList(growable: false);
  }

  @override
  Future<CatalogPage<CatalogItemSummary>> episodes(
    String seasonId, {
    int offset = 0,
    int limit = kCatalogPageSize,
  }) async {
    final db = await _databaseAdapter.database;
    const from = 'episodes e JOIN media_items m ON m.id = e.media_item_id';
    const where = 'e.season_id = ?';
    final args = <Object?>[seasonId];

    final total = await _countRows(db, from: from, where: where, args: args);
    if (total == 0 || offset >= total) {
      return CatalogPage<CatalogItemSummary>(
        items: const [],
        offset: offset,
        total: total,
      );
    }

    final rows = await db.rawQuery(
      'SELECT $_summaryColumns, e.episode_number AS episode_number FROM $from '
      'WHERE $where ORDER BY e.episode_number, m.id LIMIT ? OFFSET ?',
      [...args, limit, offset],
    );

    return CatalogPage<CatalogItemSummary>(
      items: rows.map(CatalogItemSummary.fromRow).toList(growable: false),
      offset: offset,
      total: total,
    );
  }

  @override
  Future<List<String>> groups(
    String playlistId, {
    List<CatalogItemKind> kinds = const [],
  }) async {
    final db = await _databaseAdapter.database;
    final clauses = <String>[
      'playlist_id = ?',
      "group_title IS NOT NULL",
      "group_title <> ''",
    ];
    final args = <Object?>[playlistId];
    if (kinds.isNotEmpty) {
      clauses.add(
        'content_type IN (${List.filled(kinds.length, '?').join(', ')})',
      );
      args.addAll(kinds.map((kind) => kind.storageValue));
    }

    final rows = await db.rawQuery(
      'SELECT DISTINCT group_title FROM media_items '
      'WHERE ${clauses.join(' AND ')} ORDER BY group_title',
      args,
    );
    return rows
        .map((row) => row['group_title'] as String)
        .toList(growable: false);
  }

  @override
  Future<ContentItem?> itemById(String itemId) async {
    final db = await _databaseAdapter.database;
    final rows = await db.query(
      'media_items',
      where: 'id = ?',
      whereArgs: [itemId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _mapRowToItem(rows.first);
  }

  Future<int> _countRows(
    DatabaseExecutor db, {
    required String from,
    required String where,
    required List<Object?> args,
  }) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS total FROM $from WHERE $where',
      args,
    );
    return (rows.first['total'] as int?) ?? 0;
  }

  String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  Future<bool> _isRefreshDue(
    DatabaseExecutor db, {
    required String playlistId,
  }) async {
    final rows = await db.query(
      'playlist_settings',
      columns: const ['refresh_enabled', 'refresh_mode', 'next_refresh_at'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (rows.isEmpty) return true;

    final row = rows.first;
    final refreshEnabled = (row['refresh_enabled'] as int? ?? 1) == 1;
    if (!refreshEnabled) return false;

    final refreshMode = (row['refresh_mode'] as String?) ?? 'weekly';
    if (refreshMode == 'manual') return false;

    final nextRefreshRaw = row['next_refresh_at'] as String?;
    if (nextRefreshRaw == null || nextRefreshRaw.isEmpty) return true;

    final nextRefreshAt = DateTime.tryParse(nextRefreshRaw)?.toUtc();
    if (nextRefreshAt == null) return true;

    final now = DateTime.now().toUtc();
    return now.isAfter(nextRefreshAt) || now.isAtSameMomentAs(nextRefreshAt);
  }

  Future<void> _markRefreshSuccess(
    DatabaseExecutor db, {
    required String playlistId,
    required DateTime completedAt,
  }) async {
    final completedIso = completedAt.toUtc().toIso8601String();
    final settingsRows = await db.query(
      'playlist_settings',
      columns: const ['refresh_interval_hours', 'refresh_enabled'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );

    String? nextRefreshIso;
    if (settingsRows.isNotEmpty) {
      final row = settingsRows.first;
      final refreshEnabled = (row['refresh_enabled'] as int? ?? 1) == 1;
      if (refreshEnabled) {
        final intervalHours = row['refresh_interval_hours'] as int? ?? 168;
        nextRefreshIso = completedAt
            .toUtc()
            .add(Duration(hours: intervalHours))
            .toIso8601String();
      }
    }

    await db.update(
      'playlist_settings',
      {
        'last_refresh_at': completedIso,
        'next_refresh_at': nextRefreshIso,
        'last_refresh_status': 'success',
        'updated_at': completedIso,
      },
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
  }

  _ValidatedPlaylistItems _validateItems(List<ContentItem> parsed) {
    final validItems = <ContentItem>[];
    final rejections = <String>[];

    for (final item in parsed) {
      final title = item.title.trim();
      final streamUrl = item.streamUrl.trim();
      final streamUri = Uri.tryParse(streamUrl);
      if (title.isEmpty) {
        rejections.add('Entry ${item.sourceIndex + 1} has no title');
        continue;
      }
      if (streamUri == null || !streamUri.hasScheme) {
        rejections.add(
          'Entry ${item.sourceIndex + 1} has an invalid stream URL',
        );
        continue;
      }
      validItems.add(item);
    }

    return _ValidatedPlaylistItems(
      items: List.unmodifiable(validItems),
      rejections: List.unmodifiable(rejections),
    );
  }

  Future<_ReconcileOutcome> _reconcileResiliently({
    required DatabaseExecutor db,
    required String playlistId,
    required String now,
    required _ValidatedPlaylistItems validated,
    required DateTime refreshStartedAt,
    CatalogImportProgressCallback? onProgress,
  }) async {
    if (!useStagingImport) {
      return _reconcileWithItemFallback(
        db: db,
        playlistId: playlistId,
        now: now,
        validated: validated,
        refreshStartedAt: refreshStartedAt,
      );
    }

    try {
      final acceptedCount = await _reconcileViaStagingSqlWithinSavepoint(
        db: db,
        playlistId: playlistId,
        now: now,
        parsed: validated.items,
        deleteStaleRows: validated.rejections.isEmpty,
        refreshStartedAt: refreshStartedAt,
        onProgress: onProgress,
      );
      return _ReconcileOutcome(
        acceptedCount: acceptedCount,
        rejections: validated.rejections,
      );
    } catch (error) {
      onStagingReconcileFallback?.call(error);
      // Before degrading to one savepoint per item — which is orders of
      // magnitude slower and unusable at playlist scale — retry the whole
      // playlist through the Dart-loop path. It only fails for a genuinely
      // bad row, which is the only case worth paying per-item isolation for.
      try {
        final acceptedCount = await _reconcileWithinSavepoint(
          db: db,
          playlistId: playlistId,
          now: now,
          parsed: validated.items,
          deleteStaleRows: validated.rejections.isEmpty,
          refreshStartedAt: refreshStartedAt,
          onProgress: onProgress,
        );
        return _ReconcileOutcome(
          acceptedCount: acceptedCount,
          rejections: validated.rejections,
        );
      } catch (_) {
        // Fall through to per-item isolation.
      }

      final acceptedItems = <ContentItem>[];
      final rejections = <String>[...validated.rejections];

      for (final item in validated.items) {
        try {
          await _reconcileWithinSavepoint(
            db: db,
            playlistId: playlistId,
            now: now,
            parsed: [item],
            deleteStaleRows: false,
            refreshStartedAt: refreshStartedAt,
          );
          acceptedItems.add(item);
        } catch (itemError) {
          rejections.add(
            'Entry ${item.sourceIndex + 1} was skipped: ${_conciseError(itemError)}',
          );
        }
      }

      if (acceptedItems.isEmpty) {
        rethrow;
      }

      return _ReconcileOutcome(
        acceptedCount: acceptedItems.length,
        rejections: List.unmodifiable(rejections),
      );
    }
  }

  Future<_ReconcileOutcome> _reconcileWithItemFallback({
    required DatabaseExecutor db,
    required String playlistId,
    required String now,
    required _ValidatedPlaylistItems validated,
    required DateTime refreshStartedAt,
  }) async {
    final acceptedItems = <ContentItem>[];
    final rejections = <String>[...validated.rejections];

    for (final item in validated.items) {
      try {
        await _reconcileWithinSavepoint(
          db: db,
          playlistId: playlistId,
          now: now,
          parsed: [item],
          deleteStaleRows: false,
          refreshStartedAt: refreshStartedAt,
        );
        acceptedItems.add(item);
      } catch (itemError) {
        rejections.add(
          'Entry ${item.sourceIndex + 1} was skipped: ${_conciseError(itemError)}',
        );
      }
    }

    if (acceptedItems.isEmpty) {
      throw StateError('No playlist items could be written to the database.');
    }

    return _ReconcileOutcome(
      acceptedCount: acceptedItems.length,
      rejections: List.unmodifiable(rejections),
    );
  }

  Future<int> _reconcileWithinSavepoint({
    required DatabaseExecutor db,
    required String playlistId,
    required String now,
    required List<ContentItem> parsed,
    required bool deleteStaleRows,
    required DateTime refreshStartedAt,
    CatalogImportProgressCallback? onProgress,
  }) async {
    await db.execute('SAVEPOINT catalog_import');
    try {
      final acceptedCount = await _reconcilePlaylistContent(
        db: db,
        playlistId: playlistId,
        now: now,
        parsed: parsed,
        deleteStaleRows: deleteStaleRows,
        refreshStartedAt: refreshStartedAt,
        onProgress: onProgress,
      );
      await db.execute('RELEASE SAVEPOINT catalog_import');
      return acceptedCount;
    } catch (_) {
      await db.execute('ROLLBACK TO SAVEPOINT catalog_import');
      await db.execute('RELEASE SAVEPOINT catalog_import');
      rethrow;
    }
  }

  String _conciseError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= 160 ? text : '${text.substring(0, 157)}...';
  }

  Future<int> _reconcileViaStagingSqlWithinSavepoint({
    required DatabaseExecutor db,
    required String playlistId,
    required String now,
    required List<ContentItem> parsed,
    required bool deleteStaleRows,
    required DateTime refreshStartedAt,
    CatalogImportProgressCallback? onProgress,
  }) async {
    await db.execute('SAVEPOINT catalog_import_staging');
    try {
      final acceptedCount = await _reconcileViaStagingSql(
        db: db,
        playlistId: playlistId,
        now: now,
        parsed: parsed,
        deleteStaleRows: deleteStaleRows,
        refreshStartedAt: refreshStartedAt,
        onProgress: onProgress,
      );
      await db.execute('RELEASE SAVEPOINT catalog_import_staging');
      return acceptedCount;
    } catch (_) {
      await db.execute('ROLLBACK TO SAVEPOINT catalog_import_staging');
      await db.execute('RELEASE SAVEPOINT catalog_import_staging');
      rethrow;
    }
  }

  /// Set-based reconcile: stream parsed rows into `import_staging_items`,
  /// resolve each row's target `media_items.id` with a single SQL COALESCE
  /// join (existing id -> provider hash -> stream_url|title|source_index
  /// signature -> new id), then upsert/delete every table with plain SQL
  /// operating on the whole staging set. Replaces preloading the entire
  /// existing catalog into Dart Sets/Maps — SQLite's own indexes do the
  /// O(n) diff work instead of a Dart loop. On any error this throws and
  /// the caller (`_reconcileResiliently`) falls back to the old per-item
  /// Dart-loop path, so constraint-violation resilience is unchanged.
  Future<int> _reconcileViaStagingSql({
    required DatabaseExecutor db,
    required String playlistId,
    required String now,
    required List<ContentItem> parsed,
    required bool deleteStaleRows,
    required DateTime refreshStartedAt,
    CatalogImportProgressCallback? onProgress,
  }) async {
    await db.delete(
      'import_staging_items',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );

    // A first import has nothing to reconcile against, so every staged row
    // can claim its own id up front and the resolve pass below is skipped.
    final isColdImport =
        await _countCachedItems(db, playlistId: playlistId) == 0;

    // Queuing plain inserts lets the index worker skip the removal half of a
    // reindex, but only if no index entry can already exist under a rowid
    // these rows are about to reuse — e.g. entries orphaned by a kill between
    // a catalog delete and the index drain.
    final indexIsEmpty =
        isColdImport &&
        (await db.rawQuery('SELECT 1 FROM media_items_fts LIMIT 1')).isEmpty;

    // Rows are appended to one multi-row INSERT rather than one statement
    // per row: at playlist scale the per-statement overhead dominates the
    // actual write. Column count is fixed, so the row cap keeps the bound
    // parameter count well under SQLite's limit.
    const columns = [
      'playlist_id',
      'source_index',
      'id',
      'content_type',
      'title',
      'sort_title',
      'description',
      'stream_url',
      'group_title',
      'logo_url',
      'artwork_url',
      'tvg_id',
      'tvg_name',
      'tvg_chno',
      'xui_id',
      'provider_item_hash',
      'category_id',
      'series_title',
      'series_id',
      'season_number',
      'season_id',
      'episode_number',
      'episode_id',
      'resolved_media_id',
    ];
    final rowPlaceholder = '(${_placeholders(columns.length)})';
    final insertPrefix =
        'INSERT OR REPLACE INTO import_staging_items '
        '(${columns.join(', ')}) VALUES ';
    final values = <Object?>[];
    var pendingRows = 0;

    Future<void> flushRows({bool force = false}) async {
      if (pendingRows == 0) return;
      if (!force && pendingRows < _stagingRowsPerStatement) return;
      await db.rawInsert(
        insertPrefix + List.filled(pendingRows, rowPlaceholder).join(', '),
        values,
      );
      values.clear();
      pendingRows = 0;
    }

    onProgress?.call(
      CatalogImportProgress(
        phase: CatalogImportPhase.importing,
        startedAt: refreshStartedAt,
        current: 0,
        total: parsed.length,
      ),
    );
    const progressReportInterval = 200;
    final stageStopwatch = Stopwatch()..start();

    for (var index = 0; index < parsed.length; index++) {
      final item = parsed[index];
      if (onProgress != null &&
          index > 0 &&
          index % progressReportInterval == 0) {
        onProgress(
          CatalogImportProgress(
            phase: CatalogImportPhase.importing,
            startedAt: refreshStartedAt,
            current: index,
            total: parsed.length,
          ),
        );
      }

      final group = CatalogNormalizer.canonicalGroup(item.group);
      final categoryId = _stableId('category|$playlistId|$group');
      var contentType = item.type == ContentType.live ? 'live' : 'movie';

      String? seriesTitle;
      String? seriesId;
      String? seasonId;
      String? episodeId;
      int? seasonNumber;
      int? episodeNumber;
      final episodeMatch = CatalogNormalizer.parseSeriesEpisodeTitle(
        item.title,
      );
      if (episodeMatch != null && episodeMatch.seriesTitle.isNotEmpty) {
        contentType = 'episode';
        seriesTitle = episodeMatch.seriesTitle;
        seasonNumber = episodeMatch.seasonNumber;
        episodeNumber = episodeMatch.episodeNumber;
        seriesId = _stableId('series|$playlistId|$seriesTitle');
        seasonId = _stableId('season|$seriesId|$seasonNumber');
        episodeId = _stableId('episode|$seasonId|$episodeNumber');
      }

      values
        ..add(playlistId)
        ..add(item.sourceIndex)
        ..add(item.id)
        ..add(contentType)
        ..add(item.title)
        ..add(CatalogNormalizer.normalizeText(item.title))
        ..add(item.description)
        ..add(item.streamUrl)
        ..add(group)
        ..add(item.logoUrl)
        ..add(item.posterUrl)
        ..add(item.metadata['tvg-id'])
        ..add(item.metadata['tvg-name'])
        ..add(item.metadata['tvg-chno'])
        ..add(item.metadata['xui-id'])
        ..add(
          CatalogNormalizer.providerItemHash(
            streamUrl: item.streamUrl,
            title: item.title,
            group: item.group,
          ),
        )
        ..add(categoryId)
        ..add(seriesTitle)
        ..add(seriesId)
        ..add(seasonNumber)
        ..add(seasonId)
        ..add(episodeNumber)
        ..add(episodeId)
        ..add(isColdImport ? item.id : null);
      pendingRows++;
      await flushRows();
    }
    await flushRows(force: true);
    if (onImportStageTiming != null) {
      onImportStageTiming!('stage-rows', stageStopwatch.elapsed);
    }

    // One SQL statement resolves every row's target media_items.id instead
    // of three Dart-side full-table preloads + per-item hash-map lookups.
    // Both branches are index lookups: the media_items primary key, then the
    // UNIQUE (playlist_id, stream_url, title) identity constraint. Matching
    // on url+title without source_index means a channel that merely moved
    // position keeps its id, and so keeps its favorites and watch history.
    if (!isColdImport) {
      await _stage(
        'resolve-identity',
        () => db.rawUpdate(
          '''
UPDATE import_staging_items
SET resolved_media_id = COALESCE(
  (SELECT m.id FROM media_items m
     WHERE m.playlist_id = import_staging_items.playlist_id
       AND m.id = import_staging_items.id),
  (SELECT m.id FROM media_items m
     WHERE m.playlist_id = import_staging_items.playlist_id
       AND m.stream_url = import_staging_items.stream_url
       AND m.title = import_staging_items.title),
  import_staging_items.id
)
WHERE import_staging_items.playlist_id = ?
''',
          [playlistId],
        ),
      );
    }
    await _stage(
      'dedupe-resolved-id',
      () => db.rawUpdate(
        '''
UPDATE import_staging_items
SET resolved_media_id = NULL
WHERE playlist_id = ? AND source_index NOT IN (
  SELECT MIN(source_index)
  FROM import_staging_items
  WHERE playlist_id = ?
  GROUP BY resolved_media_id
)
''',
        [playlistId, playlistId],
      ),
    );
    await _stage(
      'dedupe-url-title',
      () => db.rawUpdate(
        '''
UPDATE import_staging_items
SET resolved_media_id = NULL
WHERE playlist_id = ? AND source_index NOT IN (
  SELECT MIN(source_index)
  FROM import_staging_items
  WHERE playlist_id = ? AND resolved_media_id IS NOT NULL
  GROUP BY stream_url, title
)
''',
        [playlistId, playlistId],
      ),
    );

    await _stage(
      'upsert-categories',
      () => db.rawInsert(
        '''
INSERT INTO categories (
  id, playlist_id, provider_group_title, normalized_name, content_kind,
  created_at, updated_at
)
SELECT category_id, playlist_id, MAX(group_title), LOWER(TRIM(MAX(group_title))),
  'unknown', ?, ?
FROM import_staging_items
WHERE playlist_id = ?
GROUP BY category_id, playlist_id
ON CONFLICT(id) DO UPDATE SET
  provider_group_title = excluded.provider_group_title,
  normalized_name = excluded.normalized_name,
  updated_at = excluded.updated_at
''',
        [now, now, playlistId],
      ),
    );

    await _stage(
      'upsert-series',
      () => db.rawInsert(
        '''
INSERT INTO series (id, playlist_id, title, sort_title, artwork_url, created_at, updated_at)
SELECT series_id, playlist_id, MAX(series_title), LOWER(TRIM(MAX(series_title))),
  MAX(artwork_url), ?, ?
FROM import_staging_items
WHERE playlist_id = ? AND series_id IS NOT NULL
GROUP BY series_id, playlist_id
ON CONFLICT(id) DO UPDATE SET
  title = excluded.title,
  sort_title = excluded.sort_title,
  artwork_url = excluded.artwork_url,
  updated_at = excluded.updated_at
''',
        [now, now, playlistId],
      ),
    );

    await _stage(
      'upsert-seasons',
      () => db.rawInsert(
        '''
INSERT INTO seasons (id, series_id, season_number, created_at, updated_at)
SELECT season_id, series_id, MAX(season_number), ?, ?
FROM import_staging_items
WHERE playlist_id = ? AND season_id IS NOT NULL
GROUP BY season_id, series_id
ON CONFLICT(id) DO UPDATE SET
  season_number = excluded.season_number,
  updated_at = excluded.updated_at
''',
        [now, now, playlistId],
      ),
    );

    // Runs before the media_items upsert below, while the previous title and
    // group are still readable: on a refresh only genuinely changed rows need
    // reindexing, which is what keeps a warm refresh from re-tokenising the
    // whole catalog. sort_title is derived from title, so it adds nothing.
    await _stage(
      'queue-search-upserts',
      () => db.rawInsert(
        isColdImport
            ? '''
INSERT INTO search_index_queue (media_item_id, playlist_id, operation, queued_at)
SELECT s.resolved_media_id, ?, '${indexIsEmpty ? 'insert' : 'upsert'}', ?
FROM import_staging_items s
WHERE s.playlist_id = ? AND s.resolved_media_id IS NOT NULL
ON CONFLICT(media_item_id) DO UPDATE SET
  operation = excluded.operation,
  queued_at = excluded.queued_at
'''
            : '''
INSERT INTO search_index_queue (media_item_id, playlist_id, operation, queued_at)
SELECT s.resolved_media_id, ?, 'upsert', ?
FROM import_staging_items s
LEFT JOIN media_items m ON m.id = s.resolved_media_id
WHERE s.playlist_id = ? AND s.resolved_media_id IS NOT NULL
  AND (
    m.id IS NULL
    OR m.title <> s.title
    OR IFNULL(m.group_title, '') <> IFNULL(s.group_title, '')
  )
ON CONFLICT(media_item_id) DO UPDATE SET
  operation = excluded.operation,
  queued_at = excluded.queued_at
''',
        [playlistId, now, playlistId],
      ),
    );

    await _stage(
      'upsert-media-items',
      () => db.rawInsert(
        '''
INSERT INTO media_items (
  id, playlist_id, content_type, title, sort_title, description, artwork_url,
  logo_url, stream_url, category_id, group_title, tvg_id, tvg_name, tvg_chno,
  xui_id, source_index, provider_item_hash, created_at, updated_at
)
SELECT s.resolved_media_id, s.playlist_id, s.content_type, s.title,
  s.sort_title, s.description, s.artwork_url, s.logo_url, s.stream_url,
  s.category_id, s.group_title, s.tvg_id, s.tvg_name, s.tvg_chno, s.xui_id,
  s.source_index, s.provider_item_hash, ?, ?
FROM import_staging_items s
WHERE s.playlist_id = ? AND s.resolved_media_id IS NOT NULL
  ${isColdImport ? '' : '''
  AND NOT EXISTS (
    SELECT 1 FROM media_items m
    WHERE m.id = s.resolved_media_id
      AND m.content_type = s.content_type
      AND m.title = s.title
      AND m.stream_url = s.stream_url
      AND m.source_index = s.source_index
      AND IFNULL(m.group_title, '') = IFNULL(s.group_title, '')
      AND IFNULL(m.category_id, '') = IFNULL(s.category_id, '')
      AND IFNULL(m.description, '') = IFNULL(s.description, '')
      AND IFNULL(m.artwork_url, '') = IFNULL(s.artwork_url, '')
      AND IFNULL(m.logo_url, '') = IFNULL(s.logo_url, '')
      AND IFNULL(m.tvg_id, '') = IFNULL(s.tvg_id, '')
      AND IFNULL(m.tvg_name, '') = IFNULL(s.tvg_name, '')
      AND IFNULL(m.tvg_chno, '') = IFNULL(s.tvg_chno, '')
      AND IFNULL(m.xui_id, '') = IFNULL(s.xui_id, '')
  )
'''}
ON CONFLICT(id) DO UPDATE SET
  content_type = excluded.content_type,
  title = excluded.title,
  sort_title = excluded.sort_title,
  description = excluded.description,
  artwork_url = excluded.artwork_url,
  logo_url = excluded.logo_url,
  stream_url = excluded.stream_url,
  category_id = excluded.category_id,
  group_title = excluded.group_title,
  tvg_id = excluded.tvg_id,
  tvg_name = excluded.tvg_name,
  tvg_chno = excluded.tvg_chno,
  xui_id = excluded.xui_id,
  source_index = excluded.source_index,
  provider_item_hash = excluded.provider_item_hash,
  updated_at = excluded.updated_at
''',
        [now, now, playlistId],
      ),
    );

    await _stage(
      'upsert-episodes',
      () => _upsertEpisodesFromStaging(db, playlistId: playlistId, now: now),
    );

    // Nothing can be stale on a first import, and the anti-joins below are
    // full scans of the freshly written catalog.
    if (deleteStaleRows && !isColdImport) {
      await _stage('delete-stale', () async {
        // Queue-marking runs before the deletes below, while the stale rows
        // still exist to select ids from.
        await db.rawInsert(
          '''
INSERT INTO search_index_queue (media_item_id, media_rowid, playlist_id, operation, queued_at)
SELECT id, rowid, ?, 'delete', ?
FROM media_items
WHERE playlist_id = ? AND id NOT IN (
  SELECT resolved_media_id FROM import_staging_items
  WHERE playlist_id = ? AND resolved_media_id IS NOT NULL
)
ON CONFLICT(media_item_id) DO UPDATE SET
  media_rowid = excluded.media_rowid,
  operation = excluded.operation,
  queued_at = excluded.queued_at
''',
          [playlistId, now, playlistId, playlistId],
        );

        await db.rawDelete(
          '''
DELETE FROM seasons WHERE id IN (
  SELECT se.id FROM seasons se
  INNER JOIN series s ON s.id = se.series_id
  WHERE s.playlist_id = ?
) AND id NOT IN (
  SELECT season_id FROM import_staging_items
  WHERE playlist_id = ? AND season_id IS NOT NULL
)
''',
          [playlistId, playlistId],
        );
        await db.rawDelete(
          '''
DELETE FROM series WHERE playlist_id = ? AND id NOT IN (
  SELECT series_id FROM import_staging_items
  WHERE playlist_id = ? AND series_id IS NOT NULL
)
''',
          [playlistId, playlistId],
        );
        await db.rawDelete(
          '''
DELETE FROM media_items WHERE playlist_id = ? AND id NOT IN (
  SELECT resolved_media_id FROM import_staging_items
  WHERE playlist_id = ? AND resolved_media_id IS NOT NULL
)
''',
          [playlistId, playlistId],
        );
        await db.rawDelete(
          '''
DELETE FROM categories WHERE playlist_id = ? AND id NOT IN (
  SELECT category_id FROM import_staging_items WHERE playlist_id = ?
)
''',
          [playlistId, playlistId],
        );
      });
    }

    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS item_count FROM media_items WHERE playlist_id = ?',
      [playlistId],
    );
    final committedCount =
        (countRows.single['item_count'] as num?)?.toInt() ?? 0;
    if (committedCount == 0) {
      throw StateError(
        'Playlist import staged rows but committed no media_items rows.',
      );
    }

    await _stage(
      'clear-staging',
      () => db.delete(
        'import_staging_items',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      ),
    );

    onProgress?.call(
      CatalogImportProgress(
        phase: CatalogImportPhase.importing,
        startedAt: refreshStartedAt,
        current: parsed.length,
        total: parsed.length,
      ),
    );
    return committedCount;
  }

  Future<void> _upsertEpisodesFromStaging(
    DatabaseExecutor db, {
    required String playlistId,
    required String now,
  }) async {
    await db.delete(
      'episodes',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    await db.rawInsert(
      '''
INSERT OR IGNORE INTO episodes (
  id, playlist_id, series_id, season_id, media_item_id, episode_number,
  title, sort_title, artwork_url, created_at, updated_at
)
SELECT MIN(episode_id), playlist_id, MIN(series_id), season_id,
       MIN(resolved_media_id), episode_number, MIN(title),
       LOWER(TRIM(MIN(title))), MIN(artwork_url), ?, ?
FROM import_staging_items
WHERE playlist_id = ?
  AND episode_id IS NOT NULL
  AND resolved_media_id IS NOT NULL
GROUP BY playlist_id, season_id, episode_number
''',
      [now, now, playlistId],
    );
  }

  Future<int> _reconcilePlaylistContent({
    required DatabaseExecutor db,
    required String playlistId,
    required String now,
    required List<ContentItem> parsed,
    required bool deleteStaleRows,
    required DateTime refreshStartedAt,
    CatalogImportProgressCallback? onProgress,
  }) async {
    final existingCategoryIds = await _fetchExistingIds(
      db,
      'SELECT id FROM categories WHERE playlist_id = ?',
      [playlistId],
    );
    final existingSeriesIds = await _fetchExistingIds(
      db,
      'SELECT id FROM series WHERE playlist_id = ?',
      [playlistId],
    );
    final existingSeasonIds = await _fetchExistingIds(
      db,
      '''
SELECT seasons.id AS id
FROM seasons
INNER JOIN series ON series.id = seasons.series_id
WHERE series.playlist_id = ?
''',
      [playlistId],
    );
    final existingMediaItemIds = await _fetchExistingIds(
      db,
      'SELECT id FROM media_items WHERE playlist_id = ?',
      [playlistId],
    );
    final existingMediaIdByProviderHash =
        await _fetchExistingMediaIdsByProviderHash(db, playlistId: playlistId);
    final existingMediaIdBySignature = await _fetchExistingMediaIdsBySignature(
      db,
      playlistId: playlistId,
    );
    final existingEpisodeIds = await _fetchExistingIds(
      db,
      'SELECT id FROM episodes WHERE playlist_id = ?',
      [playlistId],
    );

    final desiredCategoryIds = <String>{};
    final desiredSeriesIds = <String>{};
    final desiredSeasonIds = <String>{};
    final desiredMediaItemIds = <String>{};
    final desiredEpisodeIds = <String>{};
    var batch = db.batch();
    var pendingOps = 0;

    // Commits and swaps in a fresh Batch once enough ops have queued, so a
    // huge playlist never builds one unbounded in-memory/platform-channel
    // payload; force=true drains whatever is left regardless of the count.
    Future<void> flushBatch({bool force = false}) async {
      if (pendingOps == 0) return;
      if (!force && pendingOps < _importBatchChunkSize) return;
      await batch.commit(noResult: true);
      batch = db.batch();
      pendingOps = 0;
    }

    final categoryIdByGroup = <String, String>{};
    for (final item in parsed) {
      final group = CatalogNormalizer.canonicalGroup(item.group);
      final categoryId = categoryIdByGroup.putIfAbsent(
        group,
        () => _stableId('category|$playlistId|$group'),
      );
      if (!desiredCategoryIds.add(categoryId)) continue;

      _queueUpsert(
        batch: batch,
        table: 'categories',
        id: categoryId,
        now: now,
        exists: existingCategoryIds.contains(categoryId),
        values: {
          'playlist_id': playlistId,
          'provider_group_title': group,
          'normalized_name': CatalogNormalizer.normalizeText(group),
          'content_kind': 'unknown',
          'country_code': null,
          'language_code': null,
        },
      );
      pendingOps++;
    }
    await flushBatch();

    final seriesIdByTitle = <String, String>{};
    final seasonIdByKey = <String, String>{};

    onProgress?.call(
      CatalogImportProgress(
        phase: CatalogImportPhase.importing,
        startedAt: refreshStartedAt,
        current: 0,
        total: parsed.length,
      ),
    );
    const progressReportInterval = 200;

    for (var index = 0; index < parsed.length; index++) {
      final item = parsed[index];
      if (onProgress != null &&
          index > 0 &&
          index % progressReportInterval == 0) {
        onProgress(
          CatalogImportProgress(
            phase: CatalogImportPhase.importing,
            startedAt: refreshStartedAt,
            current: index,
            total: parsed.length,
          ),
        );
      }
      final group = CatalogNormalizer.canonicalGroup(item.group);
      final categoryId = categoryIdByGroup[group];
      var contentType = item.type == ContentType.live ? 'live' : 'movie';

      String? seriesId;
      String? seasonId;
      int? episodeNumber;
      final episodeMatch = CatalogNormalizer.parseSeriesEpisodeTitle(
        item.title,
      );
      if (episodeMatch != null) {
        final seriesTitle = episodeMatch.seriesTitle;
        final seasonNumber = episodeMatch.seasonNumber;
        episodeNumber = episodeMatch.episodeNumber;
        if (seriesTitle.isNotEmpty) {
          contentType = 'episode';
          seriesId = seriesIdByTitle.putIfAbsent(
            seriesTitle,
            () => _stableId('series|$playlistId|$seriesTitle'),
          );
          if (desiredSeriesIds.add(seriesId)) {
            _queueUpsert(
              batch: batch,
              table: 'series',
              id: seriesId,
              now: now,
              exists: existingSeriesIds.contains(seriesId),
              values: {
                'playlist_id': playlistId,
                'title': seriesTitle,
                'sort_title': CatalogNormalizer.normalizeText(seriesTitle),
                'artwork_url': item.posterUrl,
              },
            );
            pendingOps++;
          }

          final seasonKey = '$seriesId|$seasonNumber';
          seasonId = seasonIdByKey.putIfAbsent(
            seasonKey,
            () => _stableId('season|$seriesId|$seasonNumber'),
          );
          if (desiredSeasonIds.add(seasonId)) {
            _queueUpsert(
              batch: batch,
              table: 'seasons',
              id: seasonId,
              now: now,
              exists: existingSeasonIds.contains(seasonId),
              values: {'series_id': seriesId, 'season_number': seasonNumber},
            );
            pendingOps++;
          }
        }
      }

      final resolvedMediaId = _resolveMediaItemId(
        item: item,
        existingMediaItemIds: existingMediaItemIds,
        existingMediaIdByProviderHash: existingMediaIdByProviderHash,
        existingMediaIdBySignature: existingMediaIdBySignature,
      );
      desiredMediaItemIds.add(resolvedMediaId);
      _queueUpsert(
        batch: batch,
        table: 'media_items',
        id: resolvedMediaId,
        now: now,
        exists: existingMediaItemIds.contains(resolvedMediaId),
        values: {
          'playlist_id': playlistId,
          'content_type': contentType,
          'title': item.title,
          'sort_title': CatalogNormalizer.normalizeText(item.title),
          'description': item.description,
          'artwork_url': item.posterUrl,
          'logo_url': item.logoUrl,
          'stream_url': item.streamUrl,
          'category_id': categoryId,
          'group_title': group,
          'tvg_id': item.metadata['tvg-id'],
          'tvg_name': item.metadata['tvg-name'],
          'tvg_chno': item.metadata['tvg-chno'],
          'xui_id': item.metadata['xui-id'],
          'source_index': item.sourceIndex,
          'provider_item_hash': CatalogNormalizer.providerItemHash(
            streamUrl: item.streamUrl,
            title: item.title,
            group: item.group,
          ),
        },
      );
      pendingOps++;

      _queueSearchIndexUpsert(
        batch: batch,
        playlistId: playlistId,
        mediaItemId: resolvedMediaId,
        now: now,
      );
      pendingOps++;

      if (contentType == 'episode' &&
          seriesId != null &&
          seasonId != null &&
          episodeNumber != null &&
          episodeNumber > 0) {
        final episodeId = strongStableId(
          'episode',
          '$resolvedMediaId|$episodeNumber',
        );
        desiredEpisodeIds.add(episodeId);
        _queueUpsert(
          batch: batch,
          table: 'episodes',
          id: episodeId,
          now: now,
          exists: existingEpisodeIds.contains(episodeId),
          values: {
            'playlist_id': playlistId,
            'series_id': seriesId,
            'season_id': seasonId,
            'media_item_id': resolvedMediaId,
            'episode_number': episodeNumber,
            'title': item.title,
            'sort_title': CatalogNormalizer.normalizeText(item.title),
            'artwork_url': item.posterUrl,
          },
        );
        pendingOps++;
      }

      await flushBatch();
    }
    // Commit any items left over from the loop before deleting stale rows,
    // so FK-ordered deletes never race with not-yet-committed inserts.
    await flushBatch(force: true);

    if (deleteStaleRows) {
      final staleMediaItemIds = existingMediaItemIds.difference(
        desiredMediaItemIds,
      );
      // Deletes run directly (chunked, outside the upsert batch) since a
      // single `id IN (...)` statement for hundreds of thousands of stale
      // ids would exceed SQLite's bound-parameter limit.
      await _deleteStaleRowsChunked(
        db,
        table: 'episodes',
        staleIds: existingEpisodeIds.difference(desiredEpisodeIds),
      );
      await _deleteStaleRowsChunked(
        db,
        table: 'seasons',
        staleIds: existingSeasonIds.difference(desiredSeasonIds),
      );
      await _deleteStaleRowsChunked(
        db,
        table: 'series',
        staleIds: existingSeriesIds.difference(desiredSeriesIds),
      );
      await _deleteStaleRowsChunked(
        db,
        table: 'media_items',
        staleIds: staleMediaItemIds,
      );
      await _deleteStaleRowsChunked(
        db,
        table: 'categories',
        staleIds: existingCategoryIds.difference(desiredCategoryIds),
      );
      for (final staleId in staleMediaItemIds) {
        _queueSearchIndexDelete(
          batch: batch,
          playlistId: playlistId,
          mediaItemId: staleId,
          now: now,
        );
        pendingOps++;
        await flushBatch();
      }
    }

    await flushBatch(force: true);
    onProgress?.call(
      CatalogImportProgress(
        phase: CatalogImportPhase.importing,
        startedAt: refreshStartedAt,
        current: parsed.length,
        total: parsed.length,
      ),
    );
    return parsed.length;
  }

  Future<Set<String>> _fetchExistingIds(
    DatabaseExecutor db,
    String sql,
    List<Object?> args,
  ) async {
    final rows = await db.rawQuery(sql, args);
    return rows.map((row) => row['id']! as String).toSet();
  }

  Future<Map<String, String>> _fetchExistingMediaIdsBySignature(
    DatabaseExecutor db, {
    required String playlistId,
  }) async {
    final rows = await db.query(
      'media_items',
      columns: const ['id', 'stream_url', 'title', 'source_index'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    final map = <String, String>{};
    for (final row in rows) {
      final signature = _mediaSignature(
        streamUrl: row['stream_url']! as String,
        title: row['title']! as String,
        sourceIndex: row['source_index'] as int? ?? 0,
      );
      map.putIfAbsent(signature, () => row['id']! as String);
    }
    return map;
  }

  Future<Map<String, String>> _fetchExistingMediaIdsByProviderHash(
    DatabaseExecutor db, {
    required String playlistId,
  }) async {
    final rows = await db.query(
      'media_items',
      columns: const ['id', 'provider_item_hash'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
    );
    final map = <String, String>{};
    for (final row in rows) {
      final providerHash = row['provider_item_hash'] as String?;
      if (providerHash == null || providerHash.isEmpty) continue;
      map.putIfAbsent(providerHash, () => row['id']! as String);
    }
    return map;
  }

  String _resolveMediaItemId({
    required ContentItem item,
    required Set<String> existingMediaItemIds,
    required Map<String, String> existingMediaIdByProviderHash,
    required Map<String, String> existingMediaIdBySignature,
  }) {
    if (existingMediaItemIds.contains(item.id)) {
      return item.id;
    }

    final providerHash = strongStableId(
      'provider',
      CatalogNormalizer.providerItemHash(
        streamUrl: item.streamUrl,
        title: item.title,
        group: item.group,
      ),
    );
    final byProviderHash = existingMediaIdByProviderHash[providerHash];
    if (byProviderHash != null) {
      return byProviderHash;
    }

    final signature = _mediaSignature(
      streamUrl: item.streamUrl,
      title: item.title,
      sourceIndex: item.sourceIndex,
    );
    final bySignature = existingMediaIdBySignature[signature];
    if (bySignature != null) {
      return bySignature;
    }

    return item.id;
  }

  String _mediaSignature({
    required String streamUrl,
    required String title,
    required int sourceIndex,
  }) {
    return CatalogNormalizer.mediaSignature(
      streamUrl: streamUrl,
      title: title,
      sourceIndex: sourceIndex,
    );
  }

  void _queueUpsert({
    required Batch batch,
    required String table,
    required String id,
    required String now,
    required bool exists,
    required Map<String, Object?> values,
  }) {
    if (exists) {
      batch.update(
        table,
        {...values, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      batch.insert(table, {
        'id': id,
        ...values,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _deleteStaleRowsChunked(
    DatabaseExecutor db, {
    required String table,
    required Set<String> staleIds,
  }) async {
    if (staleIds.isEmpty) return;
    final idList = staleIds.toList();
    for (var start = 0; start < idList.length; start += _deleteChunkSize) {
      final end = (start + _deleteChunkSize < idList.length)
          ? start + _deleteChunkSize
          : idList.length;
      final chunk = idList.sublist(start, end);
      final placeholders = List.filled(chunk.length, '?').join(',');
      await db.delete(table, where: 'id IN ($placeholders)', whereArgs: chunk);
    }
  }

  void _queueSearchIndexUpsert({
    required Batch batch,
    required String playlistId,
    required String mediaItemId,
    required String now,
  }) {
    batch.insert('search_index_queue', {
      'media_item_id': mediaItemId,
      'playlist_id': playlistId,
      'operation': 'upsert',
      'queued_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  void _queueSearchIndexDelete({
    required Batch batch,
    required String playlistId,
    required String mediaItemId,
    required String now,
  }) {
    batch.insert('search_index_queue', {
      'media_item_id': mediaItemId,
      'playlist_id': playlistId,
      'operation': 'delete',
      'queued_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Starts draining [playlistId]'s search-index queue in the background.
  ///
  /// A no-op if a drain for that playlist is already in flight; callers
  /// don't need to await this, another refresh's queue entries are picked up
  /// by whichever worker runs next.
  void _startSearchIndexWorker(String playlistId) {
    if (!autoStartSearchIndexWorker) return;
    if (!_indexingPlaylists.add(playlistId)) return;
    unawaited(
      processSearchIndexQueue(playlistId: playlistId)
          // A rolled-back batch leaves the queue and dirty flag intact for
          // the next worker (e.g. next refresh, or app-restart resume); a
          // closed database (app/test shutdown mid-drain) is expected here.
          .catchError((Object _, StackTrace stackTrace) => 0)
          .whenComplete(() => _indexingPlaylists.remove(playlistId)),
    );
  }

  /// Restarts indexing for playlists whose queue survived a previous run
  /// (app killed mid-drain, or a schema migration that rebuilt the index).
  Future<void> resumeSearchIndexing() async {
    final db = await _databaseAdapter.database;
    final rows = await db.query(
      'playlists',
      columns: const ['id'],
      where: 'search_index_dirty = 1',
    );
    for (final row in rows) {
      _startSearchIndexWorker(row['id']! as String);
    }
  }

  /// Drains queued FTS changes in bounded batches so a refresh never has to
  /// rebuild the whole index. Returns the number of rows processed.
  Future<int> processSearchIndexQueue({
    String? playlistId,
    int batchSize = searchIndexBatchSize,
  }) async {
    var processed = 0;
    while (true) {
      final batchCount = await _drainSearchIndexBatch(
        playlistId: playlistId,
        batchSize: batchSize,
      );
      if (batchCount == 0) break;
      processed += batchCount;
    }

    if (playlistId != null) {
      await _clearSearchIndexDirtyIfEmpty(playlistId);
    }
    return processed;
  }

  Future<int> _drainSearchIndexBatch({
    required String? playlistId,
    required int batchSize,
  }) async {
    if (playlistId != null && _pausedIndexingPlaylists.contains(playlistId)) {
      return 0;
    }
    final db = await _databaseAdapter.database;
    final where = playlistId != null ? 'playlist_id = ?' : null;
    final whereArgs = playlistId != null ? [playlistId] : null;
    final rows = await db.query(
      'search_index_queue',
      columns: const ['media_item_id', 'media_rowid', 'operation'],
      where: where,
      whereArgs: whereArgs,
      limit: batchSize,
    );
    if (rows.isEmpty) return 0;
    if (playlistId != null && _pausedIndexingPlaylists.contains(playlistId)) {
      return 0;
    }

    final queuedIds = <String>[];
    final insertIds = <String>[];
    final upsertIds = <String>[];
    final staleRowids = <int>[];
    final staleIdsWithoutRowid = <String>[];
    for (final row in rows) {
      final mediaItemId = row['media_item_id']! as String;
      queuedIds.add(mediaItemId);
      switch (row['operation']) {
        case 'insert':
          insertIds.add(mediaItemId);
        case 'upsert':
          upsertIds.add(mediaItemId);
        default:
          final rowid = row['media_rowid'] as int?;
          if (rowid != null) {
            staleRowids.add(rowid);
          } else {
            staleIdsWithoutRowid.add(mediaItemId);
          }
      }
    }

    return _databaseAdapter.transaction((txn) async {
      // 'insert' means the row is known to have no index entry yet (first
      // import of a playlist), so the removal half of a reindex — half the
      // work on the largest import there is — can be skipped.
      for (final chunk in _chunked(insertIds)) {
        await _reindexChunk(txn, chunk, removeExisting: false);
      }
      for (final chunk in _chunked(upsertIds)) {
        await _reindexChunk(txn, chunk, removeExisting: true);
      }
      for (final chunk in _chunked(staleRowids)) {
        await txn.rawDelete(
          'DELETE FROM media_items_fts WHERE rowid IN (${_placeholders(chunk.length)})',
          chunk,
        );
      }
      for (final chunk in _chunked(staleIdsWithoutRowid)) {
        await txn.rawDelete(
          'DELETE FROM media_items_fts WHERE media_item_id IN (${_placeholders(chunk.length)})',
          chunk,
        );
      }
      for (final chunk in _chunked(queuedIds)) {
        await txn.rawDelete(
          'DELETE FROM search_index_queue WHERE media_item_id IN (${_placeholders(chunk.length)})',
          chunk,
        );
      }
      return rows.length;
    });
  }

  /// The FTS table shares media_items' rowid, so a stale entry is removed by
  /// an integer rowid lookup. Matching on the UNINDEXED media_item_id column
  /// instead would scan the whole index once per row.
  static Future<void> _reindexChunk(
    DatabaseExecutor txn,
    List<String> mediaItemIds, {
    required bool removeExisting,
  }) async {
    final placeholders = _placeholders(mediaItemIds.length);
    if (removeExisting) {
      await txn.rawDelete(
        'DELETE FROM media_items_fts WHERE rowid IN '
        '(SELECT m.rowid FROM media_items m WHERE m.id IN ($placeholders))',
        mediaItemIds,
      );
    }
    await txn.rawInsert(
      'INSERT INTO media_items_fts (rowid, media_item_id, title, group_title) '
      "SELECT m.rowid, m.id, m.title, COALESCE(m.group_title, '') "
      'FROM media_items m WHERE m.id IN ($placeholders)',
      mediaItemIds,
    );
  }

  static Iterable<List<T>> _chunked<T>(
    List<T> values, {
    int size = _deleteChunkSize,
  }) sync* {
    for (var start = 0; start < values.length; start += size) {
      final end = start + size;
      yield values.sublist(start, end > values.length ? values.length : end);
    }
  }

  static String _placeholders(int count) => List.filled(count, '?').join(', ');

  Future<void> _clearSearchIndexDirtyIfEmpty(String playlistId) async {
    final db = await _databaseAdapter.database;
    final remaining = await db.query(
      'search_index_queue',
      columns: const ['media_item_id'],
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (remaining.isNotEmpty) return;
    await db.update(
      'playlists',
      {'search_index_dirty': 0},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  Future<void> _updateImportFailure({
    required String playlistId,
    required String playlistUrl,
    required DateTime startedAt,
    required int stagedRows,
    required int stagedDurationMs,
    required Object error,
  }) async {
    final db = await _databaseAdapter.database;
    final secureStorageKey = _secureStorageKey(playlistId);
    await _upsertPlaylistRow(
      db,
      playlistId: playlistId,
      values: {
        'id': playlistId,
        'name': 'Primary Playlist',
        'secure_storage_key': secureStorageKey,
        'source_url_redacted': _redactUrl(playlistUrl),
        'enabled': 1,
        'created_at': startedAt.toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'last_import_started_at': startedAt.toIso8601String(),
        'last_import_completed_at': DateTime.now().toUtc().toIso8601String(),
        'last_import_staged_rows': stagedRows,
        'last_import_staged_duration_ms': stagedDurationMs,
        'last_import_status': 'failed',
        'last_import_error': error.toString(),
      },
    );
  }

  Future<void> _upsertPlaylistRow(
    DatabaseExecutor db, {
    required String playlistId,
    required Map<String, Object?> values,
  }) async {
    final existing = await db.query(
      'playlists',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final updateValues = Map<String, Object?>.from(values)
        ..remove('id')
        ..remove('created_at');
      await db.update(
        'playlists',
        updateValues,
        where: 'id = ?',
        whereArgs: [playlistId],
      );
    } else {
      await db.insert('playlists', values);
    }
  }

  Future<String> _resolvePlaylistId(String playlistUrl) async {
    final strongId = strongStableId('playlist', playlistUrl);
    final legacyId = legacyStableId('id', 'playlist|$playlistUrl');
    final db = await _databaseAdapter.database;

    final strongRows = await db.query(
      'playlists',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [strongId],
      limit: 1,
    );
    if (strongRows.isNotEmpty) return strongId;

    final legacyRows = await db.query(
      'playlists',
      columns: const ['id'],
      where: 'id = ?',
      whereArgs: [legacyId],
      limit: 1,
    );
    if (legacyRows.isNotEmpty) return legacyId;

    return strongId;
  }

  String _secureStorageKey(String playlistId) => 'playlist:$playlistId';

  ContentItem _mapRowToItem(Map<String, Object?> row) {
    return ContentItem(
      id: row['id']! as String,
      title: row['title']! as String,
      type: (row['content_type'] as String) == 'live'
          ? ContentType.live
          : ContentType.vod,
      streamUrl: row['stream_url']! as String,
      group: (row['group_title'] as String?) ?? 'Uncategorized',
      description: (row['description'] as String?) ?? '',
      logoUrl: row['logo_url'] as String?,
      posterUrl: row['artwork_url'] as String?,
      metadata: {
        if (row['tvg_id'] is String) 'tvg-id': row['tvg_id'] as String,
        if (row['tvg_name'] is String) 'tvg-name': row['tvg_name'] as String,
        if (row['tvg_chno'] is String) 'tvg-chno': row['tvg_chno'] as String,
        if (row['xui_id'] is String) 'xui-id': row['xui_id'] as String,
      },
      sourceIndex: row['source_index'] as int? ?? 0,
    );
  }

  String _redactUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final auth = uri.userInfo.isNotEmpty ? '***@' : '';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://$auth${uri.host}$port${uri.path}';
  }

  String _stableId(String value) => legacyStableId('id', value);
}
