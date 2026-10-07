import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/ui/theme/app_theme.dart';
import 'package:iptv_flutter/ui/theme/app_tokens.dart';
import 'package:iptv_flutter/ui/widgets/media_tile.dart';

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    required VoidCallback onActivate,
    FocusNode? focusNode,
    bool selected = false,
    bool autofocus = false,
    bool disableAnimations = false,
    String? imageUrl,
    double width = 300,
    double height = 180,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: height,
                child: MediaTile(
                  title: 'A long title for a movie or series episode',
                  subtitle: 'Sports and entertainment',
                  icon: Icons.movie,
                  imageUrl: imageUrl,
                  focusNode: focusNode,
                  selected: selected,
                  autofocus: autofocus,
                  onActivate: onActivate,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'focus and hover do not activate; Enter Select and touch activate once',
    (tester) async {
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final manager = FocusManager.instance;
      final previous = manager.highlightStrategy;
      addTearDown(() => manager.highlightStrategy = previous);
      manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      var activations = 0;
      await pumpTile(
        tester,
        focusNode: focusNode,
        onActivate: () => activations++,
      );
      final size = tester.getSize(find.byType(MediaTile));
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      await pointer.moveTo(tester.getCenter(find.byType(MediaTile)));
      await tester.pump();
      expect(activations, 0);
      await pointer.removePointer();
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      expect(activations, 0);
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
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        AppTokens.tileFocusScale,
      );
      expect(tester.getSize(find.byType(MediaTile)), size);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activations, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      expect(activations, 2);
      await tester.tap(find.byType(MediaTile));
      expect(activations, 3);
    },
  );

  testWidgets('autofocus and accessibility tap share the activation command', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    var activations = 0;
    await pumpTile(
      tester,
      autofocus: true,
      focusNode: focusNode,
      onActivate: () => activations++,
    );
    expect(focusNode.hasFocus, isTrue);
    expect(activations, 0);
    final semanticWidget = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label ==
                'A long title for a movie or series episode',
      ),
    );
    semanticWidget.properties.onTap!();
    expect(activations, 1);
    semantics.dispose();
  });

  testWidgets(
    'selection semantics remain distinct from touch focus and reduced motion',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      final manager = FocusManager.instance;
      final previous = manager.highlightStrategy;
      addTearDown(() => manager.highlightStrategy = previous);
      manager.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
      await pumpTile(
        tester,
        selected: true,
        focusNode: focusNode,
        disableAnimations: true,
        onActivate: () {},
      );
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      final node = tester.getSemantics(find.byType(MediaTile));
      expect(
        node,
        matchesSemantics(
          label: 'A long title for a movie or series episode',
          value: 'Sports and entertainment',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isFocusable: true,
          isFocused: true,
          hasTapAction: true,
        ),
      );
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      manager.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
      await tester.pumpAndSettle();
      final animation = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(animation.scale, 1);
      expect(animation.duration, Duration.zero);
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
      expect(decoration.border, Border.all(color: Colors.white, width: 3));
      semantics.dispose();
    },
  );

  testWidgets('missing and failed artwork use fallback with bounded decoding', (
    tester,
  ) async {
    await pumpTile(tester, onActivate: () {});
    expect(find.byIcon(Icons.movie), findsOneWidget);
    await pumpTile(
      tester,
      imageUrl: 'https://fixture.test/missing.png',
      onActivate: () {},
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>());
    expect((image.image as ResizeImage).width, AppTokens.artworkDecodeWidth);
    final fallback = image.errorBuilder!(
      tester.element(find.byType(Image)),
      StateError('unavailable'),
      null,
    );
    expect(fallback, isA<Icon>());
    expect(find.byIcon(Icons.movie), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(160, 150),
    const Size(300, 180),
    const Size(320, 170),
  ]) {
    testWidgets('large text fits fixed tile $size without layout overflow', (
      tester,
    ) async {
      await pumpTile(
        tester,
        width: size.width,
        height: size.height,
        textScale: 2,
        onActivate: () {},
      );
      expect(tester.getSize(find.byType(MediaTile)), size);
      expect(size.shortestSide, greaterThanOrEqualTo(56));
      expect(tester.takeException(), isNull);
    });
  }
}
