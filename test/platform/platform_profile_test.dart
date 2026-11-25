import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/platform/app_platform.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/platform/platform_profile.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show databaseFactorySqflitePlugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('webOS telemetry data uses the platform app-data directory', () {
    final directory = webOsAppDataDirectory({
      'FLUTTER_APPDATA_HOME': '.data',
      'FLUTTER_APP_ID': 'com.example.iptv',
    });
    expect(directory.path, p.join('.data', 'com.example.iptv'));
    expect(() => webOsAppDataDirectory({}), throwsStateError);
  });

  test('webOS secret store uses app data without path provider', () async {
    final directory = await Directory.systemTemp.createTemp('webos-secrets-');
    addTearDown(() => directory.delete(recursive: true));
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final values = <String, String>{};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      final arguments = call.arguments as Map<Object?, Object?>;
      final key = arguments['key']! as String;
      switch (call.method) {
        case 'write':
          values[key] = arguments['value']! as String;
          return null;
        case 'read':
          return values[key];
        case 'delete':
          values.remove(key);
          return null;
        default:
          throw StateError('Unexpected method: ${call.method}');
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final store = webOsSecretStore(directory);
    await store.write(key: 'playlist:test', value: 'secret');
    expect(await store.read(key: 'playlist:test'), 'secret');
    await store.delete(key: 'playlist:test');
    expect(await store.read(key: 'playlist:test'), isNull);
  });

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

  test('webOS uses the sqflite plugin database factory', () {
    expect(
      identical(
        platformProfileFor(AppPlatform.webos).createDatabaseFactory(),
        databaseFactorySqflitePlugin,
      ),
      isTrue,
      reason:
          'webOS must use the method-channel factory served by sqflite_webos',
    );
  });
}
