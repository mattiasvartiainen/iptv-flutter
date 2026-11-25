import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/catalog/catalog_query.dart';
import 'package:iptv_flutter/services/settings/app_preferences.dart';

import '../../support/in_memory_settings_repository.dart';

void main() {
  late InMemorySettingsRepository settings;
  late AppPreferences preferences;

  setUp(() {
    settings = InMemorySettingsRepository();
    preferences = AppPreferences(settingsRepository: settings);
  });

  test('sort preferences are independent per section and playlist', () async {
    expect(
      await preferences.catalogSort('p1', CatalogGroupKind.movie),
      CatalogSort.title,
    );
    expect(
      await preferences.catalogSort('p1', CatalogGroupKind.series),
      CatalogSort.title,
    );
    await preferences.setCatalogSort(
      'p1',
      CatalogGroupKind.movie,
      CatalogSort.playlistOrder,
    );
    final restarted = AppPreferences(settingsRepository: settings);
    expect(
      await restarted.catalogSort('p1', CatalogGroupKind.movie),
      CatalogSort.playlistOrder,
    );
    expect(
      await restarted.catalogSort('p1', CatalogGroupKind.series),
      CatalogSort.title,
    );
    expect(
      await restarted.catalogSort('p2', CatalogGroupKind.movie),
      CatalogSort.title,
    );
    await preferences.setCatalogSort(
      'p1',
      CatalogGroupKind.series,
      CatalogSort.playlistOrder,
    );
    expect(
      await restarted.catalogSort('p1', CatalogGroupKind.series),
      CatalogSort.playlistOrder,
    );
    expect(settings.appSettings, {
      'movies_sort:p1': 'playlistOrder',
      'series_sort:p1': 'playlistOrder',
    });
  });

  test('missing preferences use existing defaults', () async {
    expect(await preferences.activePlaylistId(), isNull);
    expect(await preferences.showHomeLiveTv(), isTrue);
    expect(await preferences.showHomeMovies(), isTrue);
    expect(await preferences.showHomeSeries(), isTrue);
    expect(await preferences.verboseRefreshInfo(), isFalse);
    expect(await preferences.liveTvSort('p1'), CatalogSort.playlistOrder);
    expect(settings.appSettings, isEmpty);
  });

  test(
    'Live TV sort is saved per playlist and survives a new wrapper',
    () async {
      await preferences.setLiveTvSort('p1', CatalogSort.title);
      final reloaded = AppPreferences(settingsRepository: settings);
      expect(await reloaded.liveTvSort('p1'), CatalogSort.title);
      expect(await reloaded.liveTvSort('p2'), CatalogSort.playlistOrder);
      await preferences.setLiveTvSort('p1', CatalogSort.playlistOrder);
      expect(await reloaded.liveTvSort('p1'), CatalogSort.playlistOrder);
    },
  );

  test(
    'invalid Live TV sort reports an error without changing storage',
    () async {
      settings.appSettings['live_tv_sort:p1'] = 'invalid';
      await expectLater(preferences.liveTvSort('p1'), throwsFormatException);
      expect(settings.appSettings['live_tv_sort:p1'], 'invalid');
    },
  );

  test('invalid preferences fall back without overwriting storage', () async {
    settings.appSettings.addAll({
      'show_home_live_tv': '',
      'show_home_movies': 'invalid',
      'show_home_series': '2',
      'verbose_refresh_info': 'invalid',
    });

    expect(await preferences.showHomeLiveTv(), isTrue);
    expect(await preferences.showHomeMovies(), isTrue);
    expect(await preferences.showHomeSeries(), isTrue);
    expect(await preferences.verboseRefreshInfo(), isFalse);
    expect(settings.appSettings['verbose_refresh_info'], 'invalid');
    expect(settings.calls.where((call) => call.startsWith('set:')), isEmpty);
  });

  for (final value in ['1', 'true', 'yes', 'on', ' TRUE ', 'Yes']) {
    test('parses true representation "$value"', () async {
      settings.appSettings['verbose_refresh_info'] = value;
      expect(await preferences.verboseRefreshInfo(), isTrue);
    });
  }

  for (final value in ['0', 'false', 'no', 'off', ' FALSE ', 'Off']) {
    test('parses false representation "$value"', () async {
      settings.appSettings['show_home_live_tv'] = value;
      expect(await preferences.showHomeLiveTv(), isFalse);
    });
  }

  test(
    'active playlist uses the existing key and empty clearing value',
    () async {
      await preferences.setActivePlaylistId('saved-playlist');
      expect(settings.appSettings['active_playlist_id'], 'saved-playlist');
      final reloaded = AppPreferences(settingsRepository: settings);
      expect(await reloaded.activePlaylistId(), 'saved-playlist');

      await preferences.setActivePlaylistId(null);
      expect(settings.appSettings['active_playlist_id'], '');
      expect(await reloaded.activePlaylistId(), '');
    },
  );

  test('typed setters persist canonical values under existing keys', () async {
    for (final enabled in [false, true]) {
      await preferences.setShowHomeLiveTv(enabled);
      await preferences.setShowHomeMovies(enabled);
      await preferences.setShowHomeSeries(enabled);
      await preferences.setVerboseRefreshInfo(enabled);

      expect(settings.appSettings, {
        'show_home_live_tv': '$enabled',
        'show_home_movies': '$enabled',
        'show_home_series': '$enabled',
        'verbose_refresh_info': '$enabled',
      });
      final reloaded = AppPreferences(settingsRepository: settings);
      expect(await reloaded.showHomeLiveTv(), enabled);
      expect(await reloaded.showHomeMovies(), enabled);
      expect(await reloaded.showHomeSeries(), enabled);
      expect(await reloaded.verboseRefreshInfo(), enabled);
    }
  });
}
