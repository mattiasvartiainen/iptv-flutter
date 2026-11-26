import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/navigation/navigation_controller.dart';
import 'package:iptv_flutter/features/player/player_controller.dart';
import 'package:iptv_flutter/features/player/widgets/player_controls.dart';
import 'package:iptv_flutter/features/player/widgets/player_header.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';

import '../../../support/controlled_playback.dart';

const _movie = ContentItem(
  id: 'movie',
  title: 'Movie',
  type: ContentType.vod,
  streamUrl: 'https://example.invalid/movie',
  group: 'Tests',
);
const _live = ContentItem(
  id: 'live',
  title: 'Live',
  type: ContentType.live,
  streamUrl: 'https://example.invalid/live',
  group: 'Tests',
);

void main() {
  late PlayerController player;
  late NavigationController navigation;
  late FocusNode playFocus;
  late FocusNode seekFocus;
  late ControlledPlayback adapter;

  setUp(() {
    navigation = NavigationController();
    adapter = ControlledPlayback(
      capabilities: const PlaybackCapabilities(
        supportsSeek: true,
        supportsPause: true,
        supportsVolume: true,
        supportsDrm: false,
        supportsLiveStreams: true,
      ),
    );
    player = PlayerController(
      playbackAdapter: adapter,
      navigationController: navigation,
    );
    playFocus = FocusNode();
    seekFocus = FocusNode();
  });
  tearDown(() async {
    player.dispose();
    await player.disposalComplete;
    navigation.dispose();
    playFocus.dispose();
    seekFocus.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    ContentItem item = _movie,
    PlaybackStatus status = PlaybackStatus.playing,
    Duration? duration = const Duration(minutes: 1),
    bool buffering = false,
    bool diagnostics = false,
  }) async {
    await tester.runAsync(() => player.openPlayer(item));
    adapter.emit(
      PlaybackState(
        status: status,
        item: item,
        duration: duration,
        isBuffering: buffering,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerControls(
            item: item,
            player: player,
            showDiagnostics: diagnostics,
            playFocus: playFocus,
            seekFocus: seekFocus,
            seekPreview: null,
            onSeekStart: (_) {},
            onSeekChanged: (_) {},
            onSeekEnd: (_) {},
            onBack: () {},
            onChooseSubtitles: () {},
            onChooseAudio: () {},
          ),
        ),
      ),
    );
  }

  testWidgets(
    'live and unknown-duration playback retain disabled seek controls',
    (tester) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('player-seek')), findsOneWidget);
      await pump(tester, item: _live);
      expect(find.byKey(const ValueKey('player-seek')), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.replay_10),
            )
            .onPressed,
        isNull,
      );
      await pump(tester, duration: null);
      expect(find.byKey(const ValueKey('player-seek')), findsNothing);
      await pump(tester, duration: Duration.zero);
      expect(find.byKey(const ValueKey('player-seek')), findsNothing);
    },
  );

  testWidgets(
    'central control retains focus and hides during loading/error/buffering',
    (tester) async {
      await pump(tester);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('player-central-play')),
            )
            .focusNode,
        same(playFocus),
      );
      expect(find.byTooltip('Pause'), findsOneWidget);
      await pump(tester, status: PlaybackStatus.paused);
      expect(find.byTooltip('Play'), findsOneWidget);
      for (final status in [PlaybackStatus.loading, PlaybackStatus.error]) {
        await pump(tester, status: status);
        expect(find.byKey(const ValueKey('player-central-play')), findsNothing);
      }
      await pump(tester, buffering: true);
      expect(find.byKey(const ValueKey('player-central-play')), findsNothing);
    },
  );

  testWidgets(
    'metadata, status and duration changes remain visible without tick rebuilds',
    (tester) async {
      await pump(tester, diagnostics: true);
      final header = tester.widget<PlayerHeader>(find.byType(PlayerHeader));
      for (var i = 1; i <= 20; i++) {
        adapter.emit(adapter.state.copyWith(position: Duration(seconds: i)));
        await tester.pump();
      }
      expect(
        tester.widget<PlayerHeader>(find.byType(PlayerHeader)),
        same(header),
      );
      expect(find.text('00:20 / 01:00'), findsOneWidget);
      adapter.emit(
        adapter.state.copyWith(
          mediaInfo: const PlaybackMediaInfo(
            width: 800,
            height: 600,
            fps: 25,
            videoCodec: 'h264',
            audioCodec: 'aac',
            channelLayout: '5.1',
          ),
        ),
      );
      await tester.pump();
      for (final label in ['800 x 600', '25 fps', 'h264', 'aac', '5.1']) {
        expect(find.text(label), findsOneWidget);
      }
      adapter.emit(adapter.state.copyWith(status: PlaybackStatus.paused));
      await tester.pump();
      expect(find.byTooltip('Play'), findsOneWidget);
      adapter.emit(adapter.state.copyWith(clearDuration: true));
      await tester.pump();
      expect(find.byKey(const ValueKey('player-seek')), findsNothing);
      expect(find.text('00:20 / Unknown'), findsOneWidget);
      adapter.emit(
        adapter.state.copyWith(mediaInfo: PlaybackMediaInfo(fps: double.nan)),
      );
      await tester.pump();
      final unknownHeader = tester.widget<PlayerHeader>(
        find.byType(PlayerHeader),
      );
      adapter.emit(
        adapter.state.copyWith(position: const Duration(seconds: 21)),
      );
      await tester.pump();
      expect(
        tester.widget<PlayerHeader>(find.byType(PlayerHeader)),
        same(unknownHeader),
      );
    },
  );

  testWidgets(
    'unsupported tracks remain disabled and diagnostics remain opt-in',
    (tester) async {
      await pump(tester);
      for (final tooltip in [
        'Subtitles unavailable',
        'Audio track selection unavailable',
      ]) {
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (widget) => widget is IconButton && widget.tooltip == tooltip,
                ),
              )
              .onPressed,
          isNull,
        );
      }
      expect(find.byKey(const ValueKey('player-volume')), findsOneWidget);
      expect(find.textContaining(' / '), findsNothing);
      await pump(tester, diagnostics: true);
      expect(find.textContaining(' / '), findsOneWidget);
    },
  );
}
