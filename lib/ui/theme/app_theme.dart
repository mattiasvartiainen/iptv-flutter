import 'package:flutter/material.dart';

import 'app_tokens.dart';

abstract final class AppTheme {
  static ThemeData dark({
    bool remoteFirst = false,
    bool traditionalFocus = true,
    bool disableAnimations = false,
  }) {
    final base = ThemeData.dark();
    final colors = base.colorScheme;
    final bodySize = remoteFirst
        ? AppTokens.remoteBodySize
        : AppTokens.compactBodySize;
    final targetSize = remoteFirst
        ? AppTokens.remoteTargetSize
        : AppTokens.compactTargetSize;
    final focusSide = WidgetStateProperty.resolveWith<BorderSide?>((states) {
      if (!states.contains(WidgetState.disabled) &&
          states.contains(WidgetState.focused) &&
          traditionalFocus) {
        return const BorderSide(
          color: AppTokens.focusRing,
          width: AppTokens.focusRingWidth,
        );
      }
      return null;
    });
    final buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(targetSize, targetSize)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      textStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: bodySize, fontWeight: FontWeight.w600),
      ),
      side: focusSide,
      animationDuration: disableAnimations
          ? Duration.zero
          : AppTokens.focusDuration,
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppTokens.background,
      focusColor: AppTokens.focusRing.withValues(alpha: 0.16),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      textTheme: base.textTheme.copyWith(
        bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: bodySize),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(fontSize: bodySize),
        bodySmall: base.textTheme.bodySmall?.copyWith(fontSize: bodySize),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontSize: bodySize,
          fontWeight: FontWeight.w600,
        ),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontSize: bodySize),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontSize: bodySize),
      ),
      cardTheme: CardThemeData(
        shape: AppTokens.cardShape,
        color: colors.surfaceContainerLow,
      ),
      textButtonTheme: TextButtonThemeData(style: buttonStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle.copyWith(
          side: WidgetStateProperty.resolveWith(
            (states) =>
                focusSide.resolve(states) ?? BorderSide(color: colors.outline),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: buttonStyle.copyWith(
          padding: const WidgetStatePropertyAll(EdgeInsets.all(12)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: targetSize,
        selectedColor: colors.onSecondaryContainer,
        selectedTileColor: colors.secondaryContainer,
      ),
    );
  }
}
