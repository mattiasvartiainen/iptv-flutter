import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds only when an equality-comparable selected value changes.
///
/// Select immutable values or records with stable equality. Disabled builders
/// detach their listener and catch up to the latest value when enabled again.
class SelectedValueBuilder<S, T> extends StatefulWidget {
  const SelectedValueBuilder({
    super.key,
    required this.valueListenable,
    required this.select,
    required this.builder,
    this.enabled = true,
  });

  final ValueListenable<S> valueListenable;
  final T Function(S) select;
  final Widget Function(BuildContext, T) builder;
  final bool enabled;

  @override
  State<SelectedValueBuilder<S, T>> createState() =>
      _SelectedValueBuilderState<S, T>();
}

class _SelectedValueBuilderState<S, T>
    extends State<SelectedValueBuilder<S, T>> {
  late T _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.select(widget.valueListenable.value);
    if (widget.enabled) widget.valueListenable.addListener(_changed);
  }

  @override
  void didUpdateWidget(SelectedValueBuilder<S, T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled) oldWidget.valueListenable.removeListener(_changed);
    _selected = widget.select(widget.valueListenable.value);
    if (widget.enabled) widget.valueListenable.addListener(_changed);
  }

  void _changed() {
    final next = widget.select(widget.valueListenable.value);
    if (next == _selected) return;
    setState(() => _selected = next);
  }

  @override
  void dispose() {
    if (widget.enabled) widget.valueListenable.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _selected);
}
