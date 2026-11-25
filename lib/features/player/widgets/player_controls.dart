import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/content_item.dart';
import '../../../services/playback/playback_contract.dart';
import '../../../ui/formatting.dart';
import '../../../ui/theme/player_theme.dart';
import '../player_controller.dart';
import '../player_layout.dart';
import 'player_header.dart';
import 'player_seek_bar.dart';

class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.item,
    required this.player,
    required this.playback,
    required this.showDiagnostics,
    required this.playFocus,
    required this.seekFocus,
    required this.seekPreview,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onBack,
    required this.onChooseSubtitles,
    required this.onChooseAudio,
  });

  final ContentItem item;
  final PlayerController player;
  final PlaybackState playback;
  final bool showDiagnostics;
  final FocusNode playFocus;
  final FocusNode seekFocus;
  final double? seekPreview;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final VoidCallback onBack;
  final VoidCallback onChooseSubtitles;
  final VoidCallback onChooseAudio;

  @override
  Widget build(BuildContext context) {
    final duration = playback.duration;
    final canSeek =
        player.capabilities.supportsSeek &&
        duration != null &&
        duration > Duration.zero &&
        item.type != ContentType.live;
    final canPause = player.capabilities.supportsPause;
    final playerTheme = PlayerTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = PlayerLayout.fromConstraints(constraints);
        return Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: PlayerHeader(
                title: playback.item?.title ?? item.title,
                playback: playback,
                layout: layout,
                canFavorite: player.canFavorite,
                favorite: player.favorite,
                favoriteBusy: player.favoriteBusy,
                controlError: player.controlError,
                onBack: onBack,
                onToggleFavorite: () => unawaited(player.toggleFavorite()),
              ),
            ),
            if (playback.status != PlaybackStatus.error &&
                playback.status != PlaybackStatus.loading &&
                !playback.isBuffering)
              Center(
                child: IconButton.filled(
                  key: const ValueKey('player-central-play'),
                  focusNode: playFocus,
                  iconSize: layout.centralIconSize,
                  tooltip: playback.status == PlaybackStatus.playing
                      ? 'Pause'
                      : 'Play',
                  onPressed:
                      canPause &&
                          playback.status != PlaybackStatus.loading &&
                          playback.status != PlaybackStatus.error
                      ? () => unawaited(player.togglePlayPause())
                      : null,
                  icon: Icon(
                    playback.status == PlaybackStatus.playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: playerTheme.bottomGradient),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: layout.bottomPadding,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showDiagnostics)
                          _PlayerDiagnostics(playback: playback),
                        if (canSeek)
                          PlayerSeekBar(
                            focusNode: seekFocus,
                            position: playback.position,
                            duration: duration,
                            preview: seekPreview,
                            onChangeStart: onSeekStart,
                            onChanged: onSeekChanged,
                            onChangeEnd: onSeekEnd,
                          ),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            IconButton.filledTonal(
                              tooltip: 'Rewind 10 seconds',
                              onPressed: canSeek
                                  ? () => unawaited(
                                      player.seekBy(
                                        const Duration(seconds: -10),
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Icons.replay_10),
                            ),
                            IconButton.filledTonal(
                              tooltip: 'Forward 10 seconds',
                              onPressed: canSeek
                                  ? () => unawaited(
                                      player.seekBy(
                                        const Duration(seconds: 10),
                                      ),
                                    )
                                  : null,
                              icon: const Icon(Icons.forward_10),
                            ),
                            IconButton(
                              tooltip:
                                  player.capabilities.supportsSubtitleTracks
                                  ? 'Subtitles'
                                  : 'Subtitles unavailable',
                              color: playerTheme.foreground,
                              onPressed:
                                  player.capabilities.supportsSubtitleTracks
                                  ? onChooseSubtitles
                                  : null,
                              icon: const Icon(Icons.subtitles),
                            ),
                            IconButton(
                              tooltip: player.capabilities.supportsAudioTracks
                                  ? 'Audio tracks'
                                  : 'Audio track selection unavailable',
                              color: playerTheme.foreground,
                              onPressed: player.capabilities.supportsAudioTracks
                                  ? onChooseAudio
                                  : null,
                              icon: const Icon(Icons.audiotrack),
                            ),
                            if (player.capabilities.supportsVolume)
                              SizedBox(
                                width: PlayerLayout.volumeWidth,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.volume_up,
                                      color: playerTheme.foreground,
                                    ),
                                    Expanded(
                                      child: Slider(
                                        key: const ValueKey('player-volume'),
                                        value: playback.volume.clamp(0, 100),
                                        max: 100,
                                        onChanged: (value) =>
                                            unawaited(player.setVolume(value)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PlayerDiagnostics extends StatelessWidget {
  const _PlayerDiagnostics({required this.playback});

  final PlaybackState playback;

  @override
  Widget build(BuildContext context) {
    final position = formatDuration(playback.position);
    final duration = playback.duration == null
        ? 'Unknown'
        : formatDuration(playback.duration!);
    final latency = playback.startupLatency;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '$position / $duration${latency == null ? '' : ' · ${latency.inMilliseconds} ms startup'}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: PlayerTheme.of(context).secondaryForeground,
        ),
      ),
    );
  }
}
