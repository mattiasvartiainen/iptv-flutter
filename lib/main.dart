import 'package:flutter/material.dart';

import 'app.dart';
import 'app/app_dependencies.dart';
import 'platform/app_platform.dart';
import 'platform/platform_profile.dart';
import 'services/logging/app_logger.dart';
import 'services/logging/global_error_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profile = platformProfileFor(detectAppPlatform());
  await profile.initialize();
  final dependencies = AppDependencies.create(profile: profile);
  final logger = const DebugAppLogger();
  final errorHandler = GlobalErrorHandler(logger)..install();
  errorHandler.run(() => runApp(IptvApp(dependencies: dependencies)));
}
