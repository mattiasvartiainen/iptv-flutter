import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/features/player/player_layout.dart';
import 'package:iptv_flutter/features/player/widgets/player_error_panel.dart';
import 'package:iptv_flutter/features/player/widgets/player_header.dart';
import 'package:iptv_flutter/features/player/widgets/player_seek_bar.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/ui/theme/app_theme.dart';
import 'package:iptv_flutter/ui/theme/player_theme.dart';

void main() {
  test('defaults preserve the player palette and directional scrims', () {
    const theme = PlayerTheme();
    expect(theme.videoBackground, Colors.black);
    expect(theme.foreground, Colors.white);
    expect(theme.secondaryForeground, Colors.white70);
    expect(theme.warning, Colors.amber);
    expect(theme.errorScrim, Colors.black54);
    expect(theme.controlsFadeDuration, const Duration(milliseconds: 180));
    expect(theme.headerGradient.begin, Alignment.topCenter);
    expect(theme.bottomGradient.begin, Alignment.bottomCenter);
    expect(theme.headerGradient.colors, [Colors.black87, Colors.transparent]);
    expect(theme.bottomGradient.colors, [Colors.black87, Colors.transparent]);
  });

  test('copy and interpolation support inherited theme changes', () {
    const theme = PlayerTheme();
    final other = theme.copyWith(
      foreground: Colors.green,
      secondaryForeground: Colors.blue,
      warning: Colors.red,
      videoBackground: Colors.indigo,
      scrim: Colors.purple,
      errorScrim: Colors.orange,
      controlsFadeDuration: const Duration(milliseconds: 380),
    );
    expect(other.foreground, Colors.green);
    expect(other.secondaryForeground, Colors.blue);
    expect(other.warning, Colors.red);
    expect(other.videoBackground, Colors.indigo);
    expect(other.errorScrim, Colors.orange);
    expect(other.headerGradient.colors.first, Colors.purple);
    expect(other.headerGradient.colors.last.a, 0);
    final halfway = theme.lerp(other, .5);
    expect(halfway.foreground, Color.lerp(Colors.white, Colors.green, .5));
    expect(halfway.controlsFadeDuration, const Duration(milliseconds: 280));
    expect(theme.lerp(null, .5), same(theme));
    expect(theme.copyWith().foreground, theme.foreground);
  });

  test('app input sizing stays separate from player colors and motion', () {
    for (final remote in [false, true]) {
      for (final reducedMotion in [false, true]) {
        final app = AppTheme.dark(
          remoteFirst: remote,
          disableAnimations: reducedMotion,
        );
        final player = app.extension<PlayerTheme>()!;
        expect(player.foreground, Colors.white);
        expect(
          player.controlsFadeDuration,
          reducedMotion ? Duration.zero : const Duration(milliseconds: 180),
        );
        expect(
          app.iconButtonTheme.style!.minimumSize!.resolve({}),
          remote ? const Size(56, 56) : const Size(48, 48),
        );
      }
    }
  });

  testWidgets('header consumes custom player colors and inherited targets', (
    tester,
  ) async {
    final theme = AppTheme.dark(remoteFirst: true).copyWith(
      extensions: [
        const PlayerTheme(
          foreground: Colors.green,
          secondaryForeground: Colors.blue,
          warning: Colors.red,
          scrim: Colors.purple,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: PlayerHeader(
            title: 'Movie',
            playback: const PlaybackState(status: PlaybackStatus.playing),
            layout: PlayerLayout.fromConstraints(
              const BoxConstraints.tightFor(width: 1280, height: 720),
            ),
            canFavorite: true,
            favorite: false,
            favoriteBusy: true,
            controlError: 'Could not save favourite.',
            onBack: () {},
            onToggleFavorite: () {},
          ),
        ),
      ),
    );
    expect(tester.widget<Text>(find.text('Movie')).style!.color, Colors.green);
    expect(tester.widget<Text>(find.text('Playing')).style!.color, Colors.blue);
    expect(
      tester.widget<Text>(find.text('Could not save favourite.')).style!.color,
      Colors.red,
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .color,
      Colors.green,
    );
    expect(
      tester.getSize(find.widgetWithIcon(IconButton, Icons.arrow_back)).height,
      greaterThanOrEqualTo(56),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('seek and error presentation consume the same custom palette', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final theme = AppTheme.dark().copyWith(
      extensions: [
        const PlayerTheme(foreground: Colors.green, errorScrim: Colors.purple),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: PlayerSeekBar(
            focusNode: focus,
            position: const Duration(seconds: 2),
            duration: const Duration(minutes: 1),
            preview: null,
            onChangeStart: (_) {},
            onChanged: (_) {},
            onChangeEnd: (_) {},
          ),
        ),
      ),
    );
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.color, Colors.green);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: PlayerErrorPanel(
            errorKind: PlaybackErrorKind.network,
            onBack: () {},
            onRetry: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.error_outline)).color,
      Colors.green,
    );
    expect(
      tester
          .widget<Text>(find.text('Playback failed: network unavailable.'))
          .style
          ?.color,
      Colors.green,
    );
    expect(
      tester
          .widget<ColoredBox>(
            find
                .descendant(
                  of: find.byType(PlayerErrorPanel),
                  matching: find.byType(ColoredBox),
                )
                .first,
          )
          .color,
      Colors.purple,
    );
    expect(tester.takeException(), isNull);
  });
}
