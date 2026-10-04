import 'package:flutter/foundation.dart';

import 'build_flags.dart';

enum AppPlatform { android, windows, linux, webos, other }

AppPlatform detectAppPlatform() => resolveAppPlatform(
  isWebOsBuild: isWebOsBuild,
  isWeb: kIsWeb,
  targetPlatform: defaultTargetPlatform,
);

@visibleForTesting
AppPlatform resolveAppPlatform({
  required bool isWebOsBuild,
  required bool isWeb,
  required TargetPlatform targetPlatform,
}) {
  if (isWebOsBuild) return AppPlatform.webos;
  if (isWeb) return AppPlatform.other;
  return switch (targetPlatform) {
    TargetPlatform.android => AppPlatform.android,
    TargetPlatform.windows => AppPlatform.windows,
    TargetPlatform.linux => AppPlatform.linux,
    _ => AppPlatform.other,
  };
}
