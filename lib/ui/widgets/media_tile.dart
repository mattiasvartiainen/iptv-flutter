import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_tokens.dart';

class MediaTile extends StatefulWidget {
  const MediaTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.imageUrl,
    required this.onActivate,
    this.autofocus = false,
    this.focusNode,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? imageUrl;
  final VoidCallback onActivate;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool selected;

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  bool _showFocus = false;
  bool _focused = false;
  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  @override
  void initState() {
    super.initState();
    _setFocusNode(widget.focusNode);
  }

  void _setFocusNode(FocusNode? focusNode) {
    _ownsFocusNode = focusNode == null;
    _focusNode = focusNode ?? FocusNode();
  }

  @override
  void didUpdateWidget(covariant MediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _setFocusNode(widget.focusNode);
    }
    if (!oldWidget.autofocus && widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final focusedTile = FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<MediaTile>();
        if (focusedTile == null) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final subtitle = widget.subtitle;
    final imageUrl = widget.imageUrl?.trim();
    final fallback = Icon(widget.icon ?? Icons.ondemand_video, size: 24);
    return FocusableActionDetector(
      includeFocusSemantics: false,
      mouseCursor: SystemMouseCursors.click,
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      onFocusChange: (focused) => setState(() => _focused = focused),
      onShowFocusHighlight: (show) => setState(() => _showFocus = show),
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onActivate();
            return null;
          },
        ),
      },
      child: Semantics(
        button: true,
        selected: widget.selected,
        focusable: true,
        focused: _focused,
        label: widget.title,
        value: subtitle,
        onTap: widget.onActivate,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: widget.onActivate,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: AppTokens.remoteTargetSize,
              minHeight: AppTokens.remoteTargetSize,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.tileFocusInset),
              child: AnimatedScale(
                scale: _showFocus && !disableAnimations
                    ? AppTokens.tileFocusScale
                    : 1,
                duration: disableAnimations
                    ? Duration.zero
                    : AppTokens.focusDuration,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.selected
                        ? theme.colorScheme.secondaryContainer
                        : theme.cardTheme.color ??
                              theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                    border: Border.all(
                      color: _showFocus
                          ? AppTokens.focusRing
                          : Colors.transparent,
                      width: AppTokens.focusRingWidth,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppTokens.compactCardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: imageUrl == null || imageUrl.isEmpty
                                ? fallback
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      AppTokens.progressRadius,
                                    ),
                                    child: Image.network(
                                      imageUrl,
                                      width: double.infinity,
                                      fit: BoxFit.contain,
                                      cacheWidth: AppTokens.artworkDecodeWidth,
                                      cacheHeight:
                                          AppTokens.artworkDecodeHeight,
                                      excludeFromSemantics: true,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              fallback,
                                      loadingBuilder:
                                          (context, child, progress) =>
                                              progress == null
                                              ? child
                                              : fallback,
                                    ),
                                  ),
                          ),
                        ),
                        Flexible(
                          flex: 2,
                          child: Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: widget.selected
                                  ? theme.colorScheme.onSecondaryContainer
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (subtitle != null && subtitle.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Flexible(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: widget.selected
                                    ? theme.colorScheme.onSecondaryContainer
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
