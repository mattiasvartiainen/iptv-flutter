import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/ui/theme/app_theme.dart';
import 'package:iptv_flutter/ui/theme/app_tokens.dart';
import 'package:iptv_flutter/ui/widgets/media_artwork.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';

void main() {
  for (final textScale in [1.0, 2.0]) {
    testWidgets('compact media row supports touch and keys at $textScale', (
      tester,
    ) async {
      var activations = 0;
      final scaler = TextScaler.linear(textScale);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: scaler),
            child: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 280,
                  height: AppTokens.mediaListExtentFor(scaler),
                  child: MediaTile(
                    title: 'A very long provider title for a live channel',
                    subtitle: 'A long provider group name',
                    listView: true,
                    autofocus: true,
                    onActivate: () => activations++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(MediaTile));
      expect(activations, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activations, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(activations, 3);
    });
  }

  testWidgets('channel rows display bounded logo artwork and fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: MediaTile(
              title: 'Channel',
              imageUrl: 'https://example.invalid/logo.png',
              listView: true,
              showListArtwork: true,
              onActivate: () {},
            ),
          ),
        ),
      ),
    );
    final artwork = tester.widget<MediaArtwork>(find.byType(MediaArtwork));
    expect(artwork.imageUrl, 'https://example.invalid/logo.png');
    expect(tester.getSize(find.byType(MediaArtwork)), const Size(48, 48));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 100,
            child: MediaTile(
              title: 'Channel',
              listView: true,
              showListArtwork: true,
              onActivate: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.ondemand_video), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('channel row separates focused and selected semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final manager = FocusManager.instance;
    final previous = manager.highlightStrategy;
    addTearDown(() => manager.highlightStrategy = previous);
    manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 280,
              height: 100,
              child: MediaTile(
                title: 'A long channel name',
                subtitle: 'Sweden',
                icon: Icons.live_tv,
                focusNode: focus,
                listView: true,
                showListArtwork: true,
                onActivate: () => activations++,
              ),
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pumpAndSettle();
    expect(activations, 0);
    expect(
      tester.getSemantics(find.byType(MediaTile)),
      matchesSemantics(
        label: 'A long channel name',
        value: 'Sweden',
        isButton: true,
        hasSelectedState: true,
        isFocusable: true,
        isFocused: true,
        hasTapAction: true,
      ),
    );
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find.descendant(
                    of: find.byType(MediaTile),
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .decoration
            as BoxDecoration;
    expect(
      decoration.border,
      Border.all(color: AppTokens.focusRing, width: AppTokens.focusRingWidth),
    );
    final animation = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(animation.scale, 1);
    expect(animation.duration, Duration.zero);
    expect(
      tester.getSize(find.byType(MediaTile)).shortestSide,
      greaterThanOrEqualTo(AppTokens.remoteTargetSize),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    expect(activations, 1);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
