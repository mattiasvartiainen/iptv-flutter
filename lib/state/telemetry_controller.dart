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
  int _configurationRevision = 0;

  TelemetryConfig get config => telemetry.config;

  Future<void> initialize() async {
    final revision = _configurationRevision;
    TelemetryConfig config = defaults;
    try {
      config = await store.read() ?? defaults;
    } catch (_) {
      localLogger.warning(
        'Telemetry settings unavailable; using build defaults.',
      );
    }
    if (revision != _configurationRevision) return;
    try {
      await telemetry.configure(config);
    } catch (_) {
      status = 'Telemetry unavailable. Check configuration.';
      localLogger.warning('Telemetry initialization failed.');
    }
    _notify();
  }

  Future<void> applySession(TelemetryConfig config) async {
    if (busy) return;
    _configurationRevision++;
    busy = true;
    status = null;
    _notify();
    try {
      config.validate();
      if (telemetry.activeOperations != 0) {
        status = 'Wait for active operations to finish.';
        return;
      }
      await telemetry.configure(config);
      status = config.enabled
          ? 'Telemetry enabled for this session. Apply to save.'
          : 'Telemetry disabled for this session. Apply to save.';
    } on FormatException catch (error) {
      status = error.message;
    } catch (error, stack) {
      telemetry.failure('telemetry.settings.apply', error, stack);
      status = 'Could not enable telemetry. Check the configuration.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> save(TelemetryConfig config) async {
    if (busy) return false;
    _configurationRevision++;
    busy = true;
    status = null;
    _notify();
    try {
      config.validate();
      if (telemetry.activeOperations != 0) {
        status = 'Wait for active operations to finish.';
        return false;
      }
      await telemetry.configure(config);
      try {
        await store.write(config);
      } catch (error, stack) {
        telemetry.failure('telemetry.settings.save', error, stack);
        status = config.enabled
            ? 'Telemetry is enabled for this session, but settings could not be saved. Check device and secure storage.'
            : 'Telemetry is disabled for this session, but settings could not be saved. Check device and secure storage.';
        return false;
      }
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
