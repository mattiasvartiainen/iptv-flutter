import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/content_item.dart';
import 'playback_contract.dart';

class FakePlaybackAdapter implements PlaybackAdapter {
  FakePlaybackAdapter({
    Duration transitionDelay = const Duration(milliseconds: 450),
  }) : _transitionDelay = transitionDelay;

  final Duration _transitionDelay;
  final _stateController = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState.idle();

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
    // No-op for fake playback.
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
