import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:video_player_drm/video_player.dart' as lg;

import '../models/content_item.dart';
import '../services/playback/playback_contract.dart';
import '../services/playback/playback_labels.dart';
import '../services/playback/playback_load.dart';

class WebOsPlaybackAdapter implements PlaybackAdapter, PlaybackTrackAdapter {
  WebOsPlaybackAdapter()
    : _blockUnsafePlugin = !const bool.fromEnvironment(
        'IPTV_WEBOS_SAFE_NATIVE_LOGS',
      );

  @visibleForTesting
  WebOsPlaybackAdapter.forTesting() : _blockUnsafePlugin = false;

  final bool _blockUnsafePlugin;
  final _states = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState.idle();
  lg.VideoPlayerController? _controller;
  bool _disposed = false;
  int _loadGeneration = 0;
  PlaybackLoad? _load;
  Future<void>? _disposeFuture;
  Future<void> _controllerDisposal = Future<void>.value();

  @override
  PlaybackCapabilities get capabilities => const PlaybackCapabilities(
    supportsSeek: true,
    supportsPause: true,
    supportsVolume: false,
    supportsDrm: false,
    supportsLiveStreams: true,
    supportsAudioTracks: true,
    supportsSubtitleTracks: true,
    usesPlatformVideoPlane: true,
  );

  @override
  PlaybackState get state => _state;

  @override
  Stream<PlaybackState> get states => _states.stream;

