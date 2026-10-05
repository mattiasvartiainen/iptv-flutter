import 'package:flutter/foundation.dart';

import '../services/settings/settings_repository.dart';

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController({required SettingsRepository settingsRepository})
    : _settingsRepository = settingsRepository;

  final SettingsRepository _settingsRepository;

  bool showHomeLiveTv = true;
  bool showHomeMovies = true;
  bool showHomeSeries = true;
  bool verboseRefreshInfo = false;

  static const _verboseRefreshInfoSettingKey = 'verbose_refresh_info';

  Future<void> initialize() async {
    await refreshHomeSectionVisibility();
    await refreshVerboseRefreshInfoSetting();
  }

  Future<void> refreshHomeSectionVisibility() async {
    final live = await _settingsRepository.getAppSetting('show_home_live_tv');
    final movies = await _settingsRepository.getAppSetting('show_home_movies');
    final series = await _settingsRepository.getAppSetting('show_home_series');

    showHomeLiveTv = _parseBoolOrDefault(live, defaultValue: true);
    showHomeMovies = _parseBoolOrDefault(movies, defaultValue: true);
    showHomeSeries = _parseBoolOrDefault(series, defaultValue: true);
    notifyListeners();
  }

  Future<void> setHomeSectionVisibility({
    required String settingKey,
    required bool enabled,
  }) async {
    await _settingsRepository.setAppSetting(
      settingKey,
      enabled ? 'true' : 'false',
    );
    await refreshHomeSectionVisibility();
  }

  Future<void> refreshVerboseRefreshInfoSetting() async {
    final stored = await _settingsRepository.getAppSetting(
      _verboseRefreshInfoSettingKey,
    );
    verboseRefreshInfo = _parseBoolOrDefault(stored, defaultValue: false);
    notifyListeners();
  }

  Future<void> setVerboseRefreshInfo(bool enabled) async {
    await _settingsRepository.setAppSetting(
      _verboseRefreshInfoSettingKey,
      enabled ? 'true' : 'false',
    );
    await refreshVerboseRefreshInfoSetting();
  }

  bool _parseBoolOrDefault(String? value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    return switch (value.trim().toLowerCase()) {
      '1' || 'true' || 'yes' || 'on' => true,
      '0' || 'false' || 'no' || 'off' => false,
      _ => defaultValue,
    };
  }
}
