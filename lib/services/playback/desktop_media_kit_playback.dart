import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/content_item.dart';
import 'playback_contract.dart';

class DesktopMediaKitPlaybackAdapter implements PlaybackAdapter {
  DesktopMediaKitPlaybackAdapter({
    bool disableVideoOutput = false,
    bool enableHardwareAcceleration = true,
  }) : _disableVideoOutput = disableVideoOutput,
       _enableHardwareAcceleration = enableHardwareAcceleration {
    _playingSubscription = _player.stream.playing.listen((isPlaying) {
      if (_state.item == null) return;
      if (isPlaying) {
        _publish(_state.copyWith(status: PlaybackStatus.playing));
      } else if (_state.status == PlaybackStatus.playing) {
        _publish(_state.copyWith(status: PlaybackStatus.paused));
      }
    });

    _errorSubscription = _player.stream.error.listen((errorText) {
      _publish(
        _state.copyWith(
          status: PlaybackStatus.error,
          message: _mapPlaybackError(errorText),
        ),
      );
    });

    _completedSubscription = _player.stream.completed.listen((isCompleted) {
      if (!isCompleted) return;
      _publish(_state.copyWith(status: PlaybackStatus.stopped));
    });

    _bufferingSubscription = _player.stream.buffering.listen((isBuffering) {
      _publish(_state.copyWith(isBuffering: isBuffering));
    });

    _positionSubscription = _player.stream.position.listen((position) {
      _publish(_state.copyWith(position: position));
    });

    _durationSubscription = _player.stream.duration.listen((duration) {
      _publish(
        _state.copyWith(
          duration: duration == Duration.zero ? null : duration,
          clearDuration: duration == Duration.zero,
        ),
      );
    });
  }

  final bool _disableVideoOutput;
  final bool _enableHardwareAcceleration;

  final _player = Player();
  final _stateController = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState.idle();

  VideoController? _videoController;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;

  @override
  PlaybackCapabilities get capabilities => const PlaybackCapabilities(
    supportsSeek: true,
    supportsPause: true,
    supportsVolume: true,
    supportsDrm: false,
    supportsLiveStreams: true,
  );

  @override
  PlaybackState get state => _state;

  @override
  Stream<PlaybackState> get states => _stateController.stream;

  @override
  Widget? buildVideoView() {
    final controller = _videoController;
    if (_disableVideoOutput || controller == null) return null;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Video(controller: controller),
    );
  }

  @override
  Future<void> load(ContentItem item) async {
    if (!_disableVideoOutput) {
      _videoController ??= VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: _enableHardwareAcceleration,
        ),
      );
    }

    final loadStartedAt = DateTime.now();
    _publish(
      PlaybackState(
        status: PlaybackStatus.loading,
        item: item,
        loadStartedAt: loadStartedAt,
        position: Duration.zero,
      ),
    );

    try {
      await _player.open(
        Media(
          item.streamUrl,
          httpHeaders: const {
            'Accept': 'application/x-mpegURL,application/vnd.apple.mpegurl,*/*',
            'User-Agent': 'IPTV-Flutter/0.1',
          },
        ),
      );
    } catch (error) {
      _publish(
        _state.copyWith(
          status: PlaybackStatus.error,
          message: _mapPlaybackError(error.toString()),
        ),
      );
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    if (_state.item == null) return;
    await _player.play();
    _publish(
      _state.copyWith(
        status: PlaybackStatus.playing,
        playbackStartedAt: _state.playbackStartedAt ?? DateTime.now(),
      ),
    );
  }

  @override
  Future<void> pause() async {
    if (_state.item == null) return;
    await _player.pause();
    _publish(_state.copyWith(status: PlaybackStatus.paused));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _publish(
      _state.copyWith(
        status: PlaybackStatus.stopped,
        position: Duration.zero,
        isBuffering: false,
      ),
    );
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _publish(_state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {
    final clamped = volume.clamp(0.0, 100.0).toDouble();
    await _player.setVolume(clamped);
  }

  String _mapPlaybackError(String raw) {
    final text = raw.toLowerCase();
    if (text.contains('401') ||
        text.contains('403') ||
        text.contains('forbidden')) {
      return 'Playback failed: access denied.';
    }
    if (text.contains('404') || text.contains('not found')) {
      return 'Playback failed: stream not found.';
    }
    if (text.contains('timed out') || text.contains('timeout')) {
      return 'Playback failed: stream timeout.';
    }
    if (text.contains('unsupported') ||
        text.contains('codec') ||
        text.contains('demux')) {
      return 'Playback failed: unsupported media format.';
    }
    if (text.contains('network') ||
        text.contains('connection') ||
        text.contains('dns')) {
      return 'Playback failed: network unavailable.';
    }
    return 'Playback failed. Try another stream.';
  }

  void _publish(PlaybackState nextState) {
    if (nextState.status == PlaybackStatus.playing &&
        nextState.playbackStartedAt == null &&
        nextState.loadStartedAt != null) {
      nextState = nextState.copyWith(playbackStartedAt: DateTime.now());
    }
    _state = nextState;
    debugPrint(
      '[Playback] status=${nextState.status.name} buffering=${nextState.isBuffering} position=${nextState.position.inMilliseconds}ms duration=${nextState.duration?.inMilliseconds ?? -1}ms startup=${nextState.startupLatency?.inMilliseconds ?? -1}ms title=${nextState.item?.title ?? '-'} message=${nextState.message ?? '-'}',
    );
    _stateController.add(nextState);
  }

  @override
  void dispose() {
    _playingSubscription?.cancel();
    _errorSubscription?.cancel();
    _completedSubscription?.cancel();
    _bufferingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    _stateController.close();
  }
}
