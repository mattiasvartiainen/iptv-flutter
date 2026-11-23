import 'package:flutter/material.dart';

import 'app.dart';
import 'app/app_dependencies.dart';
import 'platform/app_platform.dart';
import 'platform/platform_profile.dart';
import 'services/logging/app_logger.dart';
import 'services/logging/global_error_handler.dart';

Future<void> main() async {
  final bootstrapErrorHandler = GlobalErrorHandler(const DebugAppLogger());
  await bootstrapErrorHandler.run(() async {
    WidgetsFlutterBinding.ensureInitialized();
    final profile = platformProfileFor(detectAppPlatform());
    await profile.initialize();
    final dependencies = AppDependencies.create(profile: profile);
    GlobalErrorHandler(dependencies.logger).install();
    runApp(IptvApp(dependencies: dependencies));
  });
}
