import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';

import '../support/in_memory_settings_repository.dart';

void main() {
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

      await controller.setHomeSectionVisibility(
        settingKey: 'show_home_movies',
        enabled: false,
      );

      expect(settings.appSettings['show_home_movies'], 'false');
      expect(controller.showHomeMovies, isFalse);
    },
  );
}
