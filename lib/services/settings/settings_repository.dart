import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../catalog/catalog_query.dart';
import '../catalog/id_identity.dart';
import '../security/url_redaction.dart';
import '../sources/source_contracts.dart';
import '../sources/source_verification_record.dart';
import '../storage/secure_storage_service.dart';
import '../storage/storage_contracts.dart';

export '../sources/source_contracts.dart' show PlaylistSourceKind;

class PlaylistSourceConfig {
  const PlaylistSourceConfig.url({
    this.playlistId,
    required this.name,
    required this.url,
    this.enabled = true,
    this.verificationRecord,
    this.expectedConnectionRevision,
  }) : kind = PlaylistSourceKind.url,
       server = null,
       username = null,
       password = null;

  const PlaylistSourceConfig.xtream({
    this.playlistId,
    required this.name,
    required this.server,
    required this.username,
    required this.password,
    this.enabled = true,
    this.verificationRecord,
    this.expectedConnectionRevision,
  }) : kind = PlaylistSourceKind.xtream,
       url = null;

  final String? playlistId;
  final String name;
  final PlaylistSourceKind kind;
  final String? url;
  final String? server;
  final String? username;
  final String? password;
  final bool enabled;
  final SourceVerificationRecord? verificationRecord;
  final int? expectedConnectionRevision;

  String get resolvedUrl {
    return switch (kind) {
      PlaylistSourceKind.url => url!.trim(),
      PlaylistSourceKind.xtream =>
        '${_normalizedServer(server!)}/get.php?username=${Uri.encodeQueryComponent(username!.trim())}&password=${Uri.encodeQueryComponent(password!)}&type=m3u_plus&output=m3u8',
    };
  }

  String get summary {
    return switch (kind) {
      PlaylistSourceKind.url => _summaryForUrl(url!),
      PlaylistSourceKind.xtream => _summaryForUrl(server!),
    };
  }

  Map<String, Object?> toJson() {
    return {
      'kind': kind.name,
      'name': name,
      'url': url,
      'server': server,
      'username': username,
      'password': password,
      'enabled': enabled,
    };
  }

  String toStorageValue() => jsonEncode(toJson());

  static PlaylistSourceConfig? fromStorageValue(
    String? value, {
    String? fallbackName,
    SourceVerificationRecord? verificationRecord,
  }) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (!trimmed.startsWith('{')) {
      return PlaylistSourceConfig.url(
        name: fallbackName ?? 'Playlist',
        url: trimmed,
        verificationRecord: verificationRecord,
      );
    }

    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return null;
    return fromJson(
      decoded,
      fallbackName: fallbackName,
      verificationRecord: verificationRecord,
    );
  }

  static PlaylistSourceConfig? fromJson(
    Map<String, dynamic> json, {
    String? fallbackName,
    SourceVerificationRecord? verificationRecord,
  }) {
    final kindName = json['kind'] as String?;
    final name = (json['name'] as String?)?.trim();
    final enabled = json['enabled'] as bool? ?? true;

    switch (kindName) {
      case 'xtream':
        final server = (json['server'] as String?)?.trim();
        final username = (json['username'] as String?)?.trim();
        final password = json['password'] as String?;
        if (server == null || server.isEmpty) return null;
        if (username == null || username.isEmpty) return null;
        if (password == null || password.isEmpty) return null;
        return PlaylistSourceConfig.xtream(
          name: name?.isNotEmpty == true ? name! : (fallbackName ?? 'Playlist'),
          server: server,
          username: username,
          password: password,
          enabled: enabled,
          verificationRecord: verificationRecord,
        );
      case 'url':
      default:
        final url = (json['url'] as String?)?.trim();
        if (url == null || url.isEmpty) return null;
        return PlaylistSourceConfig.url(
          name: name?.isNotEmpty == true ? name! : (fallbackName ?? 'Playlist'),
          url: url,
          enabled: enabled,
          verificationRecord: verificationRecord,
        );
    }
  }

  static String _normalizedServer(String server) {
    final trimmed = server.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  static String _summaryForUrl(String url) {
    final parsed = Uri.tryParse(url.trim());
    return parsed?.host ?? '';
  }
}

