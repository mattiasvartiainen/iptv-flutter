import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/storage/secure_storage_service.dart';
import '../services/telemetry/telemetry_config.dart';

abstract interface class TelemetrySettingsStore {
  Future<TelemetryConfig?> read();
  Future<void> write(TelemetryConfig config);
}

class FileTelemetrySettingsStore implements TelemetrySettingsStore {
  FileTelemetrySettingsStore(this.secretStore);

  final PlaylistSecretStore secretStore;
  static const _secretKey = 'telemetry_otlp_api_key_v1';

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File(p.join(directory.path, 'telemetry-settings.json'));
  }

  @override
  Future<TelemetryConfig?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    String key = '';
    try {
      key = await secretStore.read(key: _secretKey) ?? '';
    } catch (_) {}
    final config = TelemetryConfig.fromJson(json, apiKey: key);
    config.validate();
    return config;
  }

  @override
  Future<void> write(TelemetryConfig config) async {
    config.validate();
    if (config.apiKey.isNotEmpty) {
      await secretStore.write(key: _secretKey, value: config.apiKey);
    } else {
      await secretStore.delete(key: _secretKey);
    }
    final file = await _file();
    await file.writeAsString(jsonEncode(config.toJson()), flush: true);
  }
}

TelemetryConfig telemetryBuildConfig() => const TelemetryConfig(
  enabled: bool.fromEnvironment('IPTV_TELEMETRY_ENABLED'),
  endpoint: String.fromEnvironment(
    'OTEL_EXPORTER_OTLP_ENDPOINT',
    defaultValue: 'http://localhost:4318',
  ),
  serviceName: String.fromEnvironment(
    'OTEL_SERVICE_NAME',
    defaultValue: 'iptv-app',
  ),
  deviceAlias: String.fromEnvironment(
    'IPTV_DEVICE_ALIAS',
    defaultValue: 'development',
  ),
  verbose: bool.fromEnvironment('IPTV_TELEMETRY_VERBOSE'),
  protocol: String.fromEnvironment(
    'OTEL_EXPORTER_OTLP_PROTOCOL',
    defaultValue: 'http/protobuf',
  ),
);
