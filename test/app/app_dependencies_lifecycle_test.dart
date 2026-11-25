import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/app/app_dependencies.dart';
import 'package:iptv_flutter/platform/app_platform.dart';
import 'package:iptv_flutter/platform/platform_capabilities.dart';
import 'package:iptv_flutter/platform/platform_profile.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/controlled_playback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('owned cleanup awaits native playback and remains idempotent', () async {
    final backend = ControlledPlayback();
    final nativeCleanup = backend.disposalGate = Completer<void>();
    final dependencies = AppDependencies.create(profile: _TestProfile(backend));
    final disposal = dependencies.dispose();
    expect(dependencies.dispose(), same(disposal));
    await Future<void>.delayed(Duration.zero);
    expect(
      ChangeNotifier.debugAssertNotDisposed(
        dependencies.appController.navigationController,
      ),
      isTrue,
    );
    nativeCleanup.complete();
    await disposal;
    expect(
      () => ChangeNotifier.debugAssertNotDisposed(
        dependencies.appController.navigationController,
      ),
      throwsFlutterError,
    );
    expect(backend.calls, ['dispose']);
  });

  test(
    'native cleanup failure still disposes other owned controllers',
    () async {
      final backend = ControlledPlayback()
        ..disposalError = StateError('Native cleanup failed');
      final logger = _Logger();
      final dependencies = AppDependencies.create(
        profile: _TestProfile(backend),
        logger: logger,
      );
      await expectLater(dependencies.dispose(), throwsStateError);
      expect(
        () => ChangeNotifier.debugAssertNotDisposed(
          dependencies.appController.navigationController,
        ),
        throwsFlutterError,
      );
      expect(
        () => ChangeNotifier.debugAssertNotDisposed(
          dependencies.preferencesController,
        ),
        throwsFlutterError,
      );
      expect(
        logger.errors,
        containsAll(['playback_dispose_failed', 'app_dispose_failed']),
      );
      expect(backend.calls, ['dispose']);
    },
  );

  test(
    'Flutter fire-and-forget teardown logs failure without an unhandled future',
    () async {
      final backend = ControlledPlayback()
        ..disposalError = StateError('Native cleanup failed');
      final logger = _Logger();
      final dependencies = AppDependencies.create(
        profile: _TestProfile(backend),
        logger: logger,
      );
      unawaited(dependencies.dispose());
      await Future<void>.delayed(Duration.zero);
      expect(logger.errors, contains('app_dispose_failed'));
    },
  );
}

class _TestProfile implements PlatformProfile {
  _TestProfile(this.backend);
  final PlaybackAdapter backend;

  @override
  AppPlatform get platform => AppPlatform.other;
  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
    primaryInput: PrimaryInput.touch,
    hasHardwareBack: true,
    supportsHover: false,
  );
  @override
  bool get autoRunPlaybackSpike => false;
  @override
  Map<ShortcutActivator, Intent> get extraShortcuts => const {};
  @override
  Future<void> initialize() async {}
  @override
  PlaybackAdapter createPlaybackAdapter({
    AppLogger logger = const DebugAppLogger(),
  }) => backend;
  @override
  DatabaseFactory createDatabaseFactory() => databaseFactoryFfi;
  @override
  PlaylistSecretStore createSecretStore() => InMemoryPlaylistSecretStore();
  @override
  Future<String> getDatabaseDirectory(DatabaseFactory databaseFactory) =>
      throw StateError('Uninitialized teardown must not open a database.');
  @override
  Future<Directory> getTelemetrySettingsDirectory() => throw StateError(
    'Uninitialized teardown must not read telemetry settings.',
  );
}

class _Logger implements AppLogger {
  final errors = <String>[];
  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) => errors.add(message);
  @override
  void info(String message, {Map<String, Object?> context = const {}}) {}
  @override
  void warning(String message, {Map<String, Object?> context = const {}}) {}
}
