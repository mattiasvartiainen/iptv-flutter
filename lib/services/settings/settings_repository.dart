import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../catalog/id_identity.dart';
import '../storage/database_adapter.dart';
import '../storage/secure_storage_service.dart';
import '../storage/storage_contracts.dart';

enum PlaylistSourceKind { url, xtream }

class PlaylistSourceConfig {
  const PlaylistSourceConfig.url({
    this.playlistId,
    required this.name,
    required this.url,
    this.enabled = true,
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

  String get resolvedUrl {
    return switch (kind) {
      PlaylistSourceKind.url => url!.trim(),
      PlaylistSourceKind.xtream =>
        '${_normalizedServer(server!)}/get.php?username=${Uri.encodeQueryComponent(username!.trim())}&password=${Uri.encodeQueryComponent(password!.trim())}&type=m3u_plus&output=m3u8',
    };
  }

  String get summary {
    return switch (kind) {
      PlaylistSourceKind.url => _summaryForUrl(url!),
      PlaylistSourceKind.xtream =>
        '${Uri.tryParse(_normalizedServer(server!))?.host ?? _normalizedServer(server!)} · ${username!.trim()}',
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
  }) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (!trimmed.startsWith('{')) {
      return PlaylistSourceConfig.url(
        name: fallbackName ?? 'Playlist',
        url: trimmed,
      );
    }

    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return null;
    return fromJson(decoded, fallbackName: fallbackName);
  }

  static PlaylistSourceConfig? fromJson(
    Map<String, dynamic> json, {
    String? fallbackName,
  }) {
    final kindName = json['kind'] as String?;
    final name = (json['name'] as String?)?.trim();
    final enabled = json['enabled'] as bool? ?? true;

    switch (kindName) {
      case 'xtream':
        final server = (json['server'] as String?)?.trim();
        final username = (json['username'] as String?)?.trim();
        final password = (json['password'] as String?)?.trim();
        if (server == null || server.isEmpty) return null;
        if (username == null || username.isEmpty) return null;
        if (password == null || password.isEmpty) return null;
        return PlaylistSourceConfig.xtream(
          name: name?.isNotEmpty == true ? name! : (fallbackName ?? 'Playlist'),
          server: server,
          username: username,
          password: password,
          enabled: enabled,
        );
      case 'url':
      default:
        final url = (json['url'] as String?)?.trim();
        if (url == null || url.isEmpty) return null;
        return PlaylistSourceConfig.url(
          name: name?.isNotEmpty == true ? name! : (fallbackName ?? 'Playlist'),
          url: url,
          enabled: enabled,
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
    if (parsed == null) return url.trim();
    if (parsed.host.isEmpty) return url.trim();
    final path = parsed.path.isNotEmpty ? parsed.path : '';
    return '${parsed.host}$path';
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
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository({
    DatabaseAdapter? databaseAdapter,
    PlaylistSecretStore? secretStore,
  }) : _databaseAdapter = databaseAdapter ?? SqfliteDatabaseAdapter(),
       _secretStore = secretStore ?? InMemoryPlaylistSecretStore();

  final DatabaseAdapter _databaseAdapter;
  final PlaylistSecretStore _secretStore;

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
  Future<List<ManagedPlaylist>> listPlaylists() async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery('''
SELECT p.id,
       p.name,
       p.enabled,
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
  Future<ManagedPlaylist?> getPlaylist(String playlistId) async {
    final db = await _databaseAdapter.database;
    final rows = await db.rawQuery(
      '''
SELECT p.id,
       p.name,
       p.enabled,
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
  Future<ManagedPlaylist> upsertPlaylist(PlaylistSourceConfig config) async {
    final db = await _databaseAdapter.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final playlistId = config.playlistId ?? _createPlaylistId(config);
    final secureStorageKey = 'playlist:$playlistId';
    final existingRows = await db.query(
      'playlists',
      columns: const [
        'created_at',
        'last_import_started_at',
        'last_import_completed_at',
        'last_import_staged_rows',
        'last_import_staged_duration_ms',
        'last_import_status',
        'last_import_error',
      ],
      where: 'id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    final existing = existingRows.isNotEmpty ? existingRows.first : null;

    await _secretStore.write(
      key: secureStorageKey,
      value: config.toStorageValue(),
    );

    await db.insert('playlists', {
      'id': playlistId,
      'name': config.name,
      'secure_storage_key': secureStorageKey,
      'source_url_redacted': _redactUrl(config.resolvedUrl),
      'enabled': config.enabled ? 1 : 0,
      'created_at': existing?['created_at'] ?? now,
      'updated_at': now,
      'last_import_started_at': existing?['last_import_started_at'],
      'last_import_completed_at': existing?['last_import_completed_at'],
      'last_import_staged_rows': existing?['last_import_staged_rows'],
      'last_import_staged_duration_ms':
          existing?['last_import_staged_duration_ms'],
      'last_import_status': existing?['last_import_status'] ?? 'never',
      'last_import_error': existing?['last_import_error'],
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    await db.insert('playlist_settings', {
      'playlist_id': playlistId,
      'refresh_enabled': 1,
      'refresh_mode': 'weekly',
      'refresh_interval_hours': 168,
      'last_refresh_at': null,
      'next_refresh_at': null,
      'last_refresh_status': null,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);

    final refreshed = await getPlaylist(playlistId);
    return refreshed!;
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    final db = await _databaseAdapter.database;
    final rows = await db.query(
      'playlists',
      columns: const ['secure_storage_key'],
      where: 'id = ?',
      whereArgs: [playlistId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final secureStorageKey = rows.first['secure_storage_key'] as String?;
      if (secureStorageKey != null && secureStorageKey.isNotEmpty) {
        await _secretStore.delete(key: secureStorageKey);
      }
    }

    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
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

  Future<ManagedPlaylist> _rowToManagedPlaylist(
    Map<String, Object?> row,
  ) async {
    final playlistId = row['id']! as String;
    final secureStorageKey = row['secure_storage_key'] as String?;
    PlaylistSourceConfig? sourceConfig;
    if (secureStorageKey != null && secureStorageKey.isNotEmpty) {
      sourceConfig = PlaylistSourceConfig.fromStorageValue(
        await _secretStore.read(key: secureStorageKey),
        fallbackName: row['name'] as String?,
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
          (row['source_url_redacted'] as String? ?? resolvedUrl),
      resolvedUrl: resolvedUrl,
      sourceUrlRedacted: row['source_url_redacted'] as String?,
      lastImportStatus: row['last_import_status'] as String?,
      lastImportWarning: row['last_import_error'] as String?,
      lastImportCompletedAt: _tryParseDateTime(row['last_import_completed_at']),
      refreshSettings: refreshSettings,
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

  String _redactUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    final auth = uri.userInfo.isNotEmpty ? '***@' : '';
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://$auth${uri.host}$port${uri.path}';
  }
}
