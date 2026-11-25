import 'package:flutter/material.dart';

import '../../../services/playback/playback_contract.dart';
import '../../../ui/theme/player_theme.dart';
import '../player_layout.dart';

class PlayerErrorPanel extends StatelessWidget {
  const PlayerErrorPanel({
    super.key,
    required this.errorKind,
    required this.onBack,
    required this.onRetry,
  });

  final PlaybackErrorKind? errorKind;
  final VoidCallback onBack;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: PlayerTheme.of(context).errorScrim,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: PlayerLayout.errorMaxWidth),
        child: Padding(
          padding: PlayerLayout.errorPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: PlayerTheme.of(context).foreground,
                size: 48,
              ),
              const SizedBox(height: 16),
              Text(
                _playbackErrorMessage(errorKind),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: PlayerTheme.of(context).foreground,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );

  String _playbackErrorMessage(PlaybackErrorKind? kind) => switch (kind) {
    PlaybackErrorKind.configuration =>
      'This webOS package must be rebuilt using the supported build script.',
    PlaybackErrorKind.accessDenied => 'Playback failed: access denied.',
    PlaybackErrorKind.notFound => 'Playback failed: stream not found.',
    PlaybackErrorKind.timeout => 'Playback failed: stream timeout.',
    PlaybackErrorKind.unsupportedFormat =>
      'Playback failed: unsupported media format.',
    PlaybackErrorKind.network => 'Playback failed: network unavailable.',
    PlaybackErrorKind.unknown || null => 'Playback failed. Try another stream.',
  };
}
