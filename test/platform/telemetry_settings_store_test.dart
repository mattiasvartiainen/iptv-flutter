import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/platform/telemetry_settings_store.dart';
import 'package:iptv_flutter/services/storage/secure_storage_service.dart';
import 'package:iptv_flutter/services/telemetry/telemetry_config.dart';
import 'package:path/path.dart' as p;

class _SecretStore extends InMemoryPlaylistSecretStore {
  bool unavailable = false;
  int deletes = 0;

  @override
  Future<String?> read({required String key}) async {
    if (unavailable) throw StateError('secure storage unavailable');
    return super.read(key: key);
  }

  @override
  Future<void> delete({required String key}) async {
    deletes++;
    if (unavailable) throw StateError('secure storage unavailable');
    await super.delete(key: key);
  }
}

void main() {
  late Directory directory;
  late _SecretStore secrets;
  late FileTelemetrySettingsStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('telemetry-settings-');
    secrets = _SecretStore();
    store = FileTelemetrySettingsStore(
      secrets,
      directoryProvider: () async => directory,
    );
  });

  tearDown(() async => directory.delete(recursive: true));

  test('keyless settings save and reload without secure storage', () async {
    secrets.unavailable = true;
    const config = TelemetryConfig(enabled: true, endpoint: 'http://host:4318');
    await store.write(config);
    await store.write(config);
    final loaded = await store.read();
    expect(loaded!.enabled, isTrue);
    expect(loaded.endpoint, config.endpoint);
    expect(loaded.apiKey, isEmpty);
    expect(secrets.deletes, 0);
  });

  test('removing a saved key clears secure storage', () async {
    await store.write(const TelemetryConfig(apiKey: 'secret'));
    await store.write(const TelemetryConfig());
    expect(secrets.deletes, 1);
    expect((await store.read())!.apiKey, isEmpty);
    expect(
      await File(
        p.join(directory.path, 'telemetry-settings.json'),
      ).readAsString(),
      isNot(contains('secret')),
    );
  });

  test('legacy settings retain and remove their secure key', () async {
    await store.write(const TelemetryConfig(apiKey: 'legacy-secret'));
    final file = File(p.join(directory.path, 'telemetry-settings.json'));
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    json.remove('hasApiKey');
    await file.writeAsString(jsonEncode(json));
    expect((await store.read())!.apiKey, 'legacy-secret');
    await store.write(const TelemetryConfig());
    expect(secrets.deletes, 1);
    expect((await store.read())!.apiKey, isEmpty);
  });
}
