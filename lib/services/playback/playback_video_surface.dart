import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A stable native video child with aspect ratio driven by controller values.
///
/// Invalid or unavailable dimensions use 16:9 until the native value changes.
class PlaybackVideoSurface<T> extends StatelessWidget {
  const PlaybackVideoSurface({
    super.key,
    required this.values,
    required this.aspectRatio,
    required this.child,
  });

  final ValueListenable<T> values;
  final double Function(T) aspectRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<T>(
    valueListenable: values,
    child: child,
    builder: (_, value, child) {
      final ratio = aspectRatio(value);
      return AspectRatio(
        aspectRatio: ratio.isFinite && ratio > 0 ? ratio : 16 / 9,
        child: child,
      );
    },
  );
}
