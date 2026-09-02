import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_logger.dart';

class GlobalErrorHandler {
  GlobalErrorHandler(this._logger);

  final AppLogger _logger;

  void install() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _logger.error(
        'flutter_framework_error',
        error: details.exception,
        stackTrace: details.stack,
        context: {
          'library': details.library,
          'context': details.context?.toDescription(),
        },
      );
    };

    PlatformDispatcher.instance.onError =
        (Object error, StackTrace stackTrace) {
          _logger.error(
            'uncaught_platform_error',
            error: error,
            stackTrace: stackTrace,
          );
          return true;
        };
  }

  void run(void Function() body) {
    runZonedGuarded(body, (Object error, StackTrace stackTrace) {
      _logger.error(
        'uncaught_zone_error',
        error: error,
        stackTrace: stackTrace,
      );
    });
  }
}
