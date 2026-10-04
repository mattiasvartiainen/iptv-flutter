import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/platform/app_platform.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/platform/platform_profile.dart';

void main() {
  test('platform profile selection provides platform capabilities', () {
    final android = platformProfileFor(AppPlatform.android);
    final windows = platformProfileFor(AppPlatform.windows);
    final webOs = platformProfileFor(AppPlatform.webos);

    expect(android.capabilities.primaryInput, PrimaryInput.touch);
    expect(android.capabilities.hasHardwareBack, isTrue);
    expect(windows.capabilities.primaryInput, PrimaryInput.pointer);
    expect(windows.capabilities.supportsHover, isTrue);
    expect(webOs.capabilities.primaryInput, PrimaryInput.remote);
    expect(webOs.capabilities.isRemoteFirst, isTrue);
  });
}