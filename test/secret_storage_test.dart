import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'migrates a legacy file secret on first read and removes its JSON file',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'playlist-secret-migration-',
      );
      addTearDown(() => temporaryDirectory.delete(recursive: true));

      final legacyStore = FilePlaylistSecretStore(
        baseDirectory: temporaryDirectory,
      );
      const key = 'playlist:existing';
      const value = '{"kind":"url","url":"https://provider.test/list"}';
      await legacyStore.write(key: key, value: value);

      final secureStore = InMemoryPlaylistSecretStore();
      final migratingStore = MigratingPlaylistSecretStore(
        secureStore: secureStore,
        legacyStore: legacyStore,
      );

      expect(await migratingStore.read(key: key), value);
      expect(await secureStore.read(key: key), value);

      final secretDirectory = Directory(
        p.join(temporaryDirectory.path, 'secure-store'),
      );
      final remainingJsonFiles = await secretDirectory
          .list(recursive: true)
          .where(
            (entity) => entity is File && p.extension(entity.path) == '.json',
          )
          .toList();
      expect(remainingJsonFiles, isEmpty);
    },
  );

  test('writes and deletes only succeed across both stores', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'playlist-secret-write-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final legacyStore = FilePlaylistSecretStore(
      baseDirectory: temporaryDirectory,
    );
    final secureStore = InMemoryPlaylistSecretStore();
    final migratingStore = MigratingPlaylistSecretStore(
      secureStore: secureStore,
      legacyStore: legacyStore,
    );

    await migratingStore.write(key: 'playlist:new', value: 'secret');
    expect(await secureStore.read(key: 'playlist:new'), 'secret');
    expect(await legacyStore.read(key: 'playlist:new'), isNull);

    await migratingStore.delete(key: 'playlist:new');
    expect(await secureStore.read(key: 'playlist:new'), isNull);
  });

  test('keeps the legacy file when writing to secure storage fails', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'playlist-secret-failed-migration-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final legacyStore = FilePlaylistSecretStore(
      baseDirectory: temporaryDirectory,
    );
    const key = 'playlist:existing';
    const value = '{"kind":"url","url":"https://provider.test/list"}';
    await legacyStore.write(key: key, value: value);

    final migratingStore = MigratingPlaylistSecretStore(
      secureStore: _FailingPlaylistSecretStore(),
      legacyStore: legacyStore,
    );

    await expectLater(migratingStore.read(key: key), throwsStateError);
    expect(await legacyStore.read(key: key), value);
  });
}

class _FailingPlaylistSecretStore implements PlaylistSecretStore {
  @override
  Future<void> write({required String key, required String value}) async {
    throw StateError('secure store unavailable');
  }

  @override
  Future<String?> read({required String key}) async => null;

  @override
  Future<void> delete({required String key}) async {}
}
