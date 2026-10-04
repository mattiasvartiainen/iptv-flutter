import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/platform/app_platform.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('detectAppPlatform follows Flutter target platform overrides', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(detectAppPlatform(), AppPlatform.android);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(detectAppPlatform(), AppPlatform.windows);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(detectAppPlatform(), AppPlatform.linux);

    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    expect(detectAppPlatform(), AppPlatform.other);
  });

  test('webOS build takes precedence over web and target platform', () {
    expect(
      resolveAppPlatform(
        isWebOsBuild: true,
        isWeb: true,
        targetPlatform: TargetPlatform.linux,
      ),
      AppPlatform.webos,
    );
  });

  test('web builds resolve to other', () {
    expect(
      resolveAppPlatform(
        isWebOsBuild: false,
        isWeb: true,
        targetPlatform: TargetPlatform.android,
      ),
      AppPlatform.other,
    );
  });
}
