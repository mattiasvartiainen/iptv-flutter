import 'package:flutter/widgets.dart';

import '../state/app_controller.dart';

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;
  }

  static AppController of(BuildContext context) {
    final controller = maybeOf(context);
    if (controller != null) return controller;
    throw FlutterError.fromParts([
      ErrorSummary('AppScope not found in the widget tree.'),
      ErrorDescription(
        'AppScope.of() was called from a context that is not under AppScope.',
      ),
      ErrorHint(
        'If this happens inside a dialog or overlay, capture the controller from the parent widget and pass it in explicitly instead of calling AppScope.of() inside the route builder.',
      ),
    ]);
  }
}
