import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_tokens.dart';
import 'media_artwork.dart';

enum MediaTilePresentation { standard, poster }

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
    this.listView = false,
    this.showListArtwork = false,
    this.episodeRow = false,
    this.keepAliveWhileFocused = false,
    this.onFocusChanged,
    this.presentation = MediaTilePresentation.standard,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? imageUrl;
  final VoidCallback onActivate;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool selected;
  final bool listView;
  final bool showListArtwork;
  final bool episodeRow;
  final bool keepAliveWhileFocused;
  final ValueChanged<bool>? onFocusChanged;
  final MediaTilePresentation presentation;

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile>
    with AutomaticKeepAliveClientMixin {
  bool _showFocus = false;
  bool _focused = false;
  @override
  bool get wantKeepAlive => widget.keepAliveWhileFocused && _focused;
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
    if (oldWidget.keepAliveWhileFocused != widget.keepAliveWhileFocused) {
      updateKeepAlive();
    }
    if (oldWidget.focusNode != widget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _setFocusNode(widget.focusNode);
    }
    if (!oldWidget.autofocus && widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true ||
            Navigator.of(context, rootNavigator: true).canPop()) {
          return;
        }
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
    super.build(context);
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
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        updateKeepAlive();
        widget.onFocusChanged?.call(focused);
      },
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
                    child: widget.listView
                        ? Row(
                            children: [
                              if (widget.showListArtwork || widget.episodeRow)
                                SizedBox(
                                  width: widget.episodeRow ? 80 : 48,
                                  height: 48,
                                  child: MediaArtwork(
                                    imageUrl: imageUrl,
                                    fallbackIcon:
                                        widget.icon ?? Icons.ondemand_video,
                                    decodeWidth: AppTokens.artworkDecodeWidth,
                                    decodeHeight: AppTokens.artworkDecodeHeight,
                                    resizePolicy: widget.episodeRow
                                        ? ResizeImagePolicy.fit
                                        : ResizeImagePolicy.exact,
                                  ),
                                )
                              else
                                fallback,
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.title,
                                      maxLines: widget.episodeRow ? 2 : 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium,
                                    ),
                                    if (subtitle != null && subtitle.isNotEmpty)
                                      Text(
                                        subtitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : widget.presentation == MediaTilePresentation.poster
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    AppTokens.progressRadius,
                                  ),
                                  child: ColoredBox(
                                    color: theme.colorScheme.surfaceContainer,
                                    child: SizedBox.expand(
                                      child: MediaArtwork(
                                        imageUrl: imageUrl,
                                        fallbackIcon:
                                            widget.icon ?? Icons.ondemand_video,
                                        decodeWidth: 320,
                                        decodeHeight: 480,
                                        resizePolicy: ResizeImagePolicy.fit,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height:
                                    MediaQuery.textScalerOf(context).scale(
                                      theme.textTheme.titleMedium?.fontSize ??
                                          16,
                                    ) *
                                    (theme.textTheme.titleMedium?.height ??
                                        1.25) *
                                    2,
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
                                const SizedBox(height: 4),
                                SizedBox(
                                  height:
                                      MediaQuery.textScalerOf(context).scale(
                                        theme.textTheme.bodySmall?.fontSize ??
                                            12,
                                      ) *
                                      (theme.textTheme.bodySmall?.height ??
                                          1.33) *
                                      2,
                                  child: Text(
                                    subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: widget.selected
                                          ? theme
                                                .colorScheme
                                                .onSecondaryContainer
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          )
                        : Column(
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
                                          child: MediaArtwork(
                                            imageUrl: imageUrl,
                                            fallbackIcon:
                                                widget.icon ??
                                                Icons.ondemand_video,
                                            decodeWidth:
                                                AppTokens.artworkDecodeWidth,
                                            decodeHeight:
                                                AppTokens.artworkDecodeHeight,
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
                                          ? theme
                                                .colorScheme
                                                .onSecondaryContainer
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
