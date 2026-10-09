import 'package:flutter/material.dart';

abstract final class AppTokens {
  static const compactBreakpoint = 600.0;
  static const expandedBreakpoint = 840.0;
  static const compactNavigationFallbackHeight = 520.0;

  static const background = Color(0xff071412);
  static const focusRing = Colors.white;
  static const focusRingWidth = 3.0;
  static const pageInset = 40.0;
  static const sectionGap = 28.0;
  static const cardPadding = 16.0;
  static const compactCardPadding = 14.0;
  static const gridGap = 20.0;
  static const tileWidth = 300.0;
  static const tileHeight = 180.0;
  static const seasonTileHeight = 150.0;
  static const episodeTileWidth = 320.0;
  static const episodeTileHeight = 170.0;
  static const homeStripHeight = 182.0;
  static const homeStripGap = 18.0;
  static const cardRadius = 12.0;
  static const panelRadius = 16.0;
  static const panelPadding = 20.0;
  static const searchInset = 32.0;
  static const playerInset = 32.0;
  static const navigationIndicatorRadius = 99.0;
  static const shellPadding = EdgeInsets.fromLTRB(pageInset, 24, pageInset, 18);
  static const shellTitlePadding = EdgeInsets.fromLTRB(
    pageInset,
    0,
    pageInset,
    12,
  );

  static EdgeInsets shellTitlePaddingFor(double availableWidth) {
    final inset = pageInsetFor(availableWidth);
    return EdgeInsets.fromLTRB(inset, 0, inset, 12);
  }

  static const searchPadding = EdgeInsets.fromLTRB(
    searchInset,
    8,
    searchInset,
    24,
  );
  static const progressRadius = 4.0;
  static const compactBodySize = 16.0;
  static const remoteBodySize = 18.0;
  static const compactTargetSize = 48.0;
  static const remoteTargetSize = 56.0;
  static const focusDuration = Duration(milliseconds: 150);
  static const tileFocusInset = 6.0;
  static const tileFocusScale = 1.02;
  static const artworkDecodeWidth = 640;
  static const artworkDecodeHeight = 360;
  static const pagePadding = EdgeInsets.fromLTRB(
    pageInset,
    8,
    pageInset,
    sectionGap,
  );

  static double pageInsetFor(double availableWidth) =>
      availableWidth < compactBreakpoint
      ? 16
      : availableWidth < expandedBreakpoint
      ? 24
      : pageInset;

  static EdgeInsets pagePaddingFor(double availableWidth) =>
      EdgeInsets.fromLTRB(
        pageInsetFor(availableWidth),
        8,
        pageInsetFor(availableWidth),
        sectionGap,
      );

  static EdgeInsets homePaddingFor(double availableWidth) =>
      EdgeInsets.fromLTRB(
        pageInsetFor(availableWidth),
        0,
        pageInsetFor(availableWidth),
        sectionGap,
      );

  static EdgeInsets searchPaddingFor(double availableWidth) {
    final inset = availableWidth < compactBreakpoint ? 16.0 : searchInset;
    return EdgeInsets.fromLTRB(inset, 8, inset, 24);
  }

  static const homePadding = EdgeInsets.fromLTRB(
    pageInset,
    0,
    pageInset,
    sectionGap,
  );
  static const cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(cardRadius)),
  );
}
