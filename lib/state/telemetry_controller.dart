import 'package:flutter/foundation.dart';

import '../platform/telemetry_settings_store.dart';
import '../services/logging/app_logger.dart';
import '../services/telemetry/otlp_app_telemetry.dart';
import '../services/telemetry/telemetry_config.dart';

class TelemetryController extends ChangeNotifier {
  TelemetryController({
    required this.telemetry,
    required this.defaults,
    required this.store,
    this.localLogger = const DebugAppLogger(),
  });

  final OtlpAppTelemetry telemetry;
  final TelemetryConfig defaults;
  final TelemetrySettingsStore store;
  final AppLogger localLogger;
  bool busy = false;
  String? status;
  bool _disposed = false;

  TelemetryConfig get config => telemetry.config;

  Future<void> initialize() async {
    TelemetryConfig config = defaults;
    try {
      config = await store.read() ?? defaults;
    } catch (_) {
      localLogger.warning(
        'Telemetry settings unavailable; using build defaults.',
      );
    }
    try {
      await telemetry.configure(config);
    } catch (_) {
      status = 'Telemetry unavailable. Check configuration.';
      localLogger.warning('Telemetry initialization failed.');
    }
    _notify();
  }

  Future<bool> save(TelemetryConfig config) async {
    if (busy) return false;
    busy = true;
    status = null;
    _notify();
    try {
      config.validate();
      if (telemetry.activeOperations != 0) {
        status = 'Wait for active operations to finish.';
        return false;
      }
      await store.write(config);
      await telemetry.configure(config);
      status = config.enabled ? 'Telemetry enabled.' : 'Telemetry disabled.';
      return true;
    } catch (_) {
      status =
          'Could not save telemetry settings. Check the endpoint and secure storage.';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> sendTest() async {
    if (busy || !config.enabled) return;
    busy = true;
    status = null;
    _notify();
    try {
      await telemetry.measure('telemetry.test', () async {
        telemetry.event('telemetry.test.log');
        await telemetry.measure('telemetry.test.child', () async {});
      });
      final exported = await telemetry.flush();
      status = exported
          ? 'Test exported. Check logs, traces and metrics.'
          : 'Export failed. Check the endpoint and authentication.';
    } catch (_) {
      status = 'Telemetry test failed.';
    } finally {
      busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
