import 'package:flutter/material.dart';

import '../../../services/playback/playback_contract.dart';
import '../../../services/playback/playback_labels.dart';

class PlayerHeader extends StatelessWidget {
  const PlayerHeader({
    super.key,
    required this.title,
    required this.playback,
    required this.compact,
    required this.canFavorite,
    required this.favorite,
    required this.favoriteBusy,
    required this.controlError,
    required this.onBack,
    required this.onToggleFavorite,
  });

  final String title;
  final PlaybackState playback;
  final bool compact;
  final bool canFavorite;
  final bool? favorite;
  final bool favoriteBusy;
  final String? controlError;
  final VoidCallback onBack;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black87, Colors.transparent],
      ),
    ),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: compact ? 4 : 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    safePlaybackLabel(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.white),
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
                  color: Colors.white,
                  icon: favoriteBusy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
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
                      color: Colors.white70,
                      fontSize: compact ? 12 : null,
                    ),
                  ),
                  for (final label in _technicalLabels(playback.mediaInfo))
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: compact ? 12 : null,
                      ),
                    ),
                ],
              ),
            ),
            if (controlError != null)
              Text(controlError!, style: const TextStyle(color: Colors.amber)),
          ],
        ),
      ),
    ),
  );

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