class ManagedPlaylist {
  const ManagedPlaylist({
    required this.playlistId,
    required this.name,
    required this.enabled,
    required this.sourceConfig,
    required this.sourceKind,
    required this.sourceSummary,
    required this.resolvedUrl,
    required this.sourceUrlRedacted,
    required this.lastImportStatus,
    required this.lastImportWarning,
    required this.lastImportCompletedAt,
    required this.refreshSettings,
    this.verificationRecord,
    this.connectionRevision = 0,
  });

  final String playlistId;
  final String name;
  final bool enabled;
  final PlaylistSourceConfig? sourceConfig;
  final PlaylistSourceKind? sourceKind;
  final String sourceSummary;
  final String resolvedUrl;
  final String? sourceUrlRedacted;
  final String? lastImportStatus;
  final String? lastImportWarning;
  final DateTime? lastImportCompletedAt;
  final PlaylistRefreshSettings? refreshSettings;
  final SourceVerificationRecord? verificationRecord;
  final int connectionRevision;

  SourceConnectionSummary? get connectionSummary => sourceKind == null
      ? null
      : SourceConnectionSummary(
          playlistId: playlistId,
          inputKind: sourceKind!,
          verification:
              verificationRecord?.verification ??
              SourceVerificationState.unchecked,
          accountState:
              verificationRecord?.accountState ?? SourceAccountState.unknown,
          connectionRevision: connectionRevision,
        );
}

enum RefreshMode { manual, daily, every3Days, weekly, every2Weeks }

class PlaylistRefreshSettings {
  const PlaylistRefreshSettings({
    required this.playlistId,
    required this.refreshEnabled,
    required this.refreshMode,
    required this.refreshIntervalHours,
    this.lastRefreshAt,
    this.nextRefreshAt,
    this.lastRefreshStatus,
  });

  final String playlistId;
  final bool refreshEnabled;
  final RefreshMode refreshMode;
  final int refreshIntervalHours;
  final DateTime? lastRefreshAt;
  final DateTime? nextRefreshAt;
  final String? lastRefreshStatus;
}

abstract interface class SettingsRepository {
  Future<String?> getAppSetting(String key);
  Future<void> setAppSetting(String key, String value);
  Future<List<ManagedPlaylist>> listPlaylists();
  Future<ManagedPlaylist?> getPlaylist(String playlistId);
  Future<ManagedPlaylist> upsertPlaylist(PlaylistSourceConfig config);
  Future<void> deletePlaylist(String playlistId);
  Future<String?> resolvePlaylistUrl(String playlistId);
  Future<PlaylistRefreshSettings?> getPlaylistRefreshSettings(
    String playlistId,
  );
  Future<void> upsertPlaylistRefreshSettings(PlaylistRefreshSettings settings);
  Future<void> setCategoryHidden({
    required String playlistId,
    required String categoryId,
    required bool hidden,
    String? profileId,
  });
  Future<bool> isCategoryHidden({
    required String playlistId,
    required String categoryId,
    String? profileId,
  });
  Future<void> setGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    required bool hidden,
    String? profileId,
  });
  Future<bool> isGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    String? profileId,
  });
}

abstract interface class SourceVerificationRepository {
  Future<bool> saveSourceVerification(
    String playlistId,
    int expectedRevision,
    SourceVerificationRecord record,
  );
}

