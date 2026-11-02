import 'package:flutter/material.dart';

import 'app.dart';
import 'app/app_dependencies.dart';
import 'platform/app_platform.dart';
import 'platform/platform_profile.dart';
import 'services/logging/global_error_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profile = platformProfileFor(detectAppPlatform());
  await profile.initialize();
  final dependencies = AppDependencies.create(profile: profile);
  final errorHandler = GlobalErrorHandler(dependencies.logger)..install();
  errorHandler.run(() => runApp(IptvApp(dependencies: dependencies)));
}
