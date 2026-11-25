import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app.dart';
import 'package:iptv_flutter/app/app_dependencies.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/services/catalog/favorite_repository.dart';
import 'package:iptv_flutter/services/playback/playback_adapter.dart';
import 'package:iptv_flutter/state/app_controller.dart';
import 'package:iptv_flutter/state/app_preferences_controller.dart';
import 'package:iptv_flutter/state/catalog_view_state.dart';
import 'package:iptv_flutter/state/playlists_controller.dart';

import '../support/catalog_fixtures.dart';
import '../support/in_memory_settings_repository.dart';

typedef _PlayerHarness = ({
  NavigationController navigation,
  PlayerController player,
  PlaylistsController playlists,
  AppPreferencesController preferences,
  CatalogViewState catalog,
});

void _disposeHarness(_PlayerHarness harness) {
  harness.player.dispose();
  harness.playlists.dispose();
  harness.preferences.dispose();
  harness.catalog.dispose();
  harness.navigation.dispose();
}

Future<_PlayerHarness> _pumpPlayerApp(
  WidgetTester tester, {
  Size size = const Size(1280, 720),
  double textScale = 1,
  PlaybackAdapter? playbackAdapter,
  ContentItem? item,
  FavoriteRepository? favorites,
  PlatformCapabilities capabilities = const PlatformCapabilities(
    primaryInput: PrimaryInput.pointer,
    hasHardwareBack: false,
    supportsHover: true,
  ),
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final settings = InMemorySettingsRepository();
  final catalog = CatalogViewState();
  final navigation = NavigationController();
  final preferences = AppPreferencesController(settingsRepository: settings);
  final playlists = PlaylistsController(
    catalogRepository: const FixtureCatalogRepository(),
    settingsRepository: settings,
    catalogView: catalog,
    navigationController: navigation,
    preferencesController: preferences,
  );
  final app = AppController(
    catalogView: catalog,
    navigationController: navigation,
  );
  final player = PlayerController(
    favorites: favorites,
    playbackAdapter:
        playbackAdapter ??
        FakePlaybackAdapter(transitionDelay: const Duration(milliseconds: 1)),
    navigationController: navigation,
  );
  final harness = (
    navigation: navigation,
    player: player,
    playlists: playlists,
    preferences: preferences,
    catalog: catalog,
  );
  addTearDown(() => _disposeHarness(harness));

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
        disableAnimations: disableAnimations,
        accessibleNavigation: accessibleNavigation,
      ),
      child: IptvApp(
        dependencies: AppDependencies.forTesting(
          capabilities: capabilities,
          appController: app,
          playerController: player,
          playlistsController: playlists,
          preferencesController: preferences,
        ),
      ),
    ),
  );
  final opening = player.openPlayer(item ?? fixtureCatalog.first);
  await tester.pump(const Duration(milliseconds: 1));
  await opening;
  await tester.pumpAndSettle();
  return harness;
}

bool _controlsAreIgnoringInput(WidgetTester tester) => tester
    .widget<IgnorePointer>(
      find.byKey(const ValueKey<String>('player-controls')),
    )
    .ignoring;

