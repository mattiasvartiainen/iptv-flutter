import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../services/logging/app_logger.dart';
import '../services/playback/desktop_media_kit_playback.dart';
import '../services/playback/fake_playback.dart';
import '../services/playback/playback_adapter.dart';
import '../services/playback/video_player_playback.dart';
import '../services/storage/secure_storage_service.dart';
import 'app_platform.dart';
import 'build_flags.dart' as build_flags;
import 'platform_capabilities.dart';
import 'webos_playback_adapter.dart';
import 'windows_playlist_secret_store.dart';

abstract interface class PlatformProfile {
  AppPlatform get platform;
  PlatformCapabilities get capabilities;
  bool get autoRunPlaybackSpike;
  Map<ShortcutActivator, Intent> get extraShortcuts;

  Future<void> initialize();
  PlaybackAdapter createPlaybackAdapter({
    AppLogger logger = const DebugAppLogger(),
  });
  DatabaseFactory createDatabaseFactory();
  Future<String> getDatabaseDirectory(DatabaseFactory databaseFactory);
  Future<Directory> getTelemetrySettingsDirectory();
  PlaylistSecretStore createSecretStore();
}

enum PlaybackBackend { videoPlayer, webOs, mediaKit, fake }

@visibleForTesting
PlaybackBackend resolvePlaybackBackend(
  AppPlatform platform, {
  required String desktopBackend,
}) => switch (platform) {
  AppPlatform.android => PlaybackBackend.videoPlayer,
  AppPlatform.webos => PlaybackBackend.webOs,
  AppPlatform.linux || AppPlatform.windows when desktopBackend == 'media_kit' =>
    PlaybackBackend.mediaKit,
  AppPlatform.linux ||
  AppPlatform.windows ||
  AppPlatform.other => PlaybackBackend.fake,
};

PlatformProfile platformProfileFor(AppPlatform platform) => switch (platform) {
  AppPlatform.android => const AndroidProfile(),
  AppPlatform.windows ||
  AppPlatform.linux => DesktopProfile(platform: platform),
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
  Map<ShortcutActivator, Intent> get extraShortcuts => const {};

  @override
  Future<void> initialize() async {}

  @override
  DatabaseFactory createDatabaseFactory() => switch (platform) {
    AppPlatform.android ||
    AppPlatform.windows ||
    AppPlatform.linux => _createFfiDatabaseFactory(),
    AppPlatform.webos => sqflite.databaseFactorySqflitePlugin,
    AppPlatform.other => sqflite.databaseFactory,
  };

  static DatabaseFactory _createFfiDatabaseFactory() {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }

  @override
  Future<String> getDatabaseDirectory(DatabaseFactory databaseFactory) async {
    if (platform == AppPlatform.android) {
      final supportDirectory = await getApplicationSupportDirectory();
      final directory = Directory(p.join(supportDirectory.path, 'databases'));
      await directory.create(recursive: true);
      return directory.path;
    }
    return databaseFactory.getDatabasesPath();
  }

  @override
  Future<Directory> getTelemetrySettingsDirectory() =>
      getApplicationSupportDirectory();

  @override
  PlaybackAdapter createPlaybackAdapter({
    AppLogger logger = const DebugAppLogger(),
  }) => switch (resolvePlaybackBackend(
    platform,
    desktopBackend: build_flags.desktopPlaybackBackend,
  )) {
    PlaybackBackend.videoPlayer => VideoPlayerPlaybackAdapter(),
    PlaybackBackend.webOs => WebOsPlaybackAdapter(),
    PlaybackBackend.mediaKit => DesktopMediaKitPlaybackAdapter(
      disableVideoOutput: build_flags.disableDesktopVideoOutput,
      enableHardwareAcceleration:
          !build_flags.disableDesktopHardwareAcceleration,
      logger: logger,
    ),
    PlaybackBackend.fake => FakePlaybackAdapter(),
  };

  @override
  PlaylistSecretStore createSecretStore() => MigratingPlaylistSecretStore(
    secureStore: platform == AppPlatform.windows
        ? WindowsPlaylistSecretStore()
        : SecurePlaylistSecretStore(),
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

final class DesktopProfile extends _PlatformProfile {
  const DesktopProfile({required super.platform})
    : super(
        capabilities: const PlatformCapabilities(
          primaryInput: PrimaryInput.pointer,
          hasHardwareBack: false,
          supportsHover: true,
        ),
      );

  @override
  Future<void> initialize() async {
    if (resolvePlaybackBackend(
          platform,
          desktopBackend: build_flags.desktopPlaybackBackend,
        ) ==
        PlaybackBackend.mediaKit) {
      MediaKit.ensureInitialized();
    }
  }
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

  @override
  Future<Directory> getTelemetrySettingsDirectory() async =>
      webOsAppDataDirectory(Platform.environment);

  @override
  PlaylistSecretStore createSecretStore() =>
      webOsSecretStore(webOsAppDataDirectory(Platform.environment));
}

@visibleForTesting
PlaylistSecretStore webOsSecretStore(Directory directory) =>
    MigratingPlaylistSecretStore(
      secureStore: SecurePlaylistSecretStore(),
      legacyStore: FilePlaylistSecretStore(baseDirectory: directory),
    );

@visibleForTesting
Directory webOsAppDataDirectory(Map<String, String> environment) {
  final base = environment['FLUTTER_APPDATA_HOME'];
  final appId = environment['FLUTTER_APP_ID'];
  if (base == null || base.isEmpty || appId == null || appId.isEmpty) {
    throw StateError('webOS application data directory is unavailable');
  }
  return Directory(p.join(base, appId));
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
