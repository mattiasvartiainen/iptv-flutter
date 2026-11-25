import 'package:flutter/material.dart';

import '../../../services/playback/playback_contract.dart';
import '../../../services/playback/playback_labels.dart';
import '../../../ui/theme/player_theme.dart';
import '../player_layout.dart';

class PlayerHeader extends StatelessWidget {
  const PlayerHeader({
    super.key,
    required this.title,
    required this.playback,
    required this.layout,
    required this.canFavorite,
    required this.favorite,
    required this.favoriteBusy,
    required this.controlError,
    required this.onBack,
    required this.onToggleFavorite,
  });

  final String title;
  final PlaybackState playback;
  final PlayerLayout layout;
  final bool canFavorite;
  final bool? favorite;
  final bool favoriteBusy;
  final String? controlError;
  final VoidCallback onBack;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final playerTheme = PlayerTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(gradient: playerTheme.headerGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: layout.headerPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: onBack,
                    color: playerTheme.foreground,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      safePlaybackLabel(title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: playerTheme.foreground,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: canFavorite
                        ? (favorite == true
                              ? 'Remove from favourites'
                              : 'Add to favourites')
                        : 'Favourites unavailable for this item',
                    onPressed: canFavorite && !favoriteBusy
                        ? onToggleFavorite
                        : null,
                    color: playerTheme.foreground,
                    icon: favoriteBusy
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: playerTheme.foreground,
                            ),
                          )
                        : Icon(
                            favorite == true
                                ? Icons.favorite
                                : Icons.favorite_border,
                          ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Text(
                      _statusLabel(playback.status),
                      style: TextStyle(
                        color: playerTheme.secondaryForeground,
                        fontSize: layout.technicalFontSize,
                      ),
                    ),
                    for (final label in _technicalLabels(playback.mediaInfo))
                      Text(
                        label,
                        style: TextStyle(
                          color: playerTheme.secondaryForeground,
                          fontSize: layout.technicalFontSize,
                        ),
                      ),
                  ],
                ),
              ),
              if (controlError != null)
                Text(
                  controlError!,
                  style: TextStyle(color: playerTheme.warning),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _technicalLabels(PlaybackMediaInfo info) => [
    if (info.width != null &&
        info.height != null &&
        info.width! > 0 &&
        info.height! > 0)
      '${info.width} x ${info.height}',
    if (info.fps != null && info.fps!.isFinite && info.fps! > 0)
      '${info.fps!.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '')} fps',
    if (info.videoCodec?.isNotEmpty == true) info.videoCodec!,
    if (info.audioCodec?.isNotEmpty == true) info.audioCodec!,
    if (info.channelLayout?.isNotEmpty == true) info.channelLayout!,
  ];

  String _statusLabel(PlaybackStatus status) => switch (status) {
    PlaybackStatus.idle => 'Ready',
    PlaybackStatus.loading => 'Loading stream',
    PlaybackStatus.playing => 'Playing',
    PlaybackStatus.paused => 'Paused',
    PlaybackStatus.stopped => 'Stopped',
    PlaybackStatus.error => 'Playback error',
  };
}
