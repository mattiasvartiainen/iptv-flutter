import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import '../../models/content_item.dart';
import 'playback_contract.dart';
import 'playback_http_headers.dart';
import 'playback_load.dart';
import 'playback_video_surface.dart';

class VideoPlayerPlaybackAdapter implements PlaybackAdapter {
  final _stateController = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState.idle();
  VideoPlayerController? _controller;
  Widget? _videoView;
  bool _disposed = false;
  PlaybackLoad? _load;
  Future<void>? _disposeFuture;
  Future<void> _controllerDisposal = Future<void>.value();

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
    if (_disposed || controller == null || !controller.value.isInitialized) {
      return null;
    }
    return _videoView ??= PlaybackVideoSurface<VideoPlayerValue>(
      values: controller,
      aspectRatio: (value) =>
          value.size.width > 0 && value.size.height > 0 ? value.aspectRatio : 0,
      child: VideoPlayer(controller),
    );
  }

  @override
  Future<void> load(ContentItem item) async {
    if (_disposed) return;
    _load?.cancel();
    final load = _load = PlaybackLoad();
    await _disposeController();
    if (_disposed || load.isCancelled) return;
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
      httpHeaders: playbackHttpHeaders,
    );
    _controller = controller;
    controller.addListener(_handleControllerUpdate);

    try {
      await load.waitFor(controller.initialize());
      if (_disposed ||
          load.isCancelled ||
          !identical(_controller, controller)) {
        return;
      }
      await controller.play();
      if (_disposed ||
          load.isCancelled ||
          !identical(_controller, controller)) {
        return;
      }
      _handleControllerUpdate();
    } catch (error, stack) {
      if (_disposed ||
          load.isCancelled ||
          !identical(_controller, controller)) {
        return;
      }
      if (identical(_controller, controller)) {
        _publish(
          _state.copyWith(
            status: PlaybackStatus.error,
            errorKind: playbackErrorKind(error),
            clearMessage: true,
          ),
        );
      }
      Error.throwWithStackTrace(PlaybackException.from(error), stack);
    }
  }

  @override
  Future<void> play() async {
    if (_controller == null && _state.status == PlaybackStatus.stopped) {
      final item = _state.item;
      if (item != null) {
        await load(item);
        return;
      }
    }
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
    final load = _load;
    load?.cancel();
    final controller = _controller;
    if (controller != null && !controller.value.isInitialized) {
      await _disposeController();
      _publish(_state.copyWith(status: PlaybackStatus.stopped));
      return;
    }
    if (controller == null) {
      _publish(_state.copyWith(status: PlaybackStatus.stopped));
      return;
    }
    await controller.pause();
    if (_disposed || !identical(_controller, controller)) return;
    await controller.seekTo(Duration.zero);
    if (_disposed || !identical(_controller, controller)) return;
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
      throw StateError('No initialized video is loaded.');
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
          errorKind: classifyPlaybackError(value.errorDescription ?? ''),
          clearMessage: true,
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
        mediaInfo: PlaybackMediaInfo(
          width: value.size.width.isFinite && value.size.width > 0
              ? value.size.width.round()
              : null,
          height: value.size.height.isFinite && value.size.height > 0
              ? value.size.height.round()
              : null,
        ),
        volume: value.volume * 100,
        playbackStartedAt: value.isPlaying
            ? (_state.playbackStartedAt ?? DateTime.now())
            : null,
      ),
    );
  }

  void _publish(PlaybackState nextState) {
    if (_disposed) return;
    _state = nextState;
    _stateController.add(nextState);
  }

  Future<void> _disposeController() {
    final controller = _controller;
    _controller = null;
    _videoView = null;
    controller?.removeListener(_handleControllerUpdate);
    if (controller != null) {
      final previous = _controllerDisposal;
      _controllerDisposal = () async {
        try {
          await previous;
        } finally {
          await controller.dispose();
        }
      }();
    }
    return _controllerDisposal;
  }

  @override
  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _disposed = true;
    _load?.cancel();
    return _disposeFuture = _dispose();
  }

  Future<void> _dispose() async {
    try {
      await _disposeController();
    } finally {
      await _stateController.close();
    }
  }
}
