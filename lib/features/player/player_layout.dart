import 'package:flutter/widgets.dart';

/// Constraint-based geometry for the fullscreen player and its dialogs.
@immutable
class PlayerLayout {
  const PlayerLayout._({required this.compact});

  /// Resolves overlay geometry from its allocated space, not its device type.
  ///
  /// Short windows retain the denser overlay. Input-specific target sizes and
  /// accessible text scaling remain the inherited theme's responsibility.
  factory PlayerLayout.fromConstraints(BoxConstraints constraints) =>
      PlayerLayout._(compact: constraints.maxHeight < compactHeight);

  static const compactHeight = 500.0;
  static const volumeWidth = 140.0;
  static const errorMaxWidth = 560.0;
  static const errorPadding = EdgeInsets.all(24);

  final bool compact;

  double get centralIconSize => compact ? 36 : 52;
  double? get technicalFontSize => compact ? 12 : null;
  EdgeInsets get headerPadding =>
      EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 4 : 8);
  EdgeInsets get bottomPadding =>
      EdgeInsets.fromLTRB(16, compact ? 4 : 28, 16, compact ? 4 : 12);

  static const trackDialogWidth = 440.0;
  static double trackListMaxHeight(double availableHeight) =>
      availableHeight * .5;

  static double? trackListHeight({
    required int trackCount,
    required TextScaler textScaler,
    required double availableHeight,
  }) => trackCount == 0
      ? null
      : (trackCount * 72.0 * textScaler.scale(1)).clamp(
          0,
          availableHeight * .45,
        );
}
