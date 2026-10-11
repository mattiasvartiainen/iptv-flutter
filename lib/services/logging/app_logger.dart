import 'package:flutter/foundation.dart';

import '../security/url_redaction.dart';

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
    if (error != null) {
      debugPrint('  error: ${redactSensitiveText(error.toString())}');
    }
    if (stackTrace != null) {
      debugPrint('  stackTrace: ${redactSensitiveText(stackTrace.toString())}');
    }
  }

  String _format(String level, String message, Map<String, Object?> context) {
    final safeMessage = redactSensitiveText(message);
    if (context.isEmpty) return '[$level] $safeMessage';
    final payload = context.entries
        .map((entry) {
          return '${entry.key}=${redactSensitiveText(entry.value.toString())}';
        })
        .join(', ');
    return '[$level] $safeMessage {$payload}';
  }
}
