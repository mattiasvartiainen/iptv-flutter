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

const bool autoRunPlaybackSpike = bool.fromEnvironment(
  'PLAYBACK_SPIKE_AUTORUN',
  defaultValue: false,
);
