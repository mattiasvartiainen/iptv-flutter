import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/ui/theme/app_theme.dart';
import 'package:iptv_flutter/ui/theme/app_tokens.dart';
import 'package:iptv_flutter/ui/widgets/media_artwork.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';

import '../../support/visual_fixture_http.dart';

void main() {
  for (final (label, url) in [
    ('portrait', 'https://example.invalid/portrait.png'),
    ('landscape', 'https://example.invalid/landscape.png'),
    ('missing', 'https://example.invalid/missing.png'),
    ('absent', null),
  ]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('$label poster keeps artwork and title separate at $scale', (
        tester,
      ) async {
        installVisualFixtureHttp();
        final focus = FocusNode();
        addTearDown(focus.dispose);
        final previous = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(() => FocusManager.instance.highlightStrategy = previous);
        var activations = 0;
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.dark(),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: 160,
                      height: AppTokens.posterTileHeightFor(
                        TextScaler.linear(scale),
                      ),
                      child: MediaTile(
                        title: 'A very long movie or series title for testing',
                        subtitle: 'A long group or season count',
                        icon: Icons.movie,
                        imageUrl: url,
                        focusNode: focus,
                        presentation: MediaTilePresentation.poster,
                        onActivate: () => activations++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          focus.requestFocus();
          await tester.pumpAndSettle();
          final artwork = find.byType(MediaArtwork);
          final title = find.text(
            'A very long movie or series title for testing',
          );
          expect(
            tester.getRect(artwork).bottom,
            lessThan(tester.getRect(title).top),
          );
          final image = tester.widget<MediaArtwork>(artwork);
          expect(image.fit, BoxFit.contain);
          expect(image.decodeWidth, 320);
          expect(image.decodeHeight, 480);
          expect(image.resizePolicy, ResizeImagePolicy.fit);
          expect(tester.getRect(artwork).height, greaterThan(100));
          if (label == 'portrait' || label == 'landscape') {
            final loaded = find.descendant(
              of: artwork,
              matching: find.byWidgetPredicate(
                (widget) => widget is RawImage && widget.image != null,
              ),
            );
            for (
              var attempt = 0;
              attempt < 100 && loaded.evaluate().isEmpty;
              attempt++
            ) {
              await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 20)),
              );
              await tester.pump(const Duration(milliseconds: 20));
            }
            expect(loaded, findsOneWidget);
            final decoded = tester.widget<RawImage>(loaded).image!;
            expect(decoded.width, lessThanOrEqualTo(320));
            expect(decoded.height, lessThanOrEqualTo(480));
            expect(
              decoded.width / decoded.height,
              closeTo(label == 'portrait' ? 0.5 : 2, 0.01),
            );
          }
          expect(tester.getSize(find.byType(MediaTile)).width, 160);
          final card = find
              .descendant(
                of: find.byType(MediaTile),
                matching: find.byType(DecoratedBox),
              )
              .first;
          final decoration =
              tester.widget<DecoratedBox>(card).decoration as BoxDecoration;
          expect(
            decoration.border,
            Border.all(
              color: AppTokens.focusRing,
              width: AppTokens.focusRingWidth,
            ),
          );
          final tileRect = tester.getRect(find.byType(MediaTile));
          final focusRect = tester.getRect(card);
          expect(focusRect.left, greaterThanOrEqualTo(tileRect.left));
          expect(focusRect.top, greaterThanOrEqualTo(tileRect.top));
          expect(focusRect.right, lessThanOrEqualTo(tileRect.right));
          expect(focusRect.bottom, lessThanOrEqualTo(tileRect.bottom));
          expect(activations, 0);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.tap(find.byType(MediaTile));
          expect(activations, 3);
          expect(tester.takeException(), isNull);
        } finally {
          uninstallVisualFixtureHttp();
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        }
      });
    }
  }
}
