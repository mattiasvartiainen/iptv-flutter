import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/ui/theme/app_theme.dart';
import 'package:iptv_flutter/ui/theme/app_tokens.dart';

void main() {
  test('preserves the existing dark palette and background', () {
    final theme = AppTheme.dark();
    expect(theme.colorScheme, ThemeData.dark().colorScheme);
    expect(theme.scaffoldBackgroundColor, const Color(0xff071412));
    expect(theme.cardTheme.shape, AppTokens.cardShape);
    expect(
      theme.listTileTheme.selectedTileColor,
      theme.colorScheme.secondaryContainer,
    );
    expect(theme.listTileTheme.selectedTileColor, isNot(AppTokens.focusRing));
  });

  test('compact and remote density use discrete type and target sizes', () {
    for (final remote in [false, true]) {
      final theme = AppTheme.dark(remoteFirst: remote);
      final expectedSize = remote ? 18.0 : 16.0;
      expect(theme.textTheme.bodyLarge?.fontSize, expectedSize);
      expect(theme.textTheme.bodyMedium?.fontSize, expectedSize);
      expect(theme.textTheme.bodySmall?.fontSize, expectedSize);
      for (final style in [
        theme.textButtonTheme.style,
        theme.filledButtonTheme.style,
        theme.elevatedButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.iconButtonTheme.style,
      ]) {
        expect(
          style?.minimumSize?.resolve({}),
          remote ? const Size(56, 56) : const Size(48, 48),
        );
      }
    }
  });

  test('focus styling is distinct and respects input and reduced motion', () {
    final theme = AppTheme.dark(disableAnimations: true);
    final style = theme.filledButtonTheme.style!;
    expect(
      style.side?.resolve({WidgetState.focused}),
      const BorderSide(color: Colors.white, width: 3),
    );
    expect(style.side?.resolve({}), isNull);
    expect(
      style.side?.resolve({WidgetState.disabled, WidgetState.focused}),
      isNull,
    );
    expect(style.animationDuration, Duration.zero);
    expect(
      AppTheme.dark(
        traditionalFocus: false,
      ).filledButtonTheme.style?.side?.resolve({WidgetState.focused}),
      isNull,
    );
  });

  test('text and focus colors meet contrast thresholds on actual surfaces', () {
    final theme = AppTheme.dark();
    final colors = theme.colorScheme;
    double contrast(Color foreground, Color background) {
      final foregroundLuminance = foreground.computeLuminance();
      final backgroundLuminance = background.computeLuminance();
      final brighter = foregroundLuminance > backgroundLuminance
          ? foregroundLuminance
          : backgroundLuminance;
      final darker = foregroundLuminance < backgroundLuminance
          ? foregroundLuminance
          : backgroundLuminance;
      return (brighter + 0.05) / (darker + 0.05);
    }

    for (final surface in [
      AppTokens.background,
      colors.surface,
      colors.surfaceContainerLow,
      colors.surfaceContainerHighest,
    ]) {
      expect(contrast(colors.onSurface, surface), greaterThanOrEqualTo(4.5));
      expect(
        contrast(colors.onSurfaceVariant, surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(AppTokens.focusRing, surface), greaterThanOrEqualTo(3));
    }
    expect(
      contrast(colors.onPrimary, colors.primary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(colors.onSecondaryContainer, colors.secondaryContainer),
      greaterThanOrEqualTo(4.5),
    );
  });

  for (final remote in [false, true]) {
    testWidgets('controls fit with large text, remote=$remote', (tester) async {
      tester.view.physicalSize = remote
          ? const Size(1280, 720)
          : const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      var activations = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(remoteFirst: remote),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Playlist preferences and playback controls'),
                FilledButton(
                  focusNode: focusNode,
                  onPressed: () => activations++,
                  child: const Text('Refresh selected playlist'),
                ),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Open playlist settings'),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('Return to catalog'),
                ),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Play selected stream'),
                ),
                IconButton(
                  onPressed: () {},
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final type in [
        FilledButton,
        OutlinedButton,
        TextButton,
        ElevatedButton,
        IconButton,
      ]) {
        expect(
          tester.getSize(find.byType(type)).height,
          greaterThanOrEqualTo(remote ? 56 : 48),
        );
      }
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(activations, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
