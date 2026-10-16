import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/platform/app_platform.dart';
import 'package:iptv_flutter/platform/platform_profile.dart';
import 'package:iptv_flutter/platform/windows_playlist_secret_store.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const key = 'playlist:existing:0123456789';
  late Map<String, String> values;
  late List<MethodCall> calls;
  late WindowsPlaylistSecretStore store;
  var failDelete = false;

  setUp(() {
    values = {};
    calls = [];
    failDelete = false;
    store = WindowsPlaylistSecretStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final arguments = call.arguments as Map<Object?, Object?>;
          final storageKey = arguments['key']! as String;
          switch (call.method) {
            case 'write':
              values[storageKey] = arguments['value']! as String;
              return null;
            case 'read':
              return values[storageKey];
            case 'containsKey':
              return values.containsKey(storageKey);
            case 'delete':
              if (failDelete || !values.containsKey(storageKey)) {
                throw PlatformException(code: 'native-delete-failure');
              }
              values.remove(storageKey);
              return null;
            default:
              throw StateError('Unexpected method: ${call.method}');
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Windows profile writes stable filename-safe physical keys', () async {
    final profileStore = platformProfileFor(
      AppPlatform.windows,
    ).createSecretStore();
    await store.write(key: key, value: 'secret');
    await expectLater(profileStore.read(key: key), completion('secret'));
    final physicalKey = values.keys.single;
    expect(physicalKey, matches(RegExp(r'^playlist-v1-[0-9a-f]{64}$')));
    expect(await WindowsPlaylistSecretStore().read(key: key), 'secret');
    await store.write(key: '$key-other', value: 'other');
    expect(values, hasLength(2));
  });

  test('reads existing unencoded keys and prefers new values', () async {
    values[key] = 'old-secret';
    expect(await store.read(key: key), 'old-secret');
    await store.write(key: key, value: 'new-secret');
    expect(await store.read(key: key), 'new-secret');
  });

  test('deleting absent keys never invokes native delete', () async {
    await store.delete(key: key);
    expect(calls.where((call) => call.method == 'delete'), isEmpty);
  });

  test('deletes both physical and old keys and tolerates retries', () async {
    values[key] = 'old-secret';
    await store.write(key: key, value: 'new-secret');
    await store.delete(key: key);
    expect(values, isEmpty);
    await store.delete(key: key);
  });

  test(
    'propagates native deletion failures without dropping secrets',
    () async {
      await store.write(key: key, value: 'secret');
      failDelete = true;
      await expectLater(
        store.delete(key: key),
        throwsA(isA<PlatformException>()),
      );
      expect(values.values.single, 'secret');
    },
  );

  test('migrates plaintext files into Windows-safe secure keys', () async {
    final directory = await Directory.systemTemp.createTemp('windows-secrets-');
    addTearDown(() => directory.delete(recursive: true));
    final legacyStore = FilePlaylistSecretStore(baseDirectory: directory);
    final migratingStore = MigratingPlaylistSecretStore(
      secureStore: store,
      legacyStore: legacyStore,
    );
    await legacyStore.write(key: key, value: 'secret');

    expect(await migratingStore.read(key: key), 'secret');
    expect(await legacyStore.read(key: key), isNull);
    expect(values.keys.single, matches(RegExp(r'^playlist-v1-[0-9a-f]{64}$')));
    await migratingStore.delete(key: key);
    await migratingStore.delete(key: key);
    expect(values, isEmpty);
  });

  test('retains the legacy copy when Windows secure deletion fails', () async {
    final directory = await Directory.systemTemp.createTemp('windows-secrets-');
    addTearDown(() => directory.delete(recursive: true));
    final legacyStore = FilePlaylistSecretStore(baseDirectory: directory);
    final migratingStore = MigratingPlaylistSecretStore(
      secureStore: store,
      legacyStore: legacyStore,
    );
    await legacyStore.write(key: key, value: 'legacy-secret');
    await store.write(key: key, value: 'secret');
    failDelete = true;

    await expectLater(
      migratingStore.delete(key: key),
      throwsA(isA<PlatformException>()),
    );
    expect(await legacyStore.read(key: key), 'legacy-secret');
    expect(values.values.single, 'secret');
  });
}
