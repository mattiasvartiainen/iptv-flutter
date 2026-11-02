import '../logging/app_logger.dart';

abstract class AppTelemetry {
  const AppTelemetry();

  bool get enabled => true;

  Future<T> measure<T>(
    String operation,
    Future<T> Function() action, {
    Map<String, Object?> attributes = const {},
  });

  void event(String name, {Map<String, Object?> attributes = const {}});

  void failure(String name, Object error, StackTrace stackTrace);
}

class NoopAppTelemetry extends AppTelemetry {
  const NoopAppTelemetry();

  @override
  bool get enabled => false;

  @override
  Future<T> measure<T>(
    String operation,
    Future<T> Function() action, {
    Map<String, Object?> attributes = const {},
  }) => action();

  @override
  void event(String name, {Map<String, Object?> attributes = const {}}) {}

  @override
  void failure(String name, Object error, StackTrace stackTrace) {}
}

class TelemetryAppLogger implements AppLogger {
  const TelemetryAppLogger(this.local, this.telemetry);

  final AppLogger local;
  final AppTelemetry telemetry;

  @override
  void info(String message, {Map<String, Object?> context = const {}}) {
    local.info(message, context: context);
    telemetry.event(message, attributes: context);
  }

  @override
  void warning(String message, {Map<String, Object?> context = const {}}) {
    local.warning(message, context: context);
    telemetry.event(message, attributes: {...context, 'severity': 'warning'});
  }

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {
    local.error(
      message,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );
    telemetry.event(message, attributes: {...context, 'severity': 'error'});
    if (error != null) {
      telemetry.failure(message, error, stackTrace ?? StackTrace.empty);
    }
  }
}
