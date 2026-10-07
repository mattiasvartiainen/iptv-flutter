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