void main() {
  testWidgets(
    'resize across compact boundary preserves playback, focus and surface',
    (tester) async {
      final adapter = _CountingVideoAdapter();
      final harness = await _pumpPlayerApp(
        tester,
        playbackAdapter: adapter,
        item: _movie,
      );
      await harness.player.pause();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      final session = harness.player.playbackSession;
      final focus = FocusManager.instance.primaryFocus;
      final surface = tester.element(find.byType(_CountingVideoView));
      final initialLoads = adapter.loads;
      for (final size in [
        const Size(640, 360),
        const Size(390, 844),
        const Size(1920, 1080),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('player-central-play')),
              )
              .iconSize,
          size.height < 500 ? 36 : 52,
        );
        expect(harness.player.playbackSession, session);
        expect(
          harness.player.playbackState.value.status,
          PlaybackStatus.paused,
        );
        expect(adapter.loads, initialLoads);
        expect(adapter.viewsCreated, 1);
        expect(tester.element(find.byType(_CountingVideoView)), same(surface));
        expect(FocusManager.instance.primaryFocus, same(focus));
        expect(tester.takeException(), isNull);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(adapter.state.status, PlaybackStatus.playing);
    },
  );

  for (final input in PrimaryInput.values) {
    testWidgets('player targets and remote actions retain $input policy', (
      tester,
    ) async {
      final adapter = _TrackingPlaybackAdapter();
      await _pumpPlayerApp(
        tester,
        size: const Size(640, 360),
        playbackAdapter: adapter,
        item: _movie,
        capabilities: PlatformCapabilities(
          primaryInput: input,
          hasHardwareBack: input != PrimaryInput.pointer,
          supportsHover: input == PrimaryInput.pointer,
        ),
      );
      final back = find.widgetWithIcon(IconButton, Icons.arrow_back);
      final minimum = input == PrimaryInput.remote ? 56.0 : 48.0;
      expect(tester.getSize(back).height, greaterThanOrEqualTo(minimum));
      expect(tester.getSize(back).width, greaterThanOrEqualTo(minimum));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(adapter.state.status, PlaybackStatus.paused);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('reduced motion changes fade only, not auto-hide timing', (
    tester,
  ) async {
    await _pumpPlayerApp(tester, disableAnimations: true);
    final fade = find.descendant(
      of: find.byKey(const ValueKey<String>('player-controls')),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(fade).duration, Duration.zero);
    await tester.pump(const Duration(seconds: 3));
    expect(_controlsAreIgnoringInput(tester), isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(_controlsAreIgnoringInput(tester), isTrue);
  });

  testWidgets('accessible navigation keeps controls available', (tester) async {
    await _pumpPlayerApp(tester, accessibleNavigation: true);
    await tester.pump(const Duration(seconds: 5));
    expect(_controlsAreIgnoringInput(tester), isFalse);
  });

  testWidgets('native-plane background remains transparent', (tester) async {
    await _pumpPlayerApp(tester, playbackAdapter: _NativePlaneAdapter());
    final surface = find.byKey(const ValueKey<String>('player-controls'));
    final scaffold = tester.widget<Scaffold>(
      find.ancestor(of: surface, matching: find.byType(Scaffold)).first,
    );
    expect(scaffold.backgroundColor, Colors.transparent);
    final backgrounds = find.ancestor(
      of: find.byIcon(Icons.ondemand_video),
      matching: find.byType(ColoredBox),
    );
    expect(
      tester.widget<ColoredBox>(backgrounds.first).color,
      Colors.transparent,
    );
  });

  testWidgets(
    'unsafe webOS build reports a setup error and visible Back exits',
    (tester) async {
      final harness = await _pumpPlayerApp(
        tester,
        playbackAdapter: _ConfigurationPlaybackAdapter(),
      );
      expect(
        find.text(
          'This webOS package must be rebuilt using the supported build script.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(harness.navigation.currentRoute, isA<HomeRoute>());
    },
  );
  testWidgets(
    'an obsolete track chooser cannot change a newer playback session',
    (tester) async {
      final adapter = _TrackingPlaybackAdapter();
      final harness = await _pumpPlayerApp(
        tester,
        playbackAdapter: adapter,
        item: _movie,
      );
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pumpAndSettle();
      final opening = harness.player.open(_movie);
      await tester.pump(const Duration(milliseconds: 1));
      await opening;
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(
        harness.player.playbackState.value.mediaInfo.selectedSubtitleId,
        'no',
      );
      expect(harness.navigation.currentRoute, isA<PlayerRoute>());
    },
  );
  testWidgets(
    'position updates retain the video surface without rebuilding it',
    (tester) async {
      final adapter = _CountingVideoAdapter();
      final harness = await _pumpPlayerApp(
        tester,
        playbackAdapter: adapter,
        item: _movie,
      );

      final initialBuilds = adapter.builds;
      for (var i = 1; i <= 20; i++) {
        await harness.player.seekTo(Duration(seconds: i));
        await tester.pump();
      }
      expect(adapter.viewsCreated, 1);
      expect(adapter.builds, initialBuilds);
      expect(initialBuilds, greaterThan(0));
    },
  );
  testWidgets(
    'same-session surface changes replace or remove the visible video',
    (tester) async {
      final adapter = _ReplacingVideoAdapter();
      final harness = await _pumpPlayerApp(
        tester,
        playbackAdapter: adapter,
        item: _movie,
      );
      expect(
        find.byKey(const ValueKey('first-native-surface')),
        findsOneWidget,
      );
      adapter.view = const SizedBox(key: ValueKey('second-native-surface'));
      await harness.player.seekTo(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byKey(const ValueKey('first-native-surface')), findsNothing);
      expect(
        find.byKey(const ValueKey('second-native-surface')),
        findsOneWidget,
      );
      adapter.view = null;
      await harness.player.seekTo(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byKey(const ValueKey('second-native-surface')), findsNothing);
      expect(find.byIcon(Icons.ondemand_video), findsOneWidget);
    },
  );
  testWidgets('tap reveals without pausing, centre pauses and Space resumes', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(tester);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tapAt(const Offset(400, 250));
    await tester.pumpAndSettle();
    expect(_controlsAreIgnoringInput(tester), isFalse);
    expect(harness.player.playbackState.value.status, PlaybackStatus.playing);
    await tester.tap(find.byKey(const ValueKey('player-central-play')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(_controlsAreIgnoringInput(tester), isFalse);
    expect(harness.player.playbackState.value.status, PlaybackStatus.paused);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(harness.player.playbackState.value.status, PlaybackStatus.playing);
  });

  testWidgets(
    'hidden controls exclude focus and remote OK reveals then activates',
    (tester) async {
      final harness = await _pumpPlayerApp(tester);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));
      final exclude = tester.widget<ExcludeFocus>(
        find.descendant(
          of: find.byKey(const ValueKey('player-controls')),
          matching: find.byType(ExcludeFocus),
        ),
      );
      expect(exclude.excluding, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(harness.player.playbackState.value.status, PlaybackStatus.playing);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'Player play pause',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(harness.player.playbackState.value.status, PlaybackStatus.paused);
    },
  );

  testWidgets('visible Back exits immediately', (tester) async {
    final harness = await _pumpPlayerApp(tester);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(harness.navigation.currentRoute, isA<HomeRoute>());
    expect(harness.player.playbackState.value.status, PlaybackStatus.stopped);
  });

  testWidgets(
    'movie slider commits one seek, reports facts and tracks preserve Back',
    (tester) async {
      final adapter = _TrackingPlaybackAdapter();
      final harness = await _pumpPlayerApp(
        tester,
        playbackAdapter: adapter,
        item: _movie,
      );
      expect(find.text('1920 x 1080'), findsOneWidget);
      expect(find.text('23.976 fps'), findsOneWidget);
      expect(find.text('h264'), findsOneWidget);
      expect(find.text('aac'), findsOneWidget);
      expect(find.text('5.1'), findsOneWidget);
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('player-seek')),
      );
      slider.onChangeStart!(1000);
      slider.onChanged!(2000);
      slider.onChanged!(3000);
      expect(adapter.seeks, isEmpty);
      slider.onChangeEnd!(3000);
      await tester.pumpAndSettle();
      expect(adapter.seeks, [const Duration(seconds: 3)]);
      expect(
        harness.player.playbackState.value.position,
        const Duration(seconds: 3),
      );
      expect(_controlsAreIgnoringInput(tester), isFalse);
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('English'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(_controlsAreIgnoringInput(tester), isFalse);
      expect(harness.navigation.currentRoute, isA<PlayerRoute>());
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English'));
      await tester.pumpAndSettle();
      expect(
        harness.player.playbackState.value.mediaInfo.selectedSubtitleId,
        '1',
      );
      await tester.tap(find.byTooltip('Subtitles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      expect(
        harness.player.playbackState.value.mediaInfo.selectedSubtitleId,
        'no',
      );
      await tester.tap(find.byTooltip('Audio tracks'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(harness.player.playbackState.value.mediaInfo.selectedAudioId, '2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'hover reveals and favourite toggles persist through repository',
    (tester) async {
      final library = _Favorites();
      await _pumpPlayerApp(tester, item: _movie, favorites: library);
      await tester.tap(find.byTooltip('Add to favourites'));
      await tester.pumpAndSettle();
      expect(library.value, isTrue);
      expect(find.byTooltip('Remove from favourites'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove from favourites'));
      await tester.pumpAndSettle();
      expect(library.value, isFalse);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 200));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      await mouse.moveTo(const Offset(30, 30));
      await tester.pumpAndSettle();
      expect(_controlsAreIgnoringInput(tester), isFalse);
      await mouse.removePointer();
    },
  );

  for (final size in [
    const Size(640, 360),
    const Size(390, 844),
    const Size(1920, 1080),
  ]) {
    testWidgets('movie controls fit $size at large text scale', (tester) async {
      await _pumpPlayerApp(
        tester,
        size: size,
        textScale: 2,
        item: _movie,
        playbackAdapter: _TrackingPlaybackAdapter(),
      );
      expect(tester.takeException(), isNull);
      final centre = tester.getRect(
        find.byKey(const ValueKey('player-central-play')),
      );
      expect(
        centre.overlaps(
          tester.getRect(find.byKey(const ValueKey('player-seek'))),
        ),
        isFalse,
      );
      for (final label in ['1920 x 1080', '23.976 fps', 'h264', 'aac', '5.1']) {
        expect(centre.overlaps(tester.getRect(find.text(label))), isFalse);
      }
    });

    testWidgets(
      'remote reaches the movie seek slider and arrows seek at $size',
      (tester) async {
        final adapter = _TrackingPlaybackAdapter();
        await _pumpPlayerApp(
          tester,
          size: size,
          playbackAdapter: adapter,
          item: _movie,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Player seek');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(adapter.seeks, isNotEmpty);
        expect(adapter.state.position, greaterThan(Duration.zero));
      },
    );
  }
  testWidgets('player renders fullscreen video surface and readable overlay', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(tester);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(Scaffold), findsWidgets);
    expect(find.text(fixtureCatalog.first.title), findsOneWidget);
    expect(find.text('Playing'), findsOneWidget);
    expect(find.byIcon(Icons.ondemand_video), findsOneWidget);
    expect(_controlsAreIgnoringInput(tester), isFalse);
    expect(harness.navigation.currentRoute, isA<PlayerRoute>());
    expect(tester.takeException(), isNull);
  });

  testWidgets('controls auto-hide and a media key reveals and pauses', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(tester);
    expect(_controlsAreIgnoringInput(tester), isFalse);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_controlsAreIgnoringInput(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pumpAndSettle();
    expect(_controlsAreIgnoringInput(tester), isFalse);
    expect(harness.player.playbackState.value.status, PlaybackStatus.paused);
  });

  testWidgets('player Back hides controls before closing playback', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(_controlsAreIgnoringInput(tester), isTrue);
    expect(harness.navigation.currentRoute, isA<PlayerRoute>());
    expect(harness.player.playbackState.value.status, PlaybackStatus.playing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(harness.navigation.currentRoute, isA<HomeRoute>());
    expect(harness.player.playbackState.value.status, PlaybackStatus.stopped);
  });

  testWidgets('system Back hides the overlay before leaving the player', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_controlsAreIgnoringInput(tester), isTrue);
    expect(harness.navigation.currentRoute, isA<PlayerRoute>());

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(harness.navigation.currentRoute, isA<HomeRoute>());
    expect(harness.player.playbackState.value.status, PlaybackStatus.stopped);
  });

  testWidgets('playback error panel retries through the player controller', (
    tester,
  ) async {
    final adapter = _RecoveringPlaybackAdapter();
    final harness = await _pumpPlayerApp(tester, playbackAdapter: adapter);
    expect(harness.player.playbackState.value.status, PlaybackStatus.error);
    expect(find.text('Playback failed. Try another stream.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(harness.player.playbackState.value.status, PlaybackStatus.playing);
    expect(find.text('Playback failed. Try another stream.'), findsNothing);
  });

  testWidgets('focused controls stay visible and compact large text fits', (
    tester,
  ) async {
    final harness = await _pumpPlayerApp(
      tester,
      size: const Size(390, 844),
      textScale: 2,
    );
    final pause = find.byTooltip('Pause');
    Focus.of(tester.element(pause)).requestFocus();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(_controlsAreIgnoringInput(tester), isFalse);
    expect(harness.navigation.currentRoute, isA<PlayerRoute>());
    expect(tester.takeException(), isNull);
  });
}

const _movie = ContentItem(
  group: 'Movies',
  id: 'movie',
  title: 'Movie',
  type: ContentType.vod,
  streamUrl: 'https://example.invalid/movie.mp4',
  catalogPlaylistId: 'playlist',
  catalogItemKey: 42,
);

class _TrackingPlaybackAdapter extends FakePlaybackAdapter {
  _TrackingPlaybackAdapter()
    : super(
        transitionDelay: const Duration(milliseconds: 1),
        duration: const Duration(minutes: 90),
        mediaInfo: const PlaybackMediaInfo(
          width: 1920,
          height: 1080,
          fps: 23.976,
          videoCodec: 'h264',
          audioCodec: 'aac',
          channelLayout: '5.1',
          audioTracks: [
            PlaybackTrack(id: 'auto', label: 'Auto'),
            PlaybackTrack(id: '2', label: 'Swedish'),
          ],
          subtitleTracks: [
            PlaybackTrack(id: 'no', label: 'Off'),
            PlaybackTrack(id: '1', label: 'English'),
          ],
          selectedAudioId: 'auto',
          selectedSubtitleId: 'no',
        ),
      );
  final seeks = <Duration>[];
  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    await super.seek(position);
  }
}

class _Favorites implements FavoriteRepository {
  bool value = false;
  @override
  Future<bool> isFavorite({
    required String playlistId,
    required int itemKey,
    String profileId = 'default',
  }) async => value;
  @override
  Future<void> setFavorite({
    required String playlistId,
    required int itemKey,
    required bool favorite,
    String profileId = 'default',
  }) async => value = favorite;
}

class _CountingVideoAdapter extends _TrackingPlaybackAdapter {
  int loads = 0;
  int viewsCreated = 0;
  int builds = 0;
  Widget? _view;
  @override
  Future<void> load(ContentItem item) {
    loads++;
    _view = null;
    return super.load(item);
  }

  @override
  Widget buildVideoView() {
    return _view ??= _createView();
  }

  Widget _createView() {
    viewsCreated++;
    return _CountingVideoView(onBuild: () => builds++);
  }
}

class _ReplacingVideoAdapter extends _TrackingPlaybackAdapter {
  Widget? view = const SizedBox(key: ValueKey('first-native-surface'));
  @override
  Widget? buildVideoView() => view;
}

class _CountingVideoView extends StatelessWidget {
  const _CountingVideoView({required this.onBuild});
  final VoidCallback onBuild;
  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox.expand();
  }
}

class _ConfigurationPlaybackAdapter extends FakePlaybackAdapter {
  @override
  Future<void> load(ContentItem item) async =>
      throw PlaybackConfigurationError();
}

class _NativePlaneAdapter extends _TrackingPlaybackAdapter {
  @override
  PlaybackCapabilities get capabilities => const PlaybackCapabilities(
    supportsSeek: true,
    supportsPause: true,
    supportsVolume: false,
    supportsDrm: false,
    supportsLiveStreams: true,
    usesPlatformVideoPlane: true,
  );
}

class _RecoveringPlaybackAdapter extends FakePlaybackAdapter {
  _RecoveringPlaybackAdapter()
    : super(transitionDelay: const Duration(milliseconds: 1));

  int _loadCount = 0;

  @override
  Future<void> load(ContentItem item) async {
    if (_loadCount++ == 0) throw StateError('temporary playback failure');
    await super.load(item);
  }
}
