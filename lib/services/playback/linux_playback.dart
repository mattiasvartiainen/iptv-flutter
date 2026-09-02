import 'desktop_media_kit_playback.dart';

class LinuxPlaybackAdapter extends DesktopMediaKitPlaybackAdapter {
  LinuxPlaybackAdapter({
    super.disableVideoOutput,
    super.enableHardwareAcceleration,
  });
}
