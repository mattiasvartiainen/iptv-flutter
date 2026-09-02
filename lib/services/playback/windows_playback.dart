import 'desktop_media_kit_playback.dart';

class WindowsPlaybackAdapter extends DesktopMediaKitPlaybackAdapter {
  WindowsPlaybackAdapter({
    super.disableVideoOutput,
    super.enableHardwareAcceleration,
  });
}
