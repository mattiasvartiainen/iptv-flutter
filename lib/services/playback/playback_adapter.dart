import 'package:flutter/foundation.dart';

import 'fake_playback.dart';
import 'linux_playback.dart';
import 'playback_contract.dart';
import 'webos_playback.dart';
import 'windows_playback.dart';

export 'playback_contract.dart';
export 'fake_playback.dart';
export 'webos_playback.dart';

const bool isWebOsBuild = bool.fromEnvironment(
  'IPTV_WEBOS',
  defaultValue: false,
);

const String desktopPlaybackBackend = String.fromEnvironment(
  'IPTV_DESKTOP_BACKEND',
  defaultValue: 'media_kit',
);

const bool disableDesktopVideoOutput = bool.fromEnvironment(
  'IPTV_DISABLE_VIDEO_OUTPUT',
  defaultValue: false,
);

const bool disableDesktopHardwareAcceleration = bool.fromEnvironment(
  'IPTV_DISABLE_HW_ACCEL',
  defaultValue: true,
);

bool shouldInitializeMediaKit({bool? webOs}) {
  final useWebOsAdapter = webOs ?? isWebOsBuild;
  if (useWebOsAdapter || kIsWeb) {
    return false;
  }
  final isDesktop =
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;
  return isDesktop && desktopPlaybackBackend == 'media_kit';
}

PlaybackAdapter createPlatformPlaybackAdapter({bool? webOs}) {
  final useWebOsAdapter = webOs ?? isWebOsBuild;
  if (useWebOsAdapter) {
    return WebOsPlaybackAdapter();
  }

  if (kIsWeb) {
    return FakePlaybackAdapter();
  }

  final useMediaKit = desktopPlaybackBackend == 'media_kit';

  switch (defaultTargetPlatform) {
    case TargetPlatform.linux:
      if (useMediaKit) {
        return LinuxPlaybackAdapter(
          disableVideoOutput: disableDesktopVideoOutput,
          enableHardwareAcceleration: !disableDesktopHardwareAcceleration,
        );
      }
      return FakePlaybackAdapter();
    case TargetPlatform.windows:
      if (useMediaKit) {
        return WindowsPlaybackAdapter(
          disableVideoOutput: disableDesktopVideoOutput,
          enableHardwareAcceleration: !disableDesktopHardwareAcceleration,
        );
      }
      return FakePlaybackAdapter();
    default:
      return FakePlaybackAdapter();
  }
}
