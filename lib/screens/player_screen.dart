import 'package:flutter/material.dart';

import '../models/content_item.dart';
import '../services/playback/playback_adapter.dart';
import '../widgets/app_scope.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.item});

  final ContentItem item;

  String _statusLabel(String status) {
    return switch (status) {
      'idle' => 'Idle',
      'loading' => 'Loading stream',
      'playing' => 'Playing',
      'paused' => 'Paused',
      'stopped' => 'Stopped',
      'error' => 'Playback error',
      _ => status,
    };
  }

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.playerControllerOf(context);
    final navigation = AppScope.navigationControllerOf(context);
    final capabilities = c.playbackAdapter.capabilities;
    return Scaffold(
      appBar: AppBar(title: const Text('Player')),
      body: StreamBuilder(
        initialData: c.playbackAdapter.state,
        stream: c.playbackAdapter.states,
        builder: (context, snapshot) {
          final state = snapshot.data ?? c.playbackAdapter.state;
          final activeItem = state.item ?? item;
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.playbackAdapter.buildVideoView()
                        case final videoView?) ...[
                      Center(child: videoView),
                    ] else ...[
                      const Center(child: Icon(Icons.ondemand_video, size: 96)),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      _statusLabel(state.status.name),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(activeItem.title),
                    const SizedBox(height: 8),
                    Text(activeItem.group),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          label: Text(
                            capabilities.supportsLiveStreams
                                ? 'Live stream supported'
                                : 'Live stream unsupported',
                          ),
                        ),
                        Chip(
                          label: Text(
                            capabilities.supportsDrm
                                ? 'DRM supported'
                                : 'DRM unsupported',
                          ),
                        ),
                        Chip(
                          label: Text(
                            state.isBuffering ? 'Buffering' : 'Not buffering',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Position: ${_formatDuration(state.position)}'),
                    Text(
                      'Duration: ${state.duration == null ? 'Unknown' : _formatDuration(state.duration!)}',
                    ),
                    Text(
                      'Startup latency: ${state.startupLatency == null ? 'Pending' : '${state.startupLatency!.inMilliseconds} ms'}',
                    ),
                    Text(
                      'Load started: ${state.loadStartedAt?.toIso8601String() ?? 'N/A'}',
                    ),
                    Text(
                      'Playback started: ${state.playbackStartedAt?.toIso8601String() ?? 'N/A'}',
                    ),
                    if (state.message case final message?) ...[
                      const SizedBox(height: 16),
                      Text(
                        message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (capabilities.supportsPause)
                          ElevatedButton(
                            onPressed: () {
                              if (state.status == PlaybackStatus.playing) {
                                c.playbackAdapter.pause();
                              } else {
                                c.playbackAdapter.play();
                              }
                            },
                            child: Text(
                              state.status == PlaybackStatus.playing
                                  ? 'Pause'
                                  : 'Play',
                            ),
                          ),
                        if (capabilities.supportsSeek) ...[
                          OutlinedButton(
                            onPressed: () {
                              final target =
                                  state.position > const Duration(seconds: 10)
                                  ? state.position - const Duration(seconds: 10)
                                  : Duration.zero;
                              c.playbackAdapter.seek(target);
                            },
                            child: const Text('Seek -10s'),
                          ),
                          OutlinedButton(
                            onPressed: () {
                              c.playbackAdapter.seek(
                                state.position + const Duration(seconds: 10),
                              );
                            },
                            child: const Text('Seek +10s'),
                          ),
                        ],
                        if (capabilities.supportsVolume) ...[
                          OutlinedButton(
                            onPressed: () => c.playbackAdapter.setVolume(25),
                            child: const Text('Volume 25%'),
                          ),
                          OutlinedButton(
                            onPressed: () => c.playbackAdapter.setVolume(100),
                            child: const Text('Volume 100%'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: navigation.pop,
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
