import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/settings/settings_repository.dart';

class InMemorySettingsRepository implements SettingsRepository {
  final Map<String, String> appSettings = {};
  final Map<String, ManagedPlaylist> _playlists = {};
  final List<String> calls = [];

  @override
  Future<String?> getAppSetting(String key) async {
    calls.add('get:$key');
    return appSettings[key];
  }

  @override
  Future<void> setAppSetting(String key, String value) async {
    calls.add('set:$key');
    appSettings[key] = value;
  }

  @override
  Future<List<ManagedPlaylist>> listPlaylists() async {
    calls.add('listPlaylists');
    return _playlists.values.toList(growable: false);
  }

  @override
  Future<ManagedPlaylist?> getPlaylist(String playlistId) async {
    calls.add('getPlaylist:$playlistId');
    return _playlists[playlistId];
  }

  @override
  Future<ManagedPlaylist> upsertPlaylist(PlaylistSourceConfig config) async {
    calls.add('upsertPlaylist');
    final id = config.playlistId ?? 'playlist-${_playlists.length + 1}';
    final playlist = ManagedPlaylist(
      playlistId: id,
      name: config.name,
      enabled: config.enabled,
      sourceConfig: config,
      sourceKind: config.kind,
      sourceSummary: config.summary,
      resolvedUrl: config.resolvedUrl,
      sourceUrlRedacted: null,
      lastImportStatus: null,
      lastImportWarning: null,
      lastImportCompletedAt: null,
      refreshSettings: null,
    );
    _playlists[id] = playlist;
    return playlist;
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    calls.add('deletePlaylist:$playlistId');
    _playlists.remove(playlistId);
  }

  @override
  Future<String?> resolvePlaylistUrl(String playlistId) async =>
      _playlists[playlistId]?.resolvedUrl;

  @override
  Future<PlaylistRefreshSettings?> getPlaylistRefreshSettings(
    String playlistId,
  ) async => null;

  @override
  Future<void> upsertPlaylistRefreshSettings(
    PlaylistRefreshSettings settings,
  ) async {}

  @override
  Future<void> setCategoryHidden({
    required String playlistId,
    required String categoryId,
    required bool hidden,
    String? profileId,
  }) async {}

  @override
  Future<bool> isCategoryHidden({
    required String playlistId,
    required String categoryId,
    String? profileId,
  }) async => false;

  @override
  Future<void> setGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    required bool hidden,
    String? profileId,
  }) async {}

  @override
  Future<bool> isGroupHidden({
    required String playlistId,
    required CatalogGroupKind kind,
    required String groupTitle,
    String? profileId,
  }) async => false;
}
