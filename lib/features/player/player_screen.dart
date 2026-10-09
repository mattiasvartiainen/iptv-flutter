import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shortcuts.dart';
import '../../models/content_item.dart';
import '../../services/playback/playback_contract.dart';
import '../../ui/widgets/app_scope.dart';
import 'player_controller.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.item});

  final ContentItem item;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const _controlsHideDelay = Duration(seconds: 4);

  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _controlHasFocus = false;
  bool _accessibleNavigation = false;
  PlayerController? _playerController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _accessibleNavigation = MediaQuery.accessibleNavigationOf(context);
    if (_accessibleNavigation) {
      _hideTimer?.cancel();
    } else if (_controlsVisible) {
      _scheduleHide();
    }
    final player = AppScope.playerControllerOf(context);
    if (identical(player, _playerController)) return;
    _playerController?.unregisterBackRequestHandler(this);
    _playerController = player;
    player.registerBackRequestHandler(this, () {
      if (!_controlsVisible) return false;
      _hideControls();
      return true;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playerController?.unregisterBackRequestHandler(this);
    super.dispose();
  }

  void _showControls() {
    if (!_controlsVisible && mounted) {
      setState(() => _controlsVisible = true);
    }
    _scheduleHide();
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (_controlsVisible && mounted) {
      setState(() => _controlsVisible = false);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!mounted ||
        !_controlsVisible ||
        _controlHasFocus ||
        _accessibleNavigation) {
      return;
    }
    _hideTimer = Timer(_controlsHideDelay, _hideControls);
  }

  void _handleBack(PlayerController player) {
    if (player.handleBackRequest()) return;
    AppScope.navigationControllerOf(context).pop();
  }

  void _handleControlFocus(bool focused) {
    _controlHasFocus = focused;
    if (focused) {
      _showControls();
    } else {
      _scheduleHide();
    }
  }

  void _handleMediaKey(PlayerController player, Intent intent) {
    if (intent is! BackIntent) _showControls();
    switch (intent) {
      case PlayPauseIntent():
        unawaited(player.togglePlayPause());
      case PlayIntent():
        unawaited(player.play());
      case PauseIntent():
        unawaited(player.pause());
      case SeekIntent(:final offset):
        unawaited(player.seekBy(offset));
      case ChannelStepIntent():
        break;
      case BackIntent():
        _handleBack(player);
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = AppScope.playerControllerOf(context);
    final preferences = AppScope.preferencesControllerOf(context);
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showControls,
        child: Actions(
          actions: {
            BackIntent: CallbackAction<BackIntent>(
              onInvoke: (intent) {
                _handleMediaKey(player, intent);
                return null;
              },
            ),
            PlayPauseIntent: CallbackAction<PlayPauseIntent>(
              onInvoke: (intent) {
                _handleMediaKey(player, intent);
                return null;
              },
            ),
            PlayIntent: CallbackAction<PlayIntent>(
              onInvoke: (intent) {
                _handleMediaKey(player, intent);
                return null;
              },
            ),
            PauseIntent: CallbackAction<PauseIntent>(
              onInvoke: (intent) {
                _handleMediaKey(player, intent);
                return null;
              },
            ),
            SeekIntent: CallbackAction<SeekIntent>(
              onInvoke: (intent) {
                _handleMediaKey(player, intent);
                return null;
              },
            ),
            ChannelStepIntent: CallbackAction<ChannelStepIntent>(
              onInvoke: (intent) {
                _handleMediaKey(player, intent);
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey != LogicalKeyboardKey.escape &&
                  event.logicalKey != LogicalKeyboardKey.goBack &&
                  event.logicalKey != LogicalKeyboardKey.browserBack) {
                _showControls();
              }
              return KeyEventResult.ignored;
            },
            child: ValueListenableBuilder<PlaybackState>(
              valueListenable: player.playbackState,
              builder: (context, playback, _) => Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child:
                          player.videoView ??
                          Icon(
                            Icons.ondemand_video,
                            size: 72,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  if (playback.status == PlaybackStatus.loading ||
                      playback.isBuffering)
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  if (playback.status == PlaybackStatus.error)
                    _buildErrorPanel(context, player, playback),
                  IgnorePointer(
                    key: const ValueKey<String>('player-controls'),
                    ignoring: !_controlsVisible,
                    child: ExcludeSemantics(
                      excluding: !_controlsVisible,
                      child: AnimatedOpacity(
                        opacity: _controlsVisible ? 1 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: Focus(
                          onFocusChange: _handleControlFocus,
                          child: _buildControls(
                            context,
                            player,
                            playback,
                            showDiagnostics: preferences.verboseRefreshInfo,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(
    BuildContext context,
    PlayerController player,
    PlaybackState playback, {
    required bool showDiagnostics,
  }) {
    final theme = Theme.of(context);
    final title = playback.item?.title ?? widget.item.title;
    final canSeek = player.capabilities.supportsSeek;
    final canPause = player.capabilities.supportsPause;
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: DecoratedBox(
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => _handleBack(player),
                      color: Colors.white,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Text(
                      _statusLabel(playback.status),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showDiagnostics) _buildDiagnostics(context, playback),
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
                                  player.seekBy(const Duration(seconds: -10)),
                                )
                              : null,
                          icon: const Icon(Icons.replay_10),
                        ),
                        IconButton.filled(
                          tooltip: playback.status == PlaybackStatus.playing
                              ? 'Pause'
                              : 'Play',
                          onPressed: canPause
                              ? () => unawaited(player.togglePlayPause())
                              : null,
                          icon: Icon(
                            playback.status == PlaybackStatus.playing
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Forward 10 seconds',
                          onPressed: canSeek
                              ? () => unawaited(
                                  player.seekBy(const Duration(seconds: 10)),
                                )
                              : null,
                          icon: const Icon(Icons.forward_10),
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
  }

  Widget _buildDiagnostics(BuildContext context, PlaybackState playback) {
    final position = _formatDuration(playback.position);
    final duration = playback.duration == null
        ? 'Unknown'
        : _formatDuration(playback.duration!);
    final latency = playback.startupLatency;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '$position / $duration${latency == null ? '' : ' · ${latency.inMilliseconds} ms startup'}',
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Colors.white70),
      ),
    );
  }

  Widget _buildErrorPanel(
    BuildContext context,
    PlayerController player,
    PlaybackState playback,
  ) => ColoredBox(
    color: Colors.black54,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              Text(
                playback.message ?? 'Playback failed.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _handleBack(player),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  FilledButton.icon(
                    onPressed: () => unawaited(player.open(widget.item)),
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

  String _statusLabel(PlaybackStatus status) => switch (status) {
    PlaybackStatus.idle => 'Ready',
    PlaybackStatus.loading => 'Loading stream',
    PlaybackStatus.playing => 'Playing',
    PlaybackStatus.paused => 'Paused',
    PlaybackStatus.stopped => 'Stopped',
    PlaybackStatus.error => 'Playback error',
  };

  String _formatDuration(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}