class SqliteSettingsRepository
    implements SettingsRepository, SourceVerificationRepository {
  SqliteSettingsRepository({
    required DatabaseAdapter databaseAdapter,
    PlaylistSecretStore? secretStore,
  }) : _databaseAdapter = databaseAdapter,
       _secretStore = secretStore ?? InMemoryPlaylistSecretStore();

  final DatabaseAdapter _databaseAdapter;
  final PlaylistSecretStore _secretStore;
  Future<void> _sourceOperations = Future<void>.value();

  Future<T> _serializeSourceOperation<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _sourceOperations = _sourceOperations.then((_) async {
      try {
        await _recoverSourceSecrets();
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> _recoverSourceSecrets() async {
    final db = await _databaseAdapter.database;
    final entries = await db.query('source_secret_journal');
    for (final entry in entries) {
      final key = entry['secret_key']! as String;
      final references = await db.query(
        'playlists',
        columns: const ['id'],
        where: 'secure_storage_key = ?',
        whereArgs: [key],
        limit: 1,
      );
      if (references.isEmpty) {
        try {
          await _secretStore.delete(key: key);
        } catch (e, st) {
          stderr.writeln('Fatal error: $e');
          stderr.writeln('Stack trace: $st');
          continue;
        }
      }
      await db.delete(
        'source_secret_journal',
        where: 'secret_key = ?',
        whereArgs: [key],
      );
    }
  }

  Future<void> _queueSecretCleanup(DatabaseExecutor db, String? key) async {
    if (key == null || key.isEmpty) return;
    await db.insert('source_secret_journal', {
      'secret_key': key,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  static const Map<RefreshMode, String> _refreshModeToDb = {
    RefreshMode.manual: 'manual',
    RefreshMode.daily: 'daily',
    RefreshMode.every3Days: 'every_3_days',
    RefreshMode.weekly: 'weekly',
    RefreshMode.every2Weeks: 'every_2_weeks',
  };

  static final Map<String, RefreshMode> _dbToRefreshMode = {
    for (final entry in _refreshModeToDb.entries) entry.value: entry.key,
  };

  @override
  Future<String?> getAppSetting(String key) async {
    final db = await _databaseAdapter.database;
    final rows = await db.query(
      'app_settings',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  @override
  Future<void> setAppSetting(String key, String value) async {
    final db = await _databaseAdapter.database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<ManagedPlaylist>> listPlaylists() =>
      _serializeSourceOperation(_listPlaylists);

  Future<List<ManagedPlaylist>> _listPlaylists() async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery('''
SELECT p.id,
       p.name,
       p.enabled,
      p.source_revision,
      p.source_verification,
      p.source_account_state,
      p.source_checked_at,
      p.source_api_enabled,
       p.secure_storage_key,
       p.source_url_redacted,
       p.last_import_status,
      p.last_import_error,
       p.last_import_completed_at,
       ps.refresh_enabled,
       ps.refresh_mode,
       ps.refresh_interval_hours,
       ps.last_refresh_at,
       ps.next_refresh_at,
       ps.last_refresh_status
FROM playlists p
LEFT JOIN playlist_settings ps ON ps.playlist_id = p.id
ORDER BY p.updated_at DESC, p.created_at DESC, p.name COLLATE NOCASE ASC
''');

    final playlists = <ManagedPlaylist>[];
    for (final row in rows) {
      playlists.add(await _rowToManagedPlaylist(row));
    }
    return playlists;
  }

  @override
  Future<ManagedPlaylist?> getPlaylist(String playlistId) =>
      _serializeSourceOperation(() => _getPlaylist(playlistId));

  Future<ManagedPlaylist?> _getPlaylist(String playlistId) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      '''
SELECT p.id,
       p.name,
       p.enabled,
      p.source_revision,
      p.source_verification,
      p.source_account_state,
      p.source_checked_at,
      p.source_api_enabled,
       p.secure_storage_key,
       p.source_url_redacted,
       p.last_import_status,
      p.last_import_error,
       p.last_import_completed_at,
       ps.refresh_enabled,
       ps.refresh_mode,
       ps.refresh_interval_hours,
       ps.last_refresh_at,
       ps.next_refresh_at,
       ps.last_refresh_status
FROM playlists p
LEFT JOIN playlist_settings ps ON ps.playlist_id = p.id
WHERE p.id = ?
LIMIT 1
''',
      [playlistId],
    );
    if (rows.isEmpty) return null;
    return _rowToManagedPlaylist(rows.first);
  }

  @override
  Future<ManagedPlaylist> upsertPlaylist(PlaylistSourceConfig config) =>
      _serializeSourceOperation(() => _upsertPlaylist(config));

  Future<ManagedPlaylist> _upsertPlaylist(PlaylistSourceConfig config) async {
    final db = await _databaseAdapter.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final playlistId = config.playlistId ?? _createPlaylistId(config);
    final random = Random.secure();
    final nonce = List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final secureStorageKey = 'playlist:$playlistId:$nonce';
    final existingRows = await db.query(
      'playlists',
      where: 'id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    final existing = existingRows.isNotEmpty ? existingRows.first : null;
    if (config.expectedConnectionRevision != null &&
        (existing == null ||
            existing['source_revision'] != config.expectedConnectionRevision)) {
      throw StateError('Source changed while editing. Reopen the editor.');
    }
    final oldKey = existing?['secure_storage_key'] as String?;
    final oldConfig = oldKey == null
        ? null
        : PlaylistSourceConfig.fromStorageValue(
            await _secretStore.read(key: oldKey),
          );
    final changed = existing != null && !_sameConnection(oldConfig, config);
    final revision =
        (existing?['source_revision'] as int? ?? 0) + (changed ? 1 : 0);
    final suppliedRecord = config.verificationRecord;
    final record =
        suppliedRecord != null && suppliedRecord.connectionRevision == revision
        ? suppliedRecord
        : changed
        ? null
        : existing == null
        ? null
        : _verificationFromRow(existing);

    await _queueSecretCleanup(db, secureStorageKey);

    await _secretStore.write(
      key: secureStorageKey,
      value: config.toStorageValue(),
    );

    await _databaseAdapter.transaction((txn) async {
      final values = <String, Object?>{
        'name': config.name,
        'secure_storage_key': secureStorageKey,
        'source_url_redacted': redactUrl(config.resolvedUrl),
        'enabled': config.enabled ? 1 : 0,
        'updated_at': now,
        'source_revision': revision,
        ..._verificationValues(record),
      };
      if (existing == null) {
        await txn.insert('playlists', {
          'id': playlistId,
          'created_at': now,
          ...values,
        });
      } else {
        await txn.update(
          'playlists',
          values,
          where: 'id = ?',
          whereArgs: [playlistId],
        );
      }

      await txn.insert('playlist_settings', {
        'playlist_id': playlistId,
        'refresh_enabled': 1,
        'refresh_mode': 'weekly',
        'refresh_interval_hours': 168,
        'last_refresh_at': null,
        'next_refresh_at': null,
        'last_refresh_status': null,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await _queueSecretCleanup(txn, oldKey);
      await txn.delete(
        'source_secret_journal',
        where: 'secret_key = ?',
        whereArgs: [secureStorageKey],
      );
    });

    await _recoverSourceSecrets();
    final refreshed = await _getPlaylist(playlistId);
    return refreshed!;
  }

  @override
  Future<void> deletePlaylist(String playlistId) =>
      _serializeSourceOperation(() => _deletePlaylist(playlistId));

  Future<void> _deletePlaylist(String playlistId) async {
    await _databaseAdapter.transaction((txn) async {
      final rows = await txn.query(
        'playlists',
        columns: const ['secure_storage_key'],
        where: 'id = ?',
        whereArgs: [playlistId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final secureStorageKey = rows.first['secure_storage_key'] as String?;
        if (secureStorageKey != null && secureStorageKey.isNotEmpty) {
          await _queueSecretCleanup(txn, secureStorageKey);
        }
      }

      await txn.rawInsert(
        '''
INSERT INTO items_fts(items_fts, rowid, title)
SELECT 'delete', id, title FROM items WHERE playlist_id = ?
''',
        [playlistId],
      );
      await txn.delete(
        'items',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.delete(
        'series_v8',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.delete(
        'groups',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.rawDelete(
        'DELETE FROM import_rows WHERE import_id IN '
        '(SELECT id FROM import_sessions WHERE playlist_id = ?)',
        [playlistId],
      );
      await txn.rawDelete(
        'DELETE FROM import_seen WHERE import_id IN '
        '(SELECT id FROM import_sessions WHERE playlist_id = ?)',
        [playlistId],
      );
      await txn.delete(
        'import_sessions',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.delete(
        'favorites_v8',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.delete(
        'playback_progress_v8',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.delete(
        'watch_history_v8',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.delete(
        'hidden_groups_v8',
        where: 'playlist_id = ?',
        whereArgs: [playlistId],
      );
      await txn.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
    });
    await _recoverSourceSecrets();
  }

  @override
  Future<bool> saveSourceVerification(
    String playlistId,
    int expectedRevision,
    SourceVerificationRecord record,
  ) => _serializeSourceOperation(() async {
    if (expectedRevision < 0 || record.connectionRevision != expectedRevision) {
      return false;
    }
    final db = await _databaseAdapter.database;
    return await db.update(
          'playlists',
          _verificationValues(record),
          where: 'id = ? AND source_revision = ?',
          whereArgs: [playlistId, expectedRevision],
        ) ==
        1;
  });

  bool _sameConnection(
    PlaylistSourceConfig? previous,
    PlaylistSourceConfig next,
  ) =>
      previous != null &&
      previous.kind == next.kind &&
      switch (next.kind) {
        PlaylistSourceKind.url => previous.url?.trim() == next.url?.trim(),
        PlaylistSourceKind.xtream =>
          PlaylistSourceConfig._normalizedServer(previous.server!) ==
                  PlaylistSourceConfig._normalizedServer(next.server!) &&
              previous.username?.trim() == next.username?.trim() &&
              previous.password == next.password,
      };

  Map<String, Object?> _verificationValues(SourceVerificationRecord? record) =>
      {
        'source_verification': record?.verification.name,
        'source_account_state': record?.accountState.name,
        'source_checked_at': record?.checkedAt.toUtc().toIso8601String(),
        'source_api_enabled': record == null
            ? null
            : record.apiEnabled
            ? 1
            : 0,
      };

  SourceVerificationRecord? _verificationFromRow(Map<String, Object?> row) {
    final checkedAt = _tryParseDateTime(row['source_checked_at']);
    if (checkedAt == null || row['source_verification'] == null) return null;
    return SourceVerificationRecord(
      verification: SourceVerificationState.values.byName(
        row['source_verification']! as String,
      ),
      accountState: SourceAccountState.values.byName(
        row['source_account_state']! as String,
      ),
      checkedAt: checkedAt,
      connectionRevision: row['source_revision'] as int? ?? 0,
      apiEnabled: row['source_api_enabled'] == 1,
    );
  }

  @override
  Future<String?> resolvePlaylistUrl(String playlistId) async {
    // getPlaylist() already reads secure storage and resolves the URL onto
    // ManagedPlaylist.resolvedUrl; avoid a second query + secret-store read.
    final playlist = await getPlaylist(playlistId);
    return playlist?.resolvedUrl;
  }

  @override
  Future<PlaylistRefreshSettings?> getPlaylistRefreshSettings(
    String playlistId,
  ) async {
    final db = await _databaseAdapter.database;
    final rows = await db.query(
      'playlist_settings',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PlaylistRefreshSettings(
      playlistId: playlistId,
      refreshEnabled: (row['refresh_enabled'] as int? ?? 1) == 1,
      refreshMode: _dbToRefreshMode[row['refresh_mode']] ?? RefreshMode.weekly,
      refreshIntervalHours: row['refresh_interval_hours'] as int? ?? 168,
      lastRefreshAt: _tryParseDateTime(row['last_refresh_at']),
      nextRefreshAt: _tryParseDateTime(row['next_refresh_at']),
      lastRefreshStatus: row['last_refresh_status'] as String?,
    );
  }

  @override
  Future<void> upsertPlaylistRefreshSettings(
    PlaylistRefreshSettings settings,
  ) async {
    final db = await _databaseAdapter.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('playlist_settings', {
      'playlist_id': settings.playlistId,
      'refresh_enabled': settings.refreshEnabled ? 1 : 0,
      'refresh_mode': _refreshModeToDb[settings.refreshMode] ?? 'weekly',
      'refresh_interval_hours': settings.refreshIntervalHours,
      'last_refresh_at': settings.lastRefreshAt?.toUtc().toIso8601String(),
      'next_refresh_at': settings.nextRefreshAt?.toUtc().toIso8601String(),
      'last_refresh_status': settings.lastRefreshStatus,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> setCategoryHidden({
    required String playlistId,
    required String categoryId,
    required bool hidden,
    String? profileId,
  }) async {
    final db = await _databaseAdapter.database;
    final targetProfile = profileId ?? 'default';
    if (hidden) {
      await db.insert('hidden_categories', {
        'playlist_id': playlistId,
        'category_id': categoryId,
        'profile_id': targetProfile,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return;
    }

    await db.delete(
      'hidden_categories',
      where: 'playlist_id = ? AND category_id = ? AND profile_id = ?',
      whereArgs: [playlistId, categoryId, targetProfile],
    );
  }

  @override
  Future<bool> isCategoryHidden({
    required String playlistId,
    required String categoryId,
    String? profileId,
  }) async {
    final db = await _databaseAdapter.database;
    final targetProfile = profileId ?? 'default';
    final rows = await db.query(
      'hidden_categories',
      columns: const ['playlist_id'],
      where: 'playlist_id = ? AND category_id = ? AND profile_id = ?',
      whereArgs: [playlistId, categoryId, targetProfile],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> setGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    required bool hidden,
    String? profileId,
  }) async {
    final db = await _databaseAdapter.database;
    final targetProfile = profileId ?? 'default';
    final kindValue = switch (kind) {
      CatalogGroupKind.live => 1,
      CatalogGroupKind.movie => 2,
      CatalogGroupKind.series => 3,
    };
    if (hidden) {
      await db.insert('hidden_groups_v8', {
        'profile_id': targetProfile,
        'playlist_id': playlistId,
        'kind': kindValue,
        'group_title': groupTitle,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      return;
    }
    await db.delete(
      'hidden_groups_v8',
      where:
          'profile_id = ? AND playlist_id = ? AND kind = ? AND group_title = ?',
      whereArgs: [targetProfile, playlistId, kindValue, groupTitle],
    );
  }

  @override
  Future<bool> isGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    String? profileId,
  }) async {
    final db = await _databaseAdapter.database;
    final targetProfile = profileId ?? 'default';
    final kindValue = switch (kind) {
      CatalogGroupKind.live => 1,
      CatalogGroupKind.movie => 2,
      CatalogGroupKind.series => 3,
    };
    final rows = await db.query(
      'hidden_groups_v8',
      columns: const ['playlist_id'],
      where:
          'profile_id = ? AND playlist_id = ? AND kind = ? AND group_title = ?',
      whereArgs: [targetProfile, playlistId, kindValue, groupTitle],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<ManagedPlaylist> _rowToManagedPlaylist(
    Map<String, Object?> row,
  ) async {
    final playlistId = row['id']! as String;
    final secureStorageKey = row['secure_storage_key'] as String?;
    final verificationRecord = _verificationFromRow(row);
    PlaylistSourceConfig? sourceConfig;
    if (secureStorageKey != null && secureStorageKey.isNotEmpty) {
      sourceConfig = PlaylistSourceConfig.fromStorageValue(
        await _secretStore.read(key: secureStorageKey),
        fallbackName: row['name'] as String?,
        verificationRecord: verificationRecord,
      );
    }

    final refreshSettings = PlaylistRefreshSettings(
      playlistId: playlistId,
      refreshEnabled: (row['refresh_enabled'] as int? ?? 1) == 1,
      refreshMode: _dbToRefreshMode[row['refresh_mode']] ?? RefreshMode.weekly,
      refreshIntervalHours: row['refresh_interval_hours'] as int? ?? 168,
      lastRefreshAt: _tryParseDateTime(row['last_refresh_at']),
      nextRefreshAt: _tryParseDateTime(row['next_refresh_at']),
      lastRefreshStatus: row['last_refresh_status'] as String?,
    );

    final resolvedUrl =
        sourceConfig?.resolvedUrl ??
        (row['source_url_redacted'] as String? ?? '');

    return ManagedPlaylist(
      playlistId: playlistId,
      name: sourceConfig?.name.isNotEmpty == true
          ? sourceConfig!.name
          : (row['name'] as String? ?? 'Playlist'),
      enabled: (row['enabled'] as int? ?? 1) == 1,
      sourceConfig: sourceConfig,
      sourceKind: sourceConfig?.kind,
      sourceSummary:
          sourceConfig?.summary ??
          PlaylistSourceConfig._summaryForUrl(
            row['source_url_redacted'] as String? ?? resolvedUrl,
          ),
      resolvedUrl: resolvedUrl,
      sourceUrlRedacted: row['source_url_redacted'] as String?,
      lastImportStatus: row['last_import_status'] as String?,
      lastImportWarning: row['last_import_error'] as String?,
      lastImportCompletedAt: _tryParseDateTime(row['last_import_completed_at']),
      refreshSettings: refreshSettings,
      verificationRecord: verificationRecord,
      connectionRevision: row['source_revision'] as int? ?? 0,
    );
  }

  DateTime? _tryParseDateTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _createPlaylistId(PlaylistSourceConfig config) {
    final seed =
        '${config.kind.name}|${config.name}|${config.resolvedUrl}|${DateTime.now().toUtc().microsecondsSinceEpoch}';
    return 'playlist-${legacyStableId('id', seed)}';
  }
}
