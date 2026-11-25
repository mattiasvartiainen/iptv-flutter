import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:iptv_flutter/models/content_item.dart';
import 'package:iptv_flutter/services/playback/playback_contract.dart';
import 'package:iptv_flutter/services/playback/playback_load.dart';

class ControlledPlayback implements PlaybackAdapter, PlaybackTrackAdapter {
  ControlledPlayback({
    this.capabilities = const PlaybackCapabilities(
      supportsPause: true,
      supportsSeek: true,
      supportsVolume: true,
      supportsDrm: false,
      supportsLiveStreams: true,
      supportsAudioTracks: true,
      supportsSubtitleTracks: true,
    ),
  });
  final calls = <String>[];
  final _states = StreamController<PlaybackState>.broadcast(sync: true);
  PlaybackState _state = const PlaybackState.idle();
  PlaybackLoad? _load;
  Future<void>? _disposal;
  bool _disposed = false;
  bool cancelLoads = true;
  Completer<void>? loadGate;
  Completer<void>? commandGate;
  Completer<void>? stopGate;
  Completer<void>? disposalGate;
  Object? stopError;
  Object? disposalError;
  Widget? view;

  @override
  final PlaybackCapabilities capabilities;
  @override
  PlaybackState get state => _state;
  @override
  Stream<PlaybackState> get states => _states.stream;
  @override
  Widget? buildVideoView() => view;

  void emit(PlaybackState state) {
    if (_disposed) return;
    _state = state;
    _states.add(state);
  }

  @override
  Future<void> load(ContentItem item) async {
    calls.add('load:${item.id}');
    final load = _load = PlaybackLoad();
    final gate = loadGate;
    loadGate = null;
    emit(PlaybackState(status: PlaybackStatus.loading, item: item));
    if (gate != null) await load.waitFor(gate.future);
    if (load.isCancelled || _disposed) return;
    emit(state.copyWith(status: PlaybackStatus.playing));
  }

  Future<void> _command(String name, void Function() update) async {
    calls.add(name);
    final gate = commandGate;
    commandGate = null;
    if (gate != null) await gate.future;
    update();
  }

  @override
  Future<void> play() async {
    if (state.status == PlaybackStatus.stopped && state.item != null) {
      await load(state.item!);
    } else {
      await _command(
        'play',
        () => emit(state.copyWith(status: PlaybackStatus.playing)),
      );
    }
  }

  @override
  Future<void> pause() => _command(
    'pause',
    () => emit(state.copyWith(status: PlaybackStatus.paused)),
  );
  @override
  Future<void> seek(Duration position) =>
      _command('seek', () => emit(state.copyWith(position: position)));
  @override
  Future<void> setVolume(double volume) =>
      _command('volume', () => emit(state.copyWith(volume: volume)));
  @override
  Future<void> selectAudioTrack(String id) => _command('audio:$id', () {});
  @override
  Future<void> selectSubtitleTrack(String id) =>
      _command('subtitle:$id', () {});

  @override
  Future<void> stop() async {
    calls.add('stop');
    if (cancelLoads) _load?.cancel();
    final gate = stopGate;
    stopGate = null;
    if (gate != null) await gate.future;
    final error = stopError;
    if (error != null) throw error;
    emit(
      state.copyWith(status: PlaybackStatus.stopped, position: Duration.zero),
    );
  }

  @override
  Future<void> dispose() {
    _disposed = true;
    _load?.cancel();
    return _disposal ??= _dispose();
  }

  Future<void> _dispose() async {
    calls.add('dispose');
    try {
      final gate = disposalGate;
      if (gate != null) await gate.future;
      final error = disposalError;
      if (error != null) throw error;
    } finally {
      await _states.close();
    }
  }
}
