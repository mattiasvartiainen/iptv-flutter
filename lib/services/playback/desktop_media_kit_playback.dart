import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../models/content_item.dart';
import '../logging/app_logger.dart';
import 'playback_contract.dart';
import 'playback_http_headers.dart';
import 'playback_labels.dart';
import 'playback_load.dart';
import 'playback_logging.dart';

class DesktopMediaKitPlaybackAdapter
    implements PlaybackAdapter, PlaybackTrackAdapter {
  DesktopMediaKitPlaybackAdapter({
    bool disableVideoOutput = false,
    bool enableHardwareAcceleration = true,
    AppLogger logger = const DebugAppLogger(),
  }) : this._(
         Player(),
         disableVideoOutput: disableVideoOutput,
         enableHardwareAcceleration: enableHardwareAcceleration,
         logger: logger,
       );

  @visibleForTesting
  DesktopMediaKitPlaybackAdapter.forTesting(Player player)
    : this._(
        player,
        disableVideoOutput: true,
        enableHardwareAcceleration: false,
        logger: const DebugAppLogger(),
      );

  DesktopMediaKitPlaybackAdapter._(
    this._player, {
    required bool disableVideoOutput,
    required bool enableHardwareAcceleration,
    required AppLogger logger,
  }) : _disableVideoOutput = disableVideoOutput,
       _enableHardwareAcceleration = enableHardwareAcceleration,
       _logger = logger {
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
          errorKind: classifyPlaybackError(errorText),
          clearMessage: true,
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
    _infoSubscriptions.addAll([
      _player.stream.tracks.listen((_) => _publishMediaInfo()),
      _player.stream.track.listen((_) => _publishMediaInfo()),
      _player.stream.videoParams.listen((_) => _publishMediaInfo()),
      _player.stream.audioParams.listen((_) => _publishMediaInfo()),
      _player.stream.volume.listen(
        (volume) => _publish(_state.copyWith(volume: volume)),
      ),
    ]);
  }

  final bool _disableVideoOutput;
  final bool _enableHardwareAcceleration;
  final AppLogger _logger;

  final Player _player;
  final _stateController = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState.idle();

  VideoController? _videoController;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<String>? _errorSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  final _infoSubscriptions = <StreamSubscription<dynamic>>[];
  Widget? _videoView;
  PlaybackLoad? _load;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  PlaybackCapabilities get capabilities => const PlaybackCapabilities(
    supportsSeek: true,
    supportsPause: true,
    supportsVolume: true,
    supportsDrm: false,
    supportsLiveStreams: true,
    supportsAudioTracks: true,
    supportsSubtitleTracks: true,
  );

  @override
  PlaybackState get state => _state;

  @override
  Stream<PlaybackState> get states => _stateController.stream;

  @override
  Widget? buildVideoView() {
    final controller = _videoController;
    if (_disposed || _disableVideoOutput || controller == null) return null;
    return _videoView ??= Video(
      controller: controller,
      controls: NoVideoControls,
    );
  }

  @override
  Future<void> load(ContentItem item) async {
    if (_disposed) return;
    _load?.cancel();
    final load = _load = PlaybackLoad();
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
      await load.waitFor(
        _player.open(
          Media(item.streamUrl, httpHeaders: playbackHttpHeaders),
          play: false,
        ),
      );
      if (_disposed || load.isCancelled) return;
      await _player.play();
    } catch (error, stack) {
      if (_disposed || load.isCancelled) return;
      _publish(
        _state.copyWith(
          status: PlaybackStatus.error,
          errorKind: playbackErrorKind(error),
          clearMessage: true,
        ),
      );
      Error.throwWithStackTrace(PlaybackException.from(error), stack);
    }
  }

  @override
  Future<void> play() async {
    if (_state.item == null) return;
    if (_state.status == PlaybackStatus.stopped) {
      await load(_state.item!);
      return;
    }
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
    _load?.cancel();
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

  @override
  Future<void> selectAudioTrack(String id) async {
    final track = _player.state.tracks.audio
        .where((track) => track.id == id)
        .firstOrNull;
    if (track == null) throw StateError('Audio track is no longer available.');
    await _player.setAudioTrack(track);
    _publishMediaInfo();
  }

  @override
  Future<void> selectSubtitleTrack(String id) async {
    final track = _player.state.tracks.subtitle
        .where((track) => track.id == id)
        .firstOrNull;
    if (track == null) {
      throw StateError('Subtitle track is no longer available.');
    }
    await _player.setSubtitleTrack(track);
    _publishMediaInfo();
  }

  void _publishMediaInfo() {
    if (_state.item == null) return;
    _publish(
      _state.copyWith(mediaInfo: desktopPlaybackMediaInfo(_player.state)),
    );
  }

  void _publish(PlaybackState nextState) {
    if (_disposed) return;
    if (_load?.isCancelled == true &&
        nextState.status != PlaybackStatus.stopped) {
      return;
    }
    if (nextState.status == PlaybackStatus.playing &&
        nextState.playbackStartedAt == null &&
        nextState.loadStartedAt != null) {
      nextState = nextState.copyWith(playbackStartedAt: DateTime.now());
    }
    final previousState = _state;
    _state = nextState;
    if (isPlaybackLogTransition(previousState, nextState)) {
      _logger.info(
        'playback_state_changed',
        context: {
          'status': nextState.status.name,
          'buffering': nextState.isBuffering,
          if (nextState.errorKind != null)
            'errorKind': nextState.errorKind!.name,
        },
      );
    }
    _stateController.add(nextState);
  }

  @override
  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _disposed = true;
    _videoView = null;
    _load?.cancel();
    return _disposeFuture = _dispose();
  }

  Future<void> _dispose() async {
    try {
      await Future.wait([
        ..._infoSubscriptions.map((subscription) => subscription.cancel()),
        if (_playingSubscription != null) _playingSubscription!.cancel(),
        if (_errorSubscription != null) _errorSubscription!.cancel(),
        if (_completedSubscription != null) _completedSubscription!.cancel(),
        if (_bufferingSubscription != null) _bufferingSubscription!.cancel(),
        if (_positionSubscription != null) _positionSubscription!.cancel(),
        if (_durationSubscription != null) _durationSubscription!.cancel(),
      ]);
    } finally {
      try {
        await _player.dispose();
      } finally {
        await _stateController.close();
      }
    }
  }
}

