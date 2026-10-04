import 'package:flutter/widgets.dart';

import 'platform_capabilities.dart';

class AppEnvironment extends InheritedWidget {
  const AppEnvironment({
    super.key,
    required this.capabilities,
    required super.child,
  });

  final PlatformCapabilities capabilities;

  static PlatformCapabilities? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppEnvironment>()
      ?.capabilities;

  static PlatformCapabilities of(BuildContext context) {
    final capabilities = maybeOf(context);
    if (capabilities == null) {
      throw FlutterError('AppEnvironment is not available above this context.');
    }
    return capabilities;
  }

  @override
  bool updateShouldNotify(AppEnvironment oldWidget) =>
      oldWidget.capabilities != capabilities;
}
