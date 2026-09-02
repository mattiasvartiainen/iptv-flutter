import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'services/logging/app_logger.dart';
import 'services/logging/global_error_handler.dart';
import 'services/playback/playback_adapter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (shouldInitializeMediaKit()) {
    MediaKit.ensureInitialized();
  }

  final logger = const DebugAppLogger();
  final errorHandler = GlobalErrorHandler(logger)..install();
  errorHandler.run(() => runApp(const IptvApp()));
}
