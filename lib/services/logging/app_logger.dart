import 'package:flutter/foundation.dart';

abstract interface class AppLogger {
  void info(String message, {Map<String, Object?> context});
  void warning(String message, {Map<String, Object?> context});
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context,
  });
}

class DebugAppLogger implements AppLogger {
  const DebugAppLogger();

  @override
  void info(String message, {Map<String, Object?> context = const {}}) {
    debugPrint(_format('INFO', message, context));
  }

  @override
  void warning(String message, {Map<String, Object?> context = const {}}) {
    debugPrint(_format('WARN', message, context));
  }

  @override
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> context = const {},
  }) {
    debugPrint(_format('ERROR', message, context));
    if (error != null) debugPrint('  error: $error');
    if (stackTrace != null) debugPrint('  stackTrace: $stackTrace');
  }

  String _format(String level, String message, Map<String, Object?> context) {
    if (context.isEmpty) return '[$level] $message';
    final payload = context.entries
        .map((entry) {
          return '${entry.key}=${entry.value}';
        })
        .join(', ');
    return '[$level] $message {$payload}';
  }
}
