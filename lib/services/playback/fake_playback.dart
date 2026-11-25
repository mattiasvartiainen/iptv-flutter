import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/content_item.dart';
import 'playback_contract.dart';

class FakePlaybackAdapter implements PlaybackAdapter, PlaybackTrackAdapter {
  FakePlaybackAdapter({
    Duration transitionDelay = const Duration(milliseconds: 450),
    PlaybackMediaInfo mediaInfo = const PlaybackMediaInfo(),
    Duration? duration,
  }) : _transitionDelay = transitionDelay,
       _mediaInfo = mediaInfo,
       _duration = duration;

  final Duration _transitionDelay;
  final PlaybackMediaInfo _mediaInfo;
  final Duration? _duration;
  final _stateController = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState.idle();

  @override
  PlaybackCapabilities get capabilities => PlaybackCapabilities(
    supportsSeek: true,
    supportsPause: true,
    supportsVolume: true,
    supportsDrm: false,
    supportsLiveStreams: true,
    supportsAudioTracks: _mediaInfo.audioTracks.isNotEmpty,
    supportsSubtitleTracks: _mediaInfo.subtitleTracks.isNotEmpty,
  );

  @override
  PlaybackState get state => _state;

  @override
  Stream<PlaybackState> get states => _stateController.stream;

  @override
  Widget? buildVideoView() => null;

  @override
  Future<void> load(ContentItem item) async {
    final loadStartedAt = DateTime.now();
    _publish(
      PlaybackState(
        status: PlaybackStatus.loading,
        item: item,
        loadStartedAt: loadStartedAt,
      ),
    );
    await Future<void>.delayed(_transitionDelay);
    _publish(
      PlaybackState(
        status: PlaybackStatus.playing,
        item: item,
        loadStartedAt: loadStartedAt,
        playbackStartedAt: DateTime.now(),
        duration: _duration,
        mediaInfo: _mediaInfo,
      ),
    );
  }

  @override
  Future<void> play() async {
    if (_state.item != null) {
      _publish(_state.copyWith(status: PlaybackStatus.playing));
    }
  }

  @override
  Future<void> pause() async {
    if (_state.item != null) {
      _publish(_state.copyWith(status: PlaybackStatus.paused));
    }
  }

  @override
  Future<void> stop() async {
    _publish(_state.copyWith(status: PlaybackStatus.stopped));
  }

  @override
  Future<void> seek(Duration position) async {
    _publish(_state.copyWith(position: position));
  }

  @override
  Future<void> setVolume(double volume) async {
    _publish(_state.copyWith(volume: volume.clamp(0, 100)));
  }

  @override
  Future<void> selectAudioTrack(String id) => _selectTrack(id, subtitle: false);

  @override
  Future<void> selectSubtitleTrack(String id) =>
      _selectTrack(id, subtitle: true);

  Future<void> _selectTrack(String id, {required bool subtitle}) async {
    final tracks = subtitle
        ? _state.mediaInfo.subtitleTracks
        : _state.mediaInfo.audioTracks;
    if (!tracks.any((track) => track.id == id)) {
      throw StateError('Track unavailable.');
    }
    _publish(
      _state.copyWith(
        mediaInfo: _state.mediaInfo.withSelectedTrack(id, subtitle: subtitle),
      ),
    );
  }

  void _publish(PlaybackState nextState) {
    _state = nextState;
    _stateController.add(nextState);
  }

  @override
  void dispose() {
    _stateController.close();
  }
}