  @override
  Widget? buildVideoView() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: lg.VideoPlayer(controller),
    );
  }

  @override
  Future<void> load(ContentItem item) async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    _load?.cancel();
    final load = _load = PlaybackLoad();
    await _disposeController();
    if (_disposed || load.isCancelled) return;
    _publish(
      PlaybackState(
        status: PlaybackStatus.loading,
        item: item,
        loadStartedAt: DateTime.now(),
      ),
    );
    // Only the supported build wrapper verifies and patches native logging.
    if (_blockUnsafePlugin) {
      _publish(
        _state.copyWith(
          status: PlaybackStatus.error,
          errorKind: PlaybackErrorKind.configuration,
        ),
      );
      throw PlaybackConfigurationError();
    }
    final controller = lg.VideoPlayerController.network(
      Uri.parse(item.streamUrl),
    );
    _controller = controller;
    controller.addListener(_handleUpdate);
    try {
      await load.waitFor(controller.initialize());
      if (!_isCurrent(controller) || generation != _loadGeneration) return;
      await controller.play();
      if (_isCurrent(controller) && generation == _loadGeneration) {
        _handleUpdate();
      }
    } catch (error) {
      if (!_isCurrent(controller) || generation != _loadGeneration) return;
      _publish(
        _state.copyWith(
          status: PlaybackStatus.error,
          errorKind: classifyPlaybackError(error.toString()),
          clearMessage: true,
        ),
      );
      throw StateError('Unable to load video.');
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
    if (_isCurrent(controller)) _handleUpdate();
  }

  @override
  Future<void> pause() async {
    final controller = _requireController();
    await controller.pause();
    if (_isCurrent(controller)) _handleUpdate();
  }

  @override
  Future<void> stop() async {
    ++_loadGeneration;
    _load?.cancel();
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      await controller.pause();
      if (!_isCurrent(controller)) return;
      await controller.seekTo(Duration.zero);
      if (!_isCurrent(controller)) return;
    } else {
      await _disposeController();
    }
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
    if (_isCurrent(controller)) _handleUpdate();
  }

  @override
  Future<void> setVolume(double volume) async {
    throw UnsupportedError('Stream volume is unavailable on webOS.');
  }

  @override
  Future<void> selectAudioTrack(String id) async {
    final controller = _requireController();
    final index = _trackIndex(id, controller.value.audioTracks, 'Audio');
    await controller.selectAudioTrack(index);
    // Audio selection is reported by the plugin's trackSelected event.
  }

  @override
  Future<void> selectSubtitleTrack(String id) async {
    final controller = _requireController();
    if (id == 'off') {
      await controller.setSubtitleEnabled(false);
    } else {
      final index = _trackIndex(
        id,
        controller.value.subtitleTracks,
        'Subtitle',
      );
      await controller.selectSubtitleTrack(index);
      if (!_isCurrent(controller)) return;
      await controller.setSubtitleEnabled(true);
    }
    if (!_isCurrent(controller)) return;
    _handleUpdate();
  }

  int _trackIndex(String id, List<Map<String, dynamic>>? tracks, String type) {
    final index = int.tryParse(id);
    if (index == null ||
        index.toString() != id ||
        index < 0 ||
        index >= (tracks?.length ?? 0)) {
      throw StateError('$type track is no longer available.');
    }
    return index;
  }

  lg.VideoPlayerController _requireController() {
    final controller = _controller;
    if (_disposed || controller == null || !controller.value.isInitialized) {
      throw StateError('No initialized video is loaded.');
    }
    return controller;
  }

  bool _isCurrent(lg.VideoPlayerController controller) =>
      !_disposed && identical(_controller, controller);

  void _handleUpdate() {
    final controller = _controller;
    if (controller == null || _disposed) return;
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
    if (!value.isInitialized) return;
    final size = value.size;
    final audio = _tracks(value.audioTracks, 'Audio');
    final subtitles = _tracks(value.subtitleTracks, 'Subtitle');
    final selectedAudio = value.currentAudioTrack;
    _publish(
      _state.copyWith(
        status: value.isPlaying
            ? PlaybackStatus.playing
            : _state.status == PlaybackStatus.stopped
            ? PlaybackStatus.stopped
            : PlaybackStatus.paused,
        position: value.position,
        duration: value.duration == Duration.zero ? null : value.duration,
        clearDuration: value.duration == Duration.zero,
        isBuffering: value.isBuffering,
        playbackStartedAt: value.isPlaying
            ? (_state.playbackStartedAt ?? DateTime.now())
            : null,
        mediaInfo: PlaybackMediaInfo(
          width: size.width.isFinite && size.width > 0
              ? size.width.toInt()
              : null,
          height: size.height.isFinite && size.height > 0
              ? size.height.toInt()
              : null,
          audioTracks: audio,
          subtitleTracks: subtitles.isEmpty
              ? subtitles
              : [const PlaybackTrack(id: 'off', label: 'Off'), ...subtitles],
          selectedAudioId:
              selectedAudio != null &&
                  selectedAudio >= 0 &&
                  selectedAudio < audio.length
              ? selectedAudio.toString()
              : null,
        ),
      ),
    );
  }

  List<PlaybackTrack> _tracks(List<Map<String, dynamic>>? tracks, String type) {
    if (tracks == null) return const [];
    final uri = Uri.tryParse(_state.item?.streamUrl ?? '');
    final sensitive = <String>[
      if (uri != null) ...uri.userInfo.split(':'),
      if (uri != null) ...uri.pathSegments,
      if (uri != null) ...uri.queryParametersAll.values.expand((v) => v),
    ].where((part) => part.isNotEmpty).map((part) => part.toLowerCase());
    return List.unmodifiable(
      tracks.asMap().entries.map((entry) {
        final language = entry.value['language'];
        // The plugin exposes a language field, not a free-form display title.
        // Restrict it to language tags so URLs and credentials never reach UI.
        final text = language is String ? language.trim() : '';
        final safe =
            RegExp(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(text) &&
                !sensitive.any((part) => text.toLowerCase().contains(part))
            ? safePlaybackLabel(text)
            : '';
        return PlaybackTrack(
          id: '${entry.key}',
          label: safe.isEmpty ? '$type track ${entry.key + 1}' : safe,
        );
      }),
    );
  }

  void _publish(PlaybackState state) {
    if (_disposed) return;
    _state = state;
    _states.add(state);
  }

  Future<void> _disposeController() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_handleUpdate);
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
    ++_loadGeneration;
    _load?.cancel();
    return _disposeFuture = _dispose();
  }

  Future<void> _dispose() async {
    try {
      await _disposeController();
    } finally {
      await _states.close();
    }
  }
}
