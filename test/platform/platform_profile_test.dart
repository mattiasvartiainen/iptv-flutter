import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/platform/app_platform.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/platform/platform_profile.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

  test('profiles resolve playback backend by target platform', () {
    const desktopBackend = 'media_kit';

    expect(
      resolvePlaybackBackend(
        AppPlatform.android,
        desktopBackend: desktopBackend,
      ),
      PlaybackBackend.videoPlayer,
    );
    expect(
      resolvePlaybackBackend(AppPlatform.webos, desktopBackend: desktopBackend),
      PlaybackBackend.videoPlayer,
    );
    expect(
      resolvePlaybackBackend(
        AppPlatform.windows,
        desktopBackend: desktopBackend,
      ),
      PlaybackBackend.mediaKit,
    );
    expect(
      resolvePlaybackBackend(AppPlatform.linux, desktopBackend: 'fake'),
      PlaybackBackend.fake,
    );
    expect(
      resolvePlaybackBackend(AppPlatform.other, desktopBackend: desktopBackend),
      PlaybackBackend.fake,
    );
  });

  test('native platform profiles provide the FFI database factory', () {
    sqfliteFfiInit();

    for (final platform in const [
      AppPlatform.android,
      AppPlatform.windows,
      AppPlatform.linux,
      AppPlatform.webos,
    ]) {
      expect(
        identical(
          platformProfileFor(platform).createDatabaseFactory(),
          databaseFactoryFfi,
        ),
        isTrue,
        reason: '$platform must retain the existing FFI SQLite backend',
      );
    }
  });
}
