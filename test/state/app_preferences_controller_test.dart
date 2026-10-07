import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';

import '../support/in_memory_settings_repository.dart';

void main() {
  test('initializes defaults when settings are missing', () async {
    final controller = AppPreferencesController(
      settingsRepository: InMemorySettingsRepository(),
    );
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.showHomeLiveTv, isTrue);
    expect(controller.showHomeMovies, isTrue);
    expect(controller.showHomeSeries, isTrue);
    expect(controller.verboseRefreshInfo, isFalse);
  });

  test('loads home visibility and verbose information preferences', () async {
    final settings = InMemorySettingsRepository()
      ..appSettings.addAll({
        'show_home_live_tv': 'false',
        'show_home_movies': 'yes',
        'show_home_series': 'off',
        'verbose_refresh_info': 'true',
      });
    final controller = AppPreferencesController(settingsRepository: settings);
    addTearDown(controller.dispose);

    await controller.initialize();

    expect(controller.showHomeLiveTv, isFalse);
    expect(controller.showHomeMovies, isTrue);
    expect(controller.showHomeSeries, isFalse);
    expect(controller.verboseRefreshInfo, isTrue);
  });

  test(
    'persists a home-section change and refreshes observable state',
    () async {
      final settings = InMemorySettingsRepository();
      final controller = AppPreferencesController(settingsRepository: settings);
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setShowHomeMovies(false);

      expect(settings.appSettings['show_home_movies'], 'false');
      expect(controller.showHomeMovies, isFalse);
      expect(controller.showHomeLiveTv, isTrue);
      expect(controller.showHomeSeries, isTrue);
      expect(notifications, 1);
    },
  );

  test('all typed commands persist and notify observable state', () async {
    final settings = InMemorySettingsRepository();
    final controller = AppPreferencesController(settingsRepository: settings);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setShowHomeLiveTv(false);
    expect(controller.showHomeLiveTv, isFalse);
    expect(settings.appSettings['show_home_live_tv'], 'false');
    expect(notifications, 1);

    await controller.setShowHomeSeries(false);
    expect(controller.showHomeSeries, isFalse);
    expect(settings.appSettings['show_home_series'], 'false');
    expect(notifications, 2);

    await controller.setVerboseRefreshInfo(true);
    expect(controller.verboseRefreshInfo, isTrue);
    expect(settings.appSettings['verbose_refresh_info'], 'true');
    expect(notifications, 3);

    await controller.setShowHomeLiveTv(true);
    await controller.setShowHomeSeries(true);
    await controller.setVerboseRefreshInfo(false);
    expect(controller.showHomeLiveTv, isTrue);
    expect(controller.showHomeSeries, isTrue);
    expect(controller.verboseRefreshInfo, isFalse);
    expect(notifications, 6);
  });
}
