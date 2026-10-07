import 'package:flutter/foundation.dart';

import '../services/settings/app_preferences.dart';
import '../services/settings/settings_repository.dart';

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController({required SettingsRepository settingsRepository})
    : _preferences = AppPreferences(settingsRepository: settingsRepository);

  final AppPreferences _preferences;

  bool showHomeLiveTv = true;
  bool showHomeMovies = true;
  bool showHomeSeries = true;
  bool verboseRefreshInfo = false;

  Future<void> initialize() async {
    await refreshHomeSectionVisibility();
    await refreshVerboseRefreshInfoSetting();
  }

  Future<void> refreshHomeSectionVisibility() async {
    final live = await _preferences.showHomeLiveTv();
    final movies = await _preferences.showHomeMovies();
    final series = await _preferences.showHomeSeries();

    showHomeLiveTv = live;
    showHomeMovies = movies;
    showHomeSeries = series;
    notifyListeners();
  }

  Future<void> setShowHomeLiveTv(bool enabled) async {
    await _preferences.setShowHomeLiveTv(enabled);
    await refreshHomeSectionVisibility();
  }

  Future<void> setShowHomeMovies(bool enabled) async {
    await _preferences.setShowHomeMovies(enabled);
    await refreshHomeSectionVisibility();
  }

  Future<void> setShowHomeSeries(bool enabled) async {
    await _preferences.setShowHomeSeries(enabled);
    await refreshHomeSectionVisibility();
  }

  Future<void> refreshVerboseRefreshInfoSetting() async {
    verboseRefreshInfo = await _preferences.verboseRefreshInfo();
    notifyListeners();
  }

  Future<void> setVerboseRefreshInfo(bool enabled) async {
    await _preferences.setVerboseRefreshInfo(enabled);
    await refreshVerboseRefreshInfoSetting();
  }
}
