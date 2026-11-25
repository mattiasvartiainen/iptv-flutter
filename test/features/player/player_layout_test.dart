import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/features/player/player_layout.dart';

void main() {
  test('compact height boundary preserves existing geometry', () {
    for (final height in [499.0, 500.0, 501.0]) {
      final compact = height < 500;
      final layout = PlayerLayout.fromConstraints(
        BoxConstraints.tightFor(width: 1280, height: height),
      );
      expect(layout.compact, compact);
      expect(layout.centralIconSize, compact ? 36 : 52);
      expect(layout.technicalFontSize, compact ? 12 : null);
      expect(
        layout.headerPadding,
        EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 4 : 8),
      );
      expect(
        layout.bottomPadding,
        EdgeInsets.fromLTRB(16, compact ? 4 : 28, 16, compact ? 4 : 12),
      );
    }
  });

  test('geometry depends on available height, not device or window width', () {
    for (final width in [320.0, 640.0, 1920.0]) {
      for (final height in [360.0, 844.0, 1080.0]) {
        expect(
          PlayerLayout.fromConstraints(
            BoxConstraints.tightFor(width: width, height: height),
          ).compact,
          height < 500,
        );
      }
    }
  });

  test('track list size respects text scaling and the available window', () {
    expect(PlayerLayout.trackListMaxHeight(360), 180);
    expect(
      PlayerLayout.trackListHeight(
        trackCount: 0,
        textScaler: TextScaler.noScaling,
        availableHeight: 720,
      ),
      isNull,
    );
    expect(
      PlayerLayout.trackListHeight(
        trackCount: 2,
        textScaler: TextScaler.noScaling,
        availableHeight: 720,
      ),
      144,
    );
    expect(
      PlayerLayout.trackListHeight(
        trackCount: 2,
        textScaler: TextScaler.linear(2),
        availableHeight: 720,
      ),
      288,
    );
    expect(
      PlayerLayout.trackListHeight(
        trackCount: 1000,
        textScaler: TextScaler.linear(2),
        availableHeight: 360,
      ),
      162,
    );
  });
}
