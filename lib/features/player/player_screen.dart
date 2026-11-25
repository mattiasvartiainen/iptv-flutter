import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shortcuts.dart';
import '../../models/content_item.dart';
import '../../services/playback/playback_contract.dart';
import '../../services/playback/playback_labels.dart';
import '../../ui/formatting.dart';
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
  final _playFocus = FocusNode(debugLabel: 'Player play pause');
  final _surfaceFocus = FocusNode(debugLabel: 'Player surface');
  final _seekFocus = FocusNode(debugLabel: 'Player seek');
  double? _seekPreview;
  bool _chooserOpen = false;
  PlaybackStatus? _lastStatus;

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
    _playerController?.playbackState.removeListener(_playbackChanged);
    _playerController?.unregisterBackRequestHandler(this);
    _playerController = player;
    player.playbackState.addListener(_playbackChanged);
    _lastStatus = player.playbackState.value.status;
    _scheduleHide();
    player.registerBackRequestHandler(this, () {
      if (!_controlsVisible) return false;
      _hideControls();
      return true;
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playerController?.playbackState.removeListener(_playbackChanged);
    _playerController?.unregisterBackRequestHandler(this);
    _playFocus.dispose();
    _surfaceFocus.dispose();
    _seekFocus.dispose();
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
      _surfaceFocus.requestFocus();
      setState(() => _controlsVisible = false);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!mounted ||
        !_controlsVisible ||
        _controlHasFocus ||
        _chooserOpen ||
        _seekPreview != null ||
        _playerController?.playbackState.value.status !=
            PlaybackStatus.playing ||
        _accessibleNavigation) {
      return;
    }

    _hideTimer = Timer(_controlsHideDelay, _hideControls);
  }

  void _playbackChanged() {
    final status = _playerController?.playbackState.value.status;
    if (status == _lastStatus) return;
    _lastStatus = status;
    if (status == PlaybackStatus.paused || status == PlaybackStatus.error) {
      _showControls();
    } else {
      _scheduleHide();
    }
  }

  void _revealForRemote() {
    _showControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_chooserOpen) _playFocus.requestFocus();
    });
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
      backgroundColor: player.capabilities.usesPlatformVideoPlane
          ? Colors.transparent
          : Colors.black,
      body: MouseRegion(
        onHover: (_) => _showControls(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showControls,
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.space): PlayPauseIntent(),
            },
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
                focusNode: _surfaceFocus,
                autofocus: true,
                onKeyEvent: (_, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.gameButtonA) &&
                      (!_controlsVisible || _surfaceFocus.hasPrimaryFocus)) {
                    _revealForRemote();
                    return KeyEventResult.handled;
                  }
                  if (event is KeyDownEvent &&
                      !_controlsVisible &&
                      const [
                        LogicalKeyboardKey.arrowUp,
                        LogicalKeyboardKey.arrowDown,
                        LogicalKeyboardKey.arrowLeft,
                        LogicalKeyboardKey.arrowRight,
                      ].contains(event.logicalKey)) {
                    _revealForRemote();
                    return KeyEventResult.handled;
                  }
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
                        color: player.capabilities.usesPlatformVideoPlane
                            ? Colors.transparent
                            : Colors.black,
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
                          child: ExcludeFocus(
                            excluding: !_controlsVisible,
                            child: AnimatedOpacity(
                              opacity: _controlsVisible ? 1 : 0,
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              child: Focus(
                                onFocusChange: _handleControlFocus,
                                child: ListenableBuilder(
                                  listenable: player,
                                  builder: (_, _) => _buildControls(
                                    context,
                                    player,
                                    playback,
                                    showDiagnostics:
                                        preferences.verboseRefreshInfo,
                                  ),
                                ),
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
    final title = safePlaybackLabel(playback.item?.title ?? widget.item.title);
    final duration = playback.duration;
    final canSeek =
        player.capabilities.supportsSeek &&
        duration != null &&
        duration > Duration.zero &&
        widget.item.type != ContentType.live;
    final canPause = player.capabilities.supportsPause;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 500;
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
                              onPressed: () => AppScope.navigationControllerOf(
                                context,
                              ).pop(),
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
                            IconButton(
                              tooltip: player.canFavorite
                                  ? (player.favorite == true
                                        ? 'Remove from favourites'
                                        : 'Add to favourites')
                                  : 'Favourites unavailable for this item',
                              onPressed:
                                  player.canFavorite && !player.favoriteBusy
                                  ? () => unawaited(player.toggleFavorite())
                                  : null,
                              color: Colors.white,
                              icon: player.favoriteBusy
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Icon(
                                      player.favorite == true
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
                              for (final label in _technicalLabels(
                                playback.mediaInfo,
                              ))
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
                        if (player.controlError != null)
                          Text(
                            player.controlError!,
                            style: const TextStyle(color: Colors.amber),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (playback.status != PlaybackStatus.error &&
                playback.status != PlaybackStatus.loading &&
                !playback.isBuffering)
              Center(
                child: IconButton.filled(
                  key: const ValueKey('player-central-play'),
                  focusNode: _playFocus,
                  iconSize: compact ? 36 : 52,
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
                    padding: EdgeInsets.fromLTRB(
                      16,
                      compact ? 4 : 28,
                      16,
                      compact ? 4 : 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showDiagnostics)
                          _buildDiagnostics(context, playback),
                        if (canSeek) ...[
                          Slider(
                            key: const ValueKey('player-seek'),
                            focusNode: _seekFocus,
                            semanticFormatterCallback: (value) =>
                                formatDuration(
                                  Duration(milliseconds: value.round()),
                                ),
                            value:
                                (_seekPreview ??
                                        playback.position.inMilliseconds
                                            .toDouble())
                                    .clamp(
                                      0,
                                      duration.inMilliseconds.toDouble(),
                                    ),
                            max: duration.inMilliseconds.toDouble(),
                            onChangeStart: (value) {
                              _hideTimer?.cancel();
                              setState(() => _seekPreview = value);
                            },
                            onChanged: (value) =>
                                setState(() => _seekPreview = value),
                            onChangeEnd: (value) {
                              setState(() => _seekPreview = null);
                              unawaited(
                                player.seekTo(
                                  Duration(milliseconds: value.round()),
                                ),
                              );
                              _scheduleHide();
                            },
                          ),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: 16,
                            children: [
                              Text(
                                formatDuration(
                                  _seekPreview == null
                                      ? playback.position
                                      : Duration(
                                          milliseconds: _seekPreview!.round(),
                                        ),
                                ),
                                style: const TextStyle(color: Colors.white),
                              ),
                              Text(
                                formatDuration(duration),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ],
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
                              color: Colors.white,
                              onPressed:
                                  player.capabilities.supportsSubtitleTracks
                                  ? () => unawaited(
                                      _chooseTrack(player, subtitle: true),
                                    )
                                  : null,
                              icon: const Icon(Icons.subtitles),
                            ),
                            IconButton(
                              tooltip: player.capabilities.supportsAudioTracks
                                  ? 'Audio tracks'
                                  : 'Audio track selection unavailable',
                              color: Colors.white,
                              onPressed: player.capabilities.supportsAudioTracks
                                  ? () => unawaited(
                                      _chooseTrack(player, subtitle: false),
                                    )
                                  : null,
                              icon: const Icon(Icons.audiotrack),
                            ),
                            if (player.capabilities.supportsVolume)
                              SizedBox(
                                width: 140,
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.volume_up,
                                      color: Colors.white,
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

  Future<void> _chooseTrack(
    PlayerController player, {
    required bool subtitle,
  }) async {
    if (_chooserOpen) return;
    final session = player.playbackSession;
    final restoreFocus = FocusManager.instance.primaryFocus;
    _chooserOpen = true;
    _hideTimer?.cancel();
    try {
      final id = await showDialog<String>(
        context: context,
        builder: (dialogContext) => ValueListenableBuilder<PlaybackState>(
          valueListenable: player.playbackState,
          builder: (_, state, _) {
            final info = state.mediaInfo;
            final tracks = subtitle ? info.subtitleTracks : info.audioTracks;
            final selected = subtitle
                ? info.selectedSubtitleId
                : info.selectedAudioId;
            return AlertDialog(
              title: Text(subtitle ? 'Subtitles' : 'Audio tracks'),
              content: SizedBox(
                width: 440,
                height: tracks.isEmpty
                    ? null
                    : (tracks.length *
                              72.0 *
                              MediaQuery.textScalerOf(dialogContext).scale(1))
                          .clamp(
                            0,
                            MediaQuery.sizeOf(dialogContext).height * .45,
                          ),
                child: tracks.isEmpty
                    ? const Text('No tracks available.')
                    : ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.sizeOf(dialogContext).height * .5,
                        ),
                        child: ListView.builder(
                          itemCount: tracks.length,
                          itemBuilder: (_, index) {
                            final track = tracks[index];
                            return ListTile(
                              autofocus:
                                  track.id == selected ||
                                  (selected == null && index == 0),
                              title: Text(track.label),
                              trailing: track.id == selected
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () =>
                                  Navigator.of(dialogContext).pop(track.id),
                            );
                          },
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        ),
      );
      if (id != null &&
          mounted &&
          player.playbackSession == session &&
          ModalRoute.of(context)?.isCurrent == true) {
        await player.selectTrack(id, subtitle: subtitle);
      }
    } finally {
      _chooserOpen = false;
      if (mounted) {
        if (restoreFocus?.context != null) restoreFocus!.requestFocus();
        _showControls();
      }
    }
  }

  Widget _buildDiagnostics(BuildContext context, PlaybackState playback) {
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
                _playbackErrorMessage(playback.errorKind),
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
                    onPressed: () =>
                        AppScope.navigationControllerOf(context).pop(),
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
