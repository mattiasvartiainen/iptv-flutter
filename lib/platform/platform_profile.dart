import 'package:media_kit/media_kit.dart';

import '../services/playback/playback_adapter.dart';
import '../services/storage/secure_storage_service.dart';
import 'app_platform.dart';
import 'build_flags.dart' as build_flags;
import 'platform_capabilities.dart';

abstract interface class PlatformProfile {
  AppPlatform get platform;
  PlatformCapabilities get capabilities;
  bool get autoRunPlaybackSpike;

  Future<void> initialize();
  PlaybackAdapter createPlaybackAdapter();
  PlaylistSecretStore createSecretStore();
}

PlatformProfile platformProfileFor(AppPlatform platform) => switch (platform) {
  AppPlatform.android => const AndroidProfile(),
  AppPlatform.windows => const WindowsProfile(),
  AppPlatform.linux => const LinuxProfile(),
  AppPlatform.webos => const WebOsProfile(),
  AppPlatform.other => const OtherPlatformProfile(),
};

abstract base class _PlatformProfile implements PlatformProfile {
  const _PlatformProfile({required this.platform, required this.capabilities});

  @override
  final AppPlatform platform;

  @override
  final PlatformCapabilities capabilities;

  @override
  bool get autoRunPlaybackSpike => build_flags.autoRunPlaybackSpike;

  @override
  Future<void> initialize() async {
    if (shouldInitializeMediaKit(webOs: platform == AppPlatform.webos)) {
      MediaKit.ensureInitialized();
    }
  }

  @override
  PlaybackAdapter createPlaybackAdapter() =>
      createPlatformPlaybackAdapter(webOs: platform == AppPlatform.webos);

  @override
  PlaylistSecretStore createSecretStore() => MigratingPlaylistSecretStore(
    secureStore: SecurePlaylistSecretStore(),
    legacyStore: FilePlaylistSecretStore(),
  );
}

final class AndroidProfile extends _PlatformProfile {
  const AndroidProfile()
    : super(
        platform: AppPlatform.android,
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.touch,
          hasHardwareBack: true,
          supportsHover: false,
        ),
      );
}

final class WindowsProfile extends _PlatformProfile {
  const WindowsProfile()
    : super(
        platform: AppPlatform.windows,
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.pointer,
          hasHardwareBack: false,
          supportsHover: true,
        ),
      );
}

final class LinuxProfile extends _PlatformProfile {
  const LinuxProfile()
    : super(
        platform: AppPlatform.linux,
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.pointer,
          hasHardwareBack: false,
          supportsHover: true,
        ),
      );
}

final class WebOsProfile extends _PlatformProfile {
  const WebOsProfile()
    : super(
        platform: AppPlatform.webos,
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.remote,
          hasHardwareBack: false,
          supportsHover: false,
        ),
      );
}

final class OtherPlatformProfile extends _PlatformProfile {
  const OtherPlatformProfile()
    : super(
        platform: AppPlatform.other,
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.pointer,
          hasHardwareBack: false,
          supportsHover: false,
        ),
      );
}
