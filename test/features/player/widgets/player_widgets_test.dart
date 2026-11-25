import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/features/player/player_layout.dart';
import 'package:iptv_flutter/features/player/widgets/player_error_panel.dart';
import 'package:iptv_flutter/features/player/widgets/player_header.dart';
import 'package:iptv_flutter/features/player/widgets/player_seek_bar.dart';
import 'package:iptv_flutter/features/player/widgets/player_track_dialog.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/ui/formatting.dart';

Future<void> _pump(WidgetTester tester, Widget widget) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));

void main() {
  testWidgets('seek preview is controlled by its owner and only end commits', (
    tester,
  ) async {
    final focus = FocusNode(debugLabel: 'Seek test');
    addTearDown(focus.dispose);
    final events = <String>[];
    Widget bar(double? preview) => PlayerSeekBar(
      focusNode: focus,
      position: const Duration(seconds: 2),
      duration: const Duration(minutes: 1),
      preview: preview,
      onChangeStart: (value) => events.add('start:$value'),
      onChanged: (value) => events.add('preview:$value'),
      onChangeEnd: (value) => events.add('commit:$value'),
    );
    await _pump(tester, bar(null));
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('player-seek')),
    );
    expect(slider.focusNode, same(focus));
    expect(slider.value, 2000);
    expect(slider.max, 60000);
    expect(
      slider.semanticFormatterCallback!(3000),
      formatDuration(const Duration(seconds: 3)),
    );
    slider.onChangeStart!(3000);
    slider.onChanged!(4000);
    expect(events, ['start:3000.0', 'preview:4000.0']);
    await _pump(tester, bar(4000));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 4000);
    expect(
      find.text(formatDuration(const Duration(seconds: 4))),
      findsOneWidget,
    );
    slider.onChangeEnd!(4000);
    expect(events.last, 'commit:4000.0');
    await _pump(tester, bar(90000));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 60000);
  });

  testWidgets(
    'header shows only known facts and delegates Back and favourite',
    (tester) async {
      var backs = 0;
      var favorites = 0;
      Widget header({bool busy = false, bool available = true}) => PlayerHeader(
        title: 'Movie',
        playback: const PlaybackState(
          status: PlaybackStatus.playing,
          mediaInfo: PlaybackMediaInfo(
            width: 1920,
            height: 1080,
            fps: 24,
            videoCodec: 'h264',
            audioCodec: 'aac',
            channelLayout: '5.1',
          ),
        ),
        layout: PlayerLayout.fromConstraints(
          const BoxConstraints.tightFor(width: 1280, height: 720),
        ),
        canFavorite: available,
        favorite: true,
        favoriteBusy: busy,
        controlError: 'Could not save favourite.',
        onBack: () => backs++,
        onToggleFavorite: () => favorites++,
      );
      await _pump(tester, header());
      for (final text in [
        'Movie',
        'Playing',
        '1920 x 1080',
        '24 fps',
        'h264',
        'aac',
        '5.1',
        'Could not save favourite.',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Back'));
      await tester.tap(find.byTooltip('Remove from favourites'));
      expect(backs, 1);
      expect(favorites, 1);
      await _pump(tester, header(busy: true));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is IconButton &&
                    widget.tooltip == 'Remove from favourites',
              ),
            )
            .onPressed,
        isNull,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await _pump(tester, header(available: false));
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.favorite))
            .onPressed,
        isNull,
      );
    },
  );

  for (final status in PlaybackStatus.values) {
    testWidgets(
      'header maps $status without guessing invalid technical facts',
      (tester) async {
        await _pump(
          tester,
          PlayerHeader(
            title: 'Movie',
            playback: PlaybackState(
              status: status,
              mediaInfo: PlaybackMediaInfo(
                width: 0,
                height: 1080,
                fps: double.nan,
              ),
            ),
            layout: PlayerLayout.fromConstraints(
              const BoxConstraints.tightFor(width: 640, height: 360),
            ),
            canFavorite: false,
            favorite: null,
            favoriteBusy: false,
            controlError: null,
            onBack: () {},
            onToggleFavorite: () {},
          ),
        );
        final label = switch (status) {
          PlaybackStatus.idle => 'Ready',
          PlaybackStatus.loading => 'Loading stream',
          PlaybackStatus.playing => 'Playing',
          PlaybackStatus.paused => 'Paused',
          PlaybackStatus.stopped => 'Stopped',
          PlaybackStatus.error => 'Playback error',
        };
        expect(find.text(label), findsOneWidget);
        expect(find.textContaining('fps'), findsNothing);
        expect(find.textContaining(' x '), findsNothing);
      },
    );
  }

  for (final subtitle in [false, true]) {
    testWidgets(
      'track dialog selects by remote and delegates cancellation ($subtitle)',
      (tester) async {
        String? selected;
        var cancelled = false;
        await _pump(
          tester,
          PlayerTrackDialog(
            mediaInfo: const PlaybackMediaInfo(
              audioTracks: [
                PlaybackTrack(id: '1', label: 'English'),
                PlaybackTrack(id: '2', label: 'Swedish'),
              ],
              subtitleTracks: [
                PlaybackTrack(id: '1', label: 'English'),
                PlaybackTrack(id: '2', label: 'Swedish'),
              ],
              selectedAudioId: '1',
              selectedSubtitleId: '1',
            ),
            subtitle: subtitle,
            onSelected: (id) => selected = id,
            onCancel: () => cancelled = true,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(subtitle ? 'Subtitles' : 'Audio tracks'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.check), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(selected, '2');
        await tester.tap(find.text('Cancel'));
        expect(cancelled, isTrue);
      },
    );
  }

  testWidgets('empty track dialog retains its explicit Cancel control', (
    tester,
  ) async {
    await _pump(
      tester,
      PlayerTrackDialog(
        mediaInfo: const PlaybackMediaInfo(),
        subtitle: true,
        onSelected: (_) => fail('Empty tracks cannot be selected'),
        onCancel: () {},
      ),
    );
    expect(find.text('No tracks available.'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets(
    'error panel delegates Back and Retry without owning navigation',
    (tester) async {
      var backs = 0;
      var retries = 0;
      await _pump(
        tester,
        PlayerErrorPanel(
          errorKind: PlaybackErrorKind.network,
          onBack: () => backs++,
          onRetry: () => retries++,
        ),
      );
      expect(
        find.text('Playback failed: network unavailable.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Back'));
      await tester.tap(find.text('Retry'));
      expect(backs, 1);
      expect(retries, 1);
    },
  );

  for (final entry in {
    PlaybackErrorKind.configuration:
        'This webOS package must be rebuilt using the supported build script.',
    PlaybackErrorKind.accessDenied: 'Playback failed: access denied.',
    PlaybackErrorKind.notFound: 'Playback failed: stream not found.',
    PlaybackErrorKind.timeout: 'Playback failed: stream timeout.',
    PlaybackErrorKind.unsupportedFormat:
        'Playback failed: unsupported media format.',
    PlaybackErrorKind.network: 'Playback failed: network unavailable.',
    PlaybackErrorKind.unknown: 'Playback failed. Try another stream.',
    null: 'Playback failed. Try another stream.',
  }.entries) {
    testWidgets('error panel maps ${entry.key} to safe product text', (
      tester,
    ) async {
      await _pump(
        tester,
        PlayerErrorPanel(errorKind: entry.key, onBack: () {}, onRetry: () {}),
      );
      expect(find.text(entry.value), findsOneWidget);
    });
  }
}
