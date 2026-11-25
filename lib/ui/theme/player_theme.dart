import 'package:flutter/material.dart';

/// Customizable player colors and motion, independent of playback behavior.
@immutable
class PlayerTheme extends ThemeExtension<PlayerTheme> {
  const PlayerTheme({
    this.videoBackground = Colors.black,
    this.foreground = Colors.white,
    this.secondaryForeground = Colors.white70,
    this.warning = Colors.amber,
    this.scrim = Colors.black87,
    this.errorScrim = Colors.black54,
    this.controlsFadeDuration = const Duration(milliseconds: 180),
  });

  final Color videoBackground;
  final Color foreground;
  final Color secondaryForeground;
  final Color warning;
  final Color scrim;
  final Color errorScrim;
  final Duration controlsFadeDuration;

  /// Returns the inherited player theme, or the standard playback palette.
  static PlayerTheme of(BuildContext context) =>
      Theme.of(context).extension<PlayerTheme>() ?? const PlayerTheme();

  LinearGradient get headerGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [scrim, scrim.withValues(alpha: 0)],
  );

  LinearGradient get bottomGradient => LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [scrim, scrim.withValues(alpha: 0)],
  );

  @override
  PlayerTheme copyWith({
    Color? videoBackground,
    Color? foreground,
    Color? secondaryForeground,
    Color? warning,
    Color? scrim,
    Color? errorScrim,
    Duration? controlsFadeDuration,
  }) => PlayerTheme(
    videoBackground: videoBackground ?? this.videoBackground,
    foreground: foreground ?? this.foreground,
    secondaryForeground: secondaryForeground ?? this.secondaryForeground,
    warning: warning ?? this.warning,
    scrim: scrim ?? this.scrim,
    errorScrim: errorScrim ?? this.errorScrim,
    controlsFadeDuration: controlsFadeDuration ?? this.controlsFadeDuration,
  );

  @override
  PlayerTheme lerp(covariant PlayerTheme? other, double t) {
    if (other == null) return this;
    return PlayerTheme(
      videoBackground: Color.lerp(videoBackground, other.videoBackground, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      secondaryForeground: Color.lerp(
        secondaryForeground,
        other.secondaryForeground,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      errorScrim: Color.lerp(errorScrim, other.errorScrim, t)!,
      controlsFadeDuration: Duration(
        microseconds:
            (controlsFadeDuration.inMicroseconds +
                    (other.controlsFadeDuration.inMicroseconds -
                            controlsFadeDuration.inMicroseconds) *
                        t)
                .round(),
      ),
    );
  }
}
