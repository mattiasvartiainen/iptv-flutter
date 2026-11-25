import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_shortcuts.dart';
import '../../models/content_item.dart';
import '../../services/playback/playback_contract.dart';
import '../../ui/theme/player_theme.dart';
import '../../ui/widgets/app_scope.dart';
import 'player_controller.dart';
import 'widgets/player_controls.dart';
import 'widgets/player_error_panel.dart';
import 'widgets/player_track_dialog.dart';

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
    final playerTheme = PlayerTheme.of(context);
    final videoBackground = player.capabilities.usesPlatformVideoPlane
        ? Colors.transparent
        : playerTheme.videoBackground;
    return Scaffold(
      backgroundColor: videoBackground,
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
                        color: videoBackground,
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
                        Center(
                          child: CircularProgressIndicator(
                            color: playerTheme.foreground,
                          ),
                        ),
                      if (playback.status == PlaybackStatus.error)
                        PlayerErrorPanel(
                          errorKind: playback.errorKind,
                          onBack: () =>
                              AppScope.navigationControllerOf(context).pop(),
                          onRetry: () => unawaited(player.open(widget.item)),
                        ),
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
                                  : playerTheme.controlsFadeDuration,
                              child: Focus(
                                onFocusChange: _handleControlFocus,
                                child: ListenableBuilder(
                                  listenable: player,
                                  builder: (_, _) => PlayerControls(
                                    item: widget.item,
                                    player: player,
                                    playback: playback,
                                    showDiagnostics:
                                        preferences.verboseRefreshInfo,
                                    playFocus: _playFocus,
                                    seekFocus: _seekFocus,
                                    seekPreview: _seekPreview,
                                    onSeekStart: (value) {
                                      _hideTimer?.cancel();
                                      setState(() => _seekPreview = value);
                                    },
                                    onSeekChanged: (value) =>
                                        setState(() => _seekPreview = value),
                                    onSeekEnd: (value) {
                                      setState(() => _seekPreview = null);
                                      unawaited(
                                        player.seekTo(
                                          Duration(milliseconds: value.round()),
                                        ),
                                      );
                                      _scheduleHide();
                                    },
                                    onBack: () =>
                                        AppScope.navigationControllerOf(
                                          context,
                                        ).pop(),
                                    onChooseSubtitles: () => unawaited(
                                      _chooseTrack(player, subtitle: true),
                                    ),
                                    onChooseAudio: () => unawaited(
                                      _chooseTrack(player, subtitle: false),
                                    ),
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
          builder: (_, state, _) => PlayerTrackDialog(
            mediaInfo: state.mediaInfo,
            subtitle: subtitle,
            onSelected: (id) => Navigator.of(dialogContext).pop(id),
            onCancel: () => Navigator.of(dialogContext).pop(),
          ),
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
}
