import '../catalog/catalog_query.dart';
import 'settings_repository.dart';

class AppPreferences {
  AppPreferences({required SettingsRepository settingsRepository})
    : _settingsRepository = settingsRepository;

  final SettingsRepository _settingsRepository;

  static const _showHomeLiveTvKey = 'show_home_live_tv';
  static const _showHomeMoviesKey = 'show_home_movies';
  static const _showHomeSeriesKey = 'show_home_series';
  static const _verboseRefreshInfoKey = 'verbose_refresh_info';
  static const _activePlaylistIdKey = 'active_playlist_id';
  static const _useListViewKey = 'use_list_view';
  static const _liveUseListViewKey = 'live_use_list_view';

  Future<CatalogSort> liveTvSort(String playlistId) =>
      catalogSort(playlistId, CatalogGroupKind.live);

  Future<void> setLiveTvSort(String playlistId, CatalogSort sort) =>
      setCatalogSort(playlistId, CatalogGroupKind.live, sort);

  static String _sortKey(String playlistId, CatalogGroupKind kind) =>
      '${switch (kind) {
        CatalogGroupKind.live => 'live_tv_sort',
        CatalogGroupKind.movie => 'movies_sort',
        CatalogGroupKind.series => 'series_sort',
      }}:$playlistId';

  Future<CatalogSort> catalogSort(
    String playlistId,
    CatalogGroupKind kind,
  ) async {
    final value = await _settingsRepository.getAppSetting(
      _sortKey(playlistId, kind),
    );
    return switch (value) {
      null =>
        kind == CatalogGroupKind.live
            ? CatalogSort.playlistOrder
            : CatalogSort.title,
      'playlistOrder' => CatalogSort.playlistOrder,
      'title' => CatalogSort.title,
      _ => throw const FormatException('Invalid catalog sort preference.'),
    };
  }

  Future<void> setCatalogSort(
    String playlistId,
    CatalogGroupKind kind,
    CatalogSort sort,
  ) => _settingsRepository.setAppSetting(_sortKey(playlistId, kind), sort.name);

  Future<bool> useListView() => _readBool(_useListViewKey, defaultValue: false);

  Future<void> setUseListView(bool enabled) =>
      _writeBool(_useListViewKey, enabled);

  Future<bool> liveUseListView() =>
      _readBool(_liveUseListViewKey, defaultValue: true);

  Future<void> setLiveUseListView(bool enabled) =>
      _writeBool(_liveUseListViewKey, enabled);

  Future<String?> activePlaylistId() =>
      _settingsRepository.getAppSetting(_activePlaylistIdKey);

  Future<void> setActivePlaylistId(String? playlistId) =>
      _settingsRepository.setAppSetting(_activePlaylistIdKey, playlistId ?? '');

  Future<bool> showHomeLiveTv() =>
      _readBool(_showHomeLiveTvKey, defaultValue: true);

  Future<bool> showHomeMovies() =>
      _readBool(_showHomeMoviesKey, defaultValue: true);

  Future<bool> showHomeSeries() =>
      _readBool(_showHomeSeriesKey, defaultValue: true);

  Future<bool> verboseRefreshInfo() =>
      _readBool(_verboseRefreshInfoKey, defaultValue: false);

  Future<void> setShowHomeLiveTv(bool enabled) =>
      _writeBool(_showHomeLiveTvKey, enabled);

  Future<void> setShowHomeMovies(bool enabled) =>
      _writeBool(_showHomeMoviesKey, enabled);

  Future<void> setShowHomeSeries(bool enabled) =>
      _writeBool(_showHomeSeriesKey, enabled);

  Future<void> setVerboseRefreshInfo(bool enabled) =>
      _writeBool(_verboseRefreshInfoKey, enabled);

  Future<bool> _readBool(String key, {required bool defaultValue}) async {
    final value = await _settingsRepository.getAppSetting(key);
    if (value == null) return defaultValue;
    return switch (value.trim().toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' => true,
      '0' || 'false' || 'no' || 'off' => false,
      _ => defaultValue,
    };
  }

  Future<void> _writeBool(String key, bool enabled) =>
      _settingsRepository.setAppSetting(key, enabled ? 'true' : 'false');
}
