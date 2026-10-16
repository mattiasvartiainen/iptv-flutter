import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PlaylistErrorDetails extends StatefulWidget {
  const PlaylistErrorDetails({super.key, required this.diagnostics});

  final String diagnostics;

  @override
  State<PlaylistErrorDetails> createState() => _PlaylistErrorDetailsState();
}

class _PlaylistErrorDetailsState extends State<PlaylistErrorDetails> {
  final ScrollController _scrollController = ScrollController();
  bool _focused = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !_scrollController.hasClients) {
      return KeyEventResult.ignored;
    }
    final offset = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 64.0,
      LogicalKeyboardKey.arrowUp => -64.0,
      LogicalKeyboardKey.pageDown =>
        _scrollController.position.viewportDimension,
      LogicalKeyboardKey.pageUp =>
        -_scrollController.position.viewportDimension,
      _ => null,
    };
    if (offset == null) return KeyEventResult.ignored;
    final target = (_scrollController.offset + offset)
        .clamp(0.0, _scrollController.position.maxScrollExtent)
        .toDouble();
    if (target == _scrollController.offset) return KeyEventResult.ignored;
    _scrollController.jumpTo(target);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    onFocusChange: (focused) => setState(() => _focused = focused),
    onKeyEvent: _handleKey,
    child: Semantics(
      label: 'Error details',
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 240),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: _focused
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.outline,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Text(
              widget.diagnostics,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ),
      ),
    ),
  );
}
