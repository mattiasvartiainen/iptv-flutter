import 'package:flutter/foundation.dart';

import '../../platform/build_flags.dart';
import 'fake_playback.dart';
import 'linux_playback.dart';
import 'playback_contract.dart';
import 'video_player_playback.dart';
import 'windows_playback.dart';

export '../../platform/build_flags.dart';
export 'fake_playback.dart';
export 'playback_contract.dart';
export 'video_player_playback.dart';

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
    return VideoPlayerPlaybackAdapter();
  }

  if (kIsWeb) {
    return FakePlaybackAdapter();
  }

  final useMediaKit = desktopPlaybackBackend == 'media_kit';

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return VideoPlayerPlaybackAdapter();
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