PlaybackMediaInfo desktopPlaybackMediaInfo(PlayerState state) {
  final videos = state.tracks.video.where(
    (track) => state.track.video.id == 'auto'
        ? track.id != 'auto' &&
              track.id != 'no' &&
              track.image != true &&
              track.albumart != true
        : track.id == state.track.video.id,
  );
  final audios = state.tracks.audio.where(
    (track) => state.track.audio.id == 'auto'
        ? track.id != 'auto' && track.id != 'no'
        : track.id == state.track.audio.id,
  );
  T? common<T>(Iterable<T?> values) {
    final unique = values.toSet();
    return unique.length == 1 ? unique.single : null;
  }

  String label(String id, String? title, String? language, String? codec) {
    if (id == 'auto') return 'Auto';
    if (id == 'no') return 'Off';
    final parts = [language, title, codec]
        .map((value) => safePlaybackLabel(value))
        .where((value) => value.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Track $id' : parts.join(' - ');
  }

  return PlaybackMediaInfo(
    width: state.videoParams.w,
    height: state.videoParams.h,
    fps: common(videos.map((track) => track.fps)),
    videoCodec: safePlaybackLabel(common(videos.map((track) => track.codec))),
    audioCodec: safePlaybackLabel(common(audios.map((track) => track.codec))),
    channelLayout: safePlaybackLabel(state.audioParams.channels),
    selectedAudioId: state.track.audio.id,
    selectedSubtitleId: state.track.subtitle.id,
    audioTracks: List.unmodifiable(
      state.tracks.audio
          .where((track) => !track.uri && track.id != 'no')
          .map(
            (track) => PlaybackTrack(
              id: track.id,
              label: label(track.id, track.title, track.language, track.codec),
            ),
          ),
    ),
    subtitleTracks: List.unmodifiable(
      state.tracks.subtitle
          .where((track) => !track.uri)
          .map(
            (track) => PlaybackTrack(
              id: track.id,
              label: label(track.id, track.title, track.language, track.codec),
            ),
          ),
    ),
  );
}
