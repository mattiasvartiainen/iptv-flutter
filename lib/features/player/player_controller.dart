import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app/navigation/app_route.dart';
import '../../app/navigation/navigation_controller.dart';
import '../../models/content_item.dart';
import '../../services/logging/app_logger.dart';
import '../../services/playback/playback_adapter.dart';
import '../../services/playback/playback_contract.dart';
import '../../services/security/url_redaction.dart';

class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.playbackAdapter,
    required this.navigationController,
    AppLogger logger = const DebugAppLogger(),
  }) : _logger = logger,
       _playbackState = ValueNotifier<PlaybackState>(playbackAdapter.state) {
    _observedRoute = navigationController.currentRoute;
    navigationController.addListener(_handleNavigationChanged);
    _statesSubscription = playbackAdapter.states.listen(_handlePlaybackState);
  }

  static const ContentItem playbackSpikeItem = ContentItem(
    id: 'playback-spike-live-hls',
    title: 'Playback Spike - Live HLS',
    type: ContentType.live,
    streamUrl: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    group: 'Playback Spike',
    description:
        'Public HLS stream used to validate player integration before full catalog wiring.',
  );

  final PlaybackAdapter playbackAdapter;
  final NavigationController navigationController;
  final AppLogger _logger;
  final ValueNotifier<PlaybackState> _playbackState;
  late AppRoute _observedRoute;
  late final StreamSubscription<PlaybackState> _statesSubscription;
  int _playbackLoadGeneration = 0;
  bool _disposed = false;
  Object? _backHandlerOwner;
  bool Function()? _backRequestHandler;

  ValueListenable<PlaybackState> get playbackState => _playbackState;

  PlaybackCapabilities get capabilities => playbackAdapter.capabilities;

  Widget? get videoView => playbackAdapter.buildVideoView();

  void registerBackRequestHandler(Object owner, bool Function() handler) {
    _backHandlerOwner = owner;
    _backRequestHandler = handler;
  }

  void unregisterBackRequestHandler(Object owner) {
    if (!identical(_backHandlerOwner, owner)) return;
    _backHandlerOwner = null;
    _backRequestHandler = null;
  }

  bool handleBackRequest() => _backRequestHandler?.call() ?? false;

  Future<void> openPlayer(ContentItem item) {
    navigationController.push(PlayerRoute(item));
    return open(item);
  }

  Future<void> openPlaybackSpike() => openPlayer(playbackSpikeItem);

  Future<void> open(ContentItem item) async {
    final generation = ++_playbackLoadGeneration;
    try {
      await playbackAdapter.load(item);
      _handlePlaybackState(playbackAdapter.state);
      final currentRoute = navigationController.currentRoute;
      if (generation != _playbackLoadGeneration ||
          currentRoute is! PlayerRoute ||
          currentRoute.item.id != item.id) {
        await _stopPlayback();
      }
    } catch (error, stackTrace) {
      _recordFailure('playback_load_failed', error, stackTrace);
    }
  }

  Future<void> togglePlayPause() async {
    if (!capabilities.supportsPause) return;
    if (_playbackState.value.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (!capabilities.supportsPause) return;
    await _runCommand('playback_play_failed', playbackAdapter.play);
  }

  Future<void> pause() async {
    if (!capabilities.supportsPause) return;
    await _runCommand('playback_pause_failed', playbackAdapter.pause);
  }

  Future<void> seekBy(Duration offset) async {
    if (!capabilities.supportsSeek) return;
    var target = _playbackState.value.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    final duration = _playbackState.value.duration;
    if (duration != null && target > duration) target = duration;
    await _runCommand(
      'playback_seek_failed',
      () => playbackAdapter.seek(target),
    );
  }

  Future<void> setVolume(double volume) async {
    if (!capabilities.supportsVolume) return;
    await _runCommand(
      'playback_volume_failed',
      () => playbackAdapter.setVolume(volume),
    );
  }

  Future<void> close() async {
    _playbackLoadGeneration++;
    await _stopPlayback();
  }

  void _handlePlaybackState(PlaybackState state) {
    if (!_disposed) _playbackState.value = state;
  }

  Future<void> _runCommand(
    String event,
    Future<void> Function() command,
  ) async {
    if (_disposed) return;
    try {
      await command();
      _handlePlaybackState(playbackAdapter.state);
    } catch (error, stackTrace) {
      _recordFailure(event, error, stackTrace);
    }
  }

  void _recordFailure(String event, Object error, StackTrace stackTrace) {
    _logger.error(
      event,
      error: redactSensitiveText(error.toString()),
      stackTrace: StackTrace.fromString(
        redactSensitiveText(stackTrace.toString()),
      ),
    );
    if (!_disposed) {
      _playbackState.value = _playbackState.value.copyWith(
        status: PlaybackStatus.error,
        message: _playbackState.value.message ?? 'Playback failed.',
      );
    }
  }

  void _handleNavigationChanged() {
    final route = navigationController.currentRoute;
    if (_observedRoute is PlayerRoute && !identical(_observedRoute, route)) {
      unawaited(close());
    }
    _observedRoute = route;
  }

  Future<void> _stopPlayback() async {
    try {
      await playbackAdapter.stop();
      _handlePlaybackState(playbackAdapter.state);
    } catch (error, stackTrace) {
      _recordFailure('playback_stop_failed', error, stackTrace);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    navigationController.removeListener(_handleNavigationChanged);
    unawaited(_statesSubscription.cancel());
    playbackAdapter.dispose();
    _playbackState.dispose();
    super.dispose();
  }
}
