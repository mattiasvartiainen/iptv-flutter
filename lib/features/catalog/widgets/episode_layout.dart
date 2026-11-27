import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_tokens.dart';

class EpisodeLayout {
  const EpisodeLayout({
    required this.width,
    required this.height,
    required this.listPreference,
    required this.textScaler,
  });

  final double width;
  final double height;
  final bool listPreference;
  final TextScaler textScaler;

  bool get isRow =>
      listPreference ||
      width < AppTokens.compactBreakpoint ||
      height < AppTokens.compactNavigationFallbackHeight;

  int get columns => isRow
      ? 1
      : math.max(
          1,
          (width / (AppTokens.episodeTileWidth + AppTokens.gridGap)).ceil(),
        );

  SliverGridDelegate get gridDelegate =>
      SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: isRow ? 0 : AppTokens.gridGap,
        mainAxisSpacing: isRow ? 0 : AppTokens.gridGap,
        mainAxisExtent: isRow
            ? AppTokens.episodeRowExtentFor(textScaler)
            : AppTokens.episodeTileHeight,
      );
}
