import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/app_route.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/services/catalog/catalog_query_service.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';

import '../support/app_harness.dart';
import '../support/controlled_playback.dart';

const _movie = ContentItem(
  id: 'movie',
  title: 'The Very Long Provider Movie Title With [HD] And Extra Information',
  type: ContentType.vod,
  streamUrl: 'https://fixture.test/private-token/movie',
  group: 'Cinema',
);
const _episode = ContentItem(
  id: 'episode',
  title: 'Harbour Stories S01E01',
  type: ContentType.vod,
  streamUrl: 'https://fixture.test/private-token/series',
  group: 'Series',
);
const _live = ContentItem(
  id: 'live',
  title: 'SVT1 FHD SE [Provider Extra Long Channel Name]',
  type: ContentType.live,
  streamUrl: 'https://fixture.test/private-token/live',
  group: 'Sweden',
);

void main() {
  for (final (label, size) in [
    ('compact portrait', const Size(390, 844)),
    ('remote-first TV', const Size(1920, 1080)),
  ]) {
    testWidgets('live activation returns to its channel on $label', (
      tester,
    ) async {
      final playback = ControlledPlayback();
      final harness = await pumpIptvApp(
        tester,
        size: size,
        mediaQueryData: label == 'compact portrait'
            ? const MediaQueryData(
                padding: EdgeInsets.only(top: 24, bottom: 20),
                viewPadding: EdgeInsets.only(top: 24, bottom: 20),
                disableAnimations: true,
              )
            : null,
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.remote,
          hasHardwareBack: true,
          supportsHover: false,
        ),
        catalogQueryService: InMemoryCatalogQueryService(
          'test-fixture-playlist',
          [_live],
        ),
        playbackAdapter: playback,
      );
      final app = harness.controllers.app;
      app.openLiveTv();
      await tester.pumpAndSettle();
      final tile = find.byKey(const ValueKey<String>('live'));
      if (label == 'compact portrait') {
        final media = MediaQuery.of(
          tester.element(find.byType(Scaffold).first),
        );
        expect(media.padding.top, 24);
        expect(media.disableAnimations, isTrue);
      }
      final focus = Focus.of(
        tester.element(
          find.descendant(of: tile, matching: find.text(_live.title)),
        ),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(playback.calls.where((call) => call.startsWith('load:')), isEmpty);
      expect(find.textContaining('private-token'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<PlayerRoute>());
      expect(playback.calls.where((call) => call == 'load:live'), hasLength(1));
      expect(find.textContaining('private-token'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<CatalogRoute>());
      expect(playback.state.status, PlaybackStatus.stopped);
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('search accepts text with a keyboard inset', (tester) async {
    final playback = ControlledPlayback();
    final harness = await pumpIptvApp(
      tester,
      size: const Size(390, 844),
      mediaQueryData: const MediaQueryData(
        viewInsets: EdgeInsets.only(bottom: 280),
      ),
      catalogQueryService: InMemoryCatalogQueryService(
        'test-fixture-playlist',
        [_live],
      ),
      playbackAdapter: playback,
    );
    harness.controllers.app.openSearch();
    await tester.pumpAndSettle();
    final field = find.byType(TextField);
    expect(
      MediaQuery.of(
        tester.element(find.byType(Scaffold).first),
      ).viewInsets.bottom,
      280,
    );
    await tester.enterText(field, 'SVT1');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.text(_live.title), findsOneWidget);
    expect(playback.calls.where((call) => call.startsWith('load:')), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final (label, size, scale) in [
    ('compact portrait', const Size(390, 844), 1.0),
    ('short landscape', const Size(800, 360), 2.0),
    ('medium', const Size(800, 1000), 1.0),
    ('expanded', const Size(1440, 900), 2.0),
    ('TV', const Size(1920, 1080), 1.0),
  ]) {
    testWidgets('movie playback and Back restore the catalog on $label', (
      tester,
    ) async {
      final playback = ControlledPlayback();
      final harness = await pumpIptvApp(
        tester,
        size: size,
        textScale: scale,
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.remote,
          hasHardwareBack: true,
          supportsHover: false,
        ),
        catalogQueryService: InMemoryCatalogQueryService(
          'test-fixture-playlist',
          [_movie, _episode],
        ),
        playbackAdapter: playback,
      );
      final app = harness.controllers.app;
      app.openMovies();
      await tester.pumpAndSettle();
      expect(playback.calls.where((call) => call.startsWith('load:')), isEmpty);
      expect(find.textContaining('private-token'), findsNothing);
      final tile = find.byKey(const ValueKey<String>('movie'));
      final focus = tester
          .widget<FocusableActionDetector>(
            find
                .descendant(
                  of: tile,
                  matching: find.byType(FocusableActionDetector),
                )
                .first,
          )
          .focusNode!;
      focus.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<DetailsRoute>());
      expect(playback.calls.where((call) => call.startsWith('load:')), isEmpty);
      expect(find.textContaining('private-token'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<PlayerRoute>());
      expect(
        playback.calls.where((call) => call == 'load:movie'),
        hasLength(1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<DetailsRoute>());
      expect(playback.state.status, PlaybackStatus.stopped);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<CatalogRoute>());
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'series episode playback returns to its inline season and focus',
    (tester) async {
      final playback = ControlledPlayback();
      final harness = await pumpIptvApp(
        tester,
        size: const Size(390, 844),
        catalogQueryService: InMemoryCatalogQueryService(
          'test-fixture-playlist',
          [_movie, _episode],
        ),
        playbackAdapter: playback,
      );
      final app = harness.controllers.app;
      app.openSeries();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MediaTile, 'Harbour Stories'));
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<SeriesDetailsRoute>());
      await tester.ensureVisible(find.text('Season 1'));
      await tester.tap(find.text('Season 1'));
      await tester.pumpAndSettle();
      final tile = find.widgetWithText(MediaTile, _episode.title);
      await Scrollable.ensureVisible(tester.element(tile), alignment: 0.1);
      await tester.pumpAndSettle();
      tester.widget<MediaTile>(tile).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(find.textContaining('private-token'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<DetailsRoute>());
      expect(playback.calls.where((call) => call.startsWith('load:')), isEmpty);
      expect(find.textContaining('private-token'), findsNothing);
      await tester.tap(find.text('Play selected stream'));
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<PlayerRoute>());
      expect(
        playback.calls.where((call) => call == 'load:episode'),
        hasLength(1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(playback.state.status, PlaybackStatus.stopped);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.navigationController.currentRoute, isA<SeriesDetailsRoute>());
      expect(find.text('Episodes - Season 1'), findsOneWidget);
      expect(tester.widget<MediaTile>(tile).focusNode!.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
