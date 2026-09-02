import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../models/content_item.dart';
import 'playback_contract.dart';

class WebOsPlaybackAdapter implements PlaybackAdapter {
  final _stateController = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState.idle();
  VideoPlayerController? _controller;
  bool _disposed = false;

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
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio > 0
          ? controller.value.aspectRatio
          : 16 / 9,
      child: VideoPlayer(controller),
    );
  }

  @override
  Future<void> load(ContentItem item) async {
    _disposeController();
    final loadStartedAt = DateTime.now();
    _publish(
      PlaybackState(
        status: PlaybackStatus.loading,
        item: item,
        loadStartedAt: loadStartedAt,
      ),
    );

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(item.streamUrl),
    );
    _controller = controller;
    controller.addListener(_handleControllerUpdate);

    try {
      await controller.initialize();
      if (_disposed || !identical(_controller, controller)) return;
      await controller.play();
      if (_disposed || !identical(_controller, controller)) return;
      _handleControllerUpdate();
    } catch (error) {
      if (identical(_controller, controller)) {
        _publish(
          _state.copyWith(
            status: PlaybackStatus.error,
            message: _mapPlaybackError(error.toString()),
          ),
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    final controller = _requireController();
    await controller.play();
    _handleControllerUpdate();
  }

  @override
  Future<void> pause() async {
    final controller = _requireController();
    await controller.pause();
    _handleControllerUpdate();
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    if (controller == null) {
      _publish(_state.copyWith(status: PlaybackStatus.stopped));
      return;
    }
    await controller.pause();
    await controller.seekTo(Duration.zero);
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
    final controller = _requireController();
    final target = position < Duration.zero ? Duration.zero : position;
    await controller.seekTo(target);
    _publish(_state.copyWith(position: target));
  }

  @override
  Future<void> setVolume(double volume) async {
    final normalized = volume.clamp(0.0, 100.0).toDouble() / 100.0;
    await _requireController().setVolume(normalized);
  }

  VideoPlayerController _requireController() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('No initialized webOS video is loaded.');
    }
    return controller;
  }

  void _handleControllerUpdate() {
    final controller = _controller;
    if (_disposed || controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      _publish(
        _state.copyWith(
          status: PlaybackStatus.error,
          message: _mapPlaybackError(value.errorDescription ?? ''),
        ),
      );
      return;
    }
    final status = value.isPlaying
        ? PlaybackStatus.playing
        : (_state.status == PlaybackStatus.stopped
              ? PlaybackStatus.stopped
              : PlaybackStatus.paused);
    _publish(
      _state.copyWith(
        status: status,
        position: value.position,
        duration: value.duration == Duration.zero ? null : value.duration,
        clearDuration: value.duration == Duration.zero,
        isBuffering: value.isBuffering,
        playbackStartedAt: value.isPlaying
            ? (_state.playbackStartedAt ?? DateTime.now())
            : null,
      ),
    );
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
    if (text.contains('timeout') || text.contains('timed out')) {
      return 'Playback failed: stream timeout.';
    }
    if (text.contains('unsupported') || text.contains('codec')) {
      return 'Playback failed: unsupported media format.';
    }
    return 'Playback failed. Try another stream.';
  }

  void _publish(PlaybackState nextState) {
    if (_disposed) return;
    _state = nextState;
    _stateController.add(nextState);
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_handleControllerUpdate);
    controller?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _disposeController();
    _stateController.close();
  }
}

typedef WebOsPlaybackAdapterStub = WebOsPlaybackAdapter;
