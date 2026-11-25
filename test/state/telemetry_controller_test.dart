import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/platform/telemetry_settings_store.dart';
import 'package:iptv_flutter/services/logging/app_logger.dart';
import 'package:iptv_flutter/services/telemetry/app_telemetry.dart';
import 'package:iptv_flutter/services/telemetry/otlp_app_telemetry.dart';
import 'package:iptv_flutter/services/telemetry/telemetry_config.dart';
import 'package:iptv_flutter/state/telemetry_controller.dart';

class _MemoryStore implements TelemetrySettingsStore {
  TelemetryConfig? saved;
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? writeGate;
  int writeCount = 0;
  String? json;
  String? secret;

  @override
  Future<TelemetryConfig?> read() async {
    if (failRead) throw StateError('storage unavailable');
    return saved;
  }

  @override
  Future<void> write(TelemetryConfig config) async {
    writeCount++;
    await writeGate?.future;
    if (failWrite) throw StateError('secure storage unavailable');
    json = jsonEncode(config.toJson());
    secret = config.apiKey;
    saved = TelemetryConfig.fromJson(
      jsonDecode(json!) as Map<String, dynamic>,
      apiKey: secret!,
    );
  }
}

void main() {
  late _MemoryStore store;
  late OtlpAppTelemetry telemetry;
  late TelemetryController controller;
  const defaults = TelemetryConfig(
    endpoint: 'https://default.example',
    serviceName: 'default-service',
    deviceAlias: 'default-device',
  );

  setUp(() {
    store = _MemoryStore();
    telemetry = OtlpAppTelemetry();
    controller = TelemetryController(
      telemetry: telemetry,
      defaults: defaults,
      store: store,
    );
  });

  tearDown(() async {
    controller.dispose();
    await telemetry.close();
  });

  test(
    'actual telemetry starts disabled and absent storage uses defaults',
    () async {
      expect(telemetry.config.enabled, isFalse);
      expect(controller.busy, isFalse);
      expect(controller.status, isNull);
      await controller.initialize();
      expect(controller.config, same(defaults));
      expect(telemetry.deliveries, isEmpty);
      expect(store.writeCount, 0);
    },
  );

  test('failed store read falls back to disabled build defaults', () async {
    store.failRead = true;
    await controller.initialize();
    expect(controller.config, same(defaults));
    expect(controller.status, isNull);
    expect(telemetry.deliveries, isEmpty);
  });

  test('loads stored disabled configuration including secure key', () async {
    store.saved = const TelemetryConfig(
      endpoint: 'https://saved.example',
      apiKey: 'stored-secret',
      verbose: true,
    );
    await controller.initialize();
    expect(controller.config, same(store.saved));
    expect(controller.config.apiKey, 'stored-secret');
    expect(telemetry.deliveries, isEmpty);
  });

  for (final endpoint in [
    'not a URL',
    'ftp://collector.example',
    'https://user:password@collector.example',
    'http://localhost:18888',
    'https://collector.example/v1/traces',
    'https://collector.example?key=secret',
  ]) {
    test('invalid endpoint is rejected before storage: $endpoint', () async {
      final before = controller.config;
      expect(
        await controller.save(TelemetryConfig(endpoint: endpoint)),
        isFalse,
      );
      expect(store.writeCount, 0);
      expect(controller.config, same(before));
      expect(controller.busy, isFalse);
      expect(controller.status, contains('Could not save'));
      expect(controller.status, isNot(contains(endpoint)));
    });
  }

  test('persists configuration with key separate from JSON', () async {
    const config = TelemetryConfig(
      endpoint: 'https://collector.example',
      serviceName: 'living-room',
      deviceAlias: 'tv',
      verbose: true,
      apiKey: 'private-test-key',
      protocol: 'http/json',
    );
    expect(await controller.save(config), isTrue);
    expect(controller.config, same(config));
    expect(store.saved!.toJson(), config.toJson());
    expect(store.secret, config.apiKey);
    expect(store.json, isNot(contains(config.apiKey)));
    expect(store.json, isNot(contains('apiKey')));
    expect(controller.status, 'Telemetry disabled.');
    expect(controller.busy, isFalse);
    expect(telemetry.deliveries, isEmpty);
  });

  test('busy guard rejects overlapping save and send test', () async {
    telemetry.config = const TelemetryConfig(enabled: true);
    store.writeGate = Completer<void>();
    final states = <bool>[];
    controller.addListener(() => states.add(controller.busy));
    const config = TelemetryConfig(endpoint: 'https://first.example');
    final saving = controller.save(config);
    expect(controller.busy, isTrue);
    expect(await controller.save(defaults), isFalse);
    await controller.sendTest();
    await Future<void>.delayed(Duration.zero);
    expect(store.writeCount, 1);
    expect(controller.status, isNull);
    expect(states, [true]);
    store.writeGate!.complete();
    expect(await saving, isTrue);
    expect(states, [true, false]);
    expect(controller.config, same(config));
    expect(telemetry.deliveries, isEmpty);
  });

  test(
    'storage failure keeps enabled telemetry active for the session',
    () async {
      store.failWrite = true;
      const config = TelemetryConfig(
        enabled: true,
        endpoint: 'https://collector.example',
      );
      expect(await controller.save(config), isFalse);
      expect(controller.config, same(config));
      expect(telemetry.enabled, isTrue);
      expect(controller.busy, isFalse);
      expect(controller.status, contains('session'));
      expect(controller.status, contains('could not be saved'));
      expect(store.saved, isNull);
    },
  );

  test('unsaved session exports application and Apply failures', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final payloads = <String>[];
    final subscription = server.listen((request) async {
      payloads.add(await utf8.decoder.bind(request).join());
      request.response.headers.contentType = ContentType.json;
      request.response.write('{}');
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });
    final config = TelemetryConfig(
      enabled: true,
      endpoint: 'http://127.0.0.1:${server.port}',
      protocol: 'http/json',
    );
    await controller.applySession(config);
    expect(store.writeCount, 0);
    expect(telemetry.enabled, isTrue);
    TelemetryAppLogger(const DebugAppLogger(), telemetry).error(
      'application.test',
      error: StateError('sensitive details'),
      stackTrace: StackTrace.current,
    );
    store.failWrite = true;
    expect(await controller.save(config), isFalse);
    expect(await telemetry.flush(), isTrue);
    final payload = payloads.join();
    expect(payload, contains('application.test'));
    expect(payload, contains('telemetry.settings.save failed'));
    expect(payload, contains('StateError'));
    expect(payload, isNot(contains('secure storage unavailable')));
    expect(payload, isNot(contains('sensitive details')));
  });

  test('active operation prevents persistence and configuration', () async {
    telemetry.activeOperations = 1;
    expect(await controller.save(defaults), isFalse);
    expect(store.writeCount, 0);
    expect(controller.status, 'Wait for active operations to finish.');
    expect(controller.busy, isFalse);
    telemetry.activeOperations = 0;
  });

  test('disabled send test does not notify or initialize SDK', () async {
    var notifications = 0;
    controller.addListener(() => notifications++);
    await controller.sendTest();
    expect(notifications, 0);
    expect(controller.status, isNull);
    expect(controller.busy, isFalse);
    expect(telemetry.deliveries, isEmpty);
  });
}
