import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/content_item.dart';
import '../logging/app_logger.dart';
import 'playback_contract.dart';
import 'playback_end_diagnostics.dart';
import 'playback_labels.dart';

/// Owns latest-request-wins state and serialized commands for one backend.
///
/// A replacement or stop invalidates old commands and events immediately.
/// Pending native loads are interrupted; other commands drain before the next
/// resource is loaded. Obsolete failures are logged, not exposed to the new
/// session. Backend adapters need not implement a second command queue.
/// New requests after disposal are ignored. Cleanup completion and failures
/// remain observable through the idempotent [dispose] future.
class PlaybackSession
    implements PlaybackAdapter, PlaybackTrackAdapter, PlaybackRawEndEvents {
  PlaybackSession(
    this._backend, {
    AppLogger logger = const DebugAppLogger(),
    PlaybackEndDiagnostics? diagnostics,
  }) : _logger = logger,
       _diagnostics = diagnostics ?? PlaybackEndDiagnostics.instance,
       _state = _backend.state {
    _traceOwner = _diagnostics?.newOwner();
    if ((_backend.capabilities.supportsAudioTracks ||
            _backend.capabilities.supportsSubtitleTracks) &&
        _backend is! PlaybackTrackAdapter) {
      throw ArgumentError('Track capabilities require PlaybackTrackAdapter.');
    }
    _subscription = _backend.states.listen(_acceptState);
    final backend = _backend;
    if (backend is PlaybackRawEndEvents) {
      _rawSubscription = (backend as PlaybackRawEndEvents).rawEndEvents.listen(
        _acceptRawEnd,
      );
    }
  }

  final PlaybackAdapter _backend;
  final AppLogger _logger;
  final PlaybackEndDiagnostics? _diagnostics;
  int? _traceOwner;
  final _states = StreamController<PlaybackState>.broadcast(sync: true);
  final _rawEnds = StreamController<ContentItem>.broadcast(sync: true);
  late final StreamSubscription<PlaybackState> _subscription;
  StreamSubscription<ContentItem>? _rawSubscription;
  PlaybackState _state;
  Future<void> _tail = Future<void>.value();
  Future<void>? _disposeFuture;
  Future<void>? _interrupt;
  int _generation = 0;
  int? _nativeGeneration;
  bool _loading = false;
  bool _disposed = false;
  bool _acceptRawEnds = false;

  @override
  PlaybackCapabilities get capabilities => _backend.capabilities;
  @override
  PlaybackState get state => _state;
  @override
  Stream<PlaybackState> get states => _states.stream;
  @override
  bool get supportsRawEndEvents {
    final backend = _backend;
    return backend is PlaybackRawEndEvents &&
        (backend as PlaybackRawEndEvents).supportsRawEndEvents;
  }

  @override
  Stream<ContentItem> get rawEndEvents => _rawEnds.stream;
  @override
  Widget? buildVideoView() =>
      !_disposed &&
          _nativeGeneration == _generation &&
          _backend.state.item == _state.item
      ? _backend.buildVideoView()
      : null;

  bool _current(int generation) => !_disposed && generation == _generation;

  void _acceptRawEnd(ContentItem item) {
    final accepted =
        !_disposed &&
        _acceptRawEnds &&
        _nativeGeneration == _generation &&
        item == _state.item;
    _trace(PlaybackEndTraceEvent.sessionRawEnd, accepted: accepted);
    if (accepted) {
      _rawEnds.add(item);
    }
  }

  void _acceptState(PlaybackState state) {
    if (_nativeGeneration == _generation &&
        !_disposed &&
        state.item == _state.item) {
      _publish(state);
    }
  }

  void _publish(PlaybackState state) {
    if (_disposed) return;
    if (_state.status != state.status) {
      _trace(PlaybackEndTraceEvent.stateChanged, state: state);
    }
    _state = state;
    _states.add(state);
  }

  void _trace(
    PlaybackEndTraceEvent event, {
    Duration? target,
    bool? accepted,
    PlaybackState? state,
  }) {
    final diagnostics = _diagnostics;
    final owner = _traceOwner;
    if (diagnostics == null || owner == null) return;
    final snapshot = state ?? _state;
    diagnostics.record(
      event,
      owner: owner,
      generation: _generation,
      position: snapshot.position,
      duration: snapshot.duration,
      target: target,
      accepted: accepted,
      status: snapshot.status,
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        // The operation's returned future remains responsible for the error.
      },
    );
    return result;
  }

  void _interruptLoad() {
    if (!_loading || _interrupt != null) return;
    _interrupt = _backend.stop().catchError((Object error, StackTrace stack) {
      _logFailure('playback_load_cancellation_failed', error, stack);
      throw error;
    });
    // Attach a handler immediately; the queued owner also awaits this future.
    unawaited(
      _interrupt!.then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {},
      ),
    );
  }

  @override
  Future<void> load(ContentItem item) {
    if (_disposed) return Future<void>.value();
    if (item.type == ContentType.live && !capabilities.supportsLiveStreams) {
      return Future<void>.error(
        UnsupportedError('Live playback is unavailable.'),
      );
    }
    final generation = ++_generation;
    _trace(PlaybackEndTraceEvent.loadRequested);
    _acceptRawEnds = false;
    _interruptLoad();
    _publish(
      PlaybackState(
        status: PlaybackStatus.loading,
        item: item,
        loadStartedAt: DateTime.now(),
      ),
    );
    return _enqueue(() async {
      if (!_current(generation)) return;
      final interrupt = _interrupt;
      _interrupt = null;
      if (interrupt != null) await interrupt;
      if (!_current(generation)) return;
      _nativeGeneration = generation;
      _acceptRawEnds = true;
      _loading = true;
      try {
        await _backend.load(item);
        if (_current(generation)) _acceptState(_backend.state);
      } catch (error, stack) {
        if (_current(generation)) {
          _acceptRawEnds = false;
          rethrow;
        }
        _logFailure('playback_obsolete_load_failed', error, stack);
      } finally {
        _loading = false;
      }
    });
  }

  Future<void> _command(
    Future<void> Function() command, {
    bool mayLoad = false,
    bool supported = true,
  }) {
    if (_disposed) return Future<void>.value();
    if (!supported) {
      return Future<void>.error(
        UnsupportedError('Playback command is unavailable.'),
      );
    }
    final generation = _generation;
    return _enqueue(() async {
      if (!_current(generation) || _nativeGeneration != generation) return;
      _loading = mayLoad && _backend.state.status == PlaybackStatus.stopped;
      try {
        await command();
        if (_current(generation)) _acceptState(_backend.state);
      } catch (error, stack) {
        if (_current(generation)) rethrow;
        _logFailure('playback_obsolete_command_failed', error, stack);
      } finally {
        _loading = false;
      }
    });
  }

  @override
  Future<void> play() {
    _trace(PlaybackEndTraceEvent.playRequested);
    final item = _state.item;
    if (!_disposed &&
        _state.status == PlaybackStatus.stopped &&
        item != null &&
        _backend.state.item != item) {
      return load(item);
    }
    return _command(() async {
      _acceptRawEnds = true;
      try {
        await _backend.play();
      } catch (_) {
        _acceptRawEnds = false;
        rethrow;
      }
    }, mayLoad: true);
  }

  @override
  Future<void> pause() {
    _trace(PlaybackEndTraceEvent.pauseRequested);
    return _command(_backend.pause, supported: capabilities.supportsPause);
  }

  @override
  Future<void> seek(Duration position) {
    _trace(PlaybackEndTraceEvent.seekRequested, target: position);
    return _command(() async {
      _trace(PlaybackEndTraceEvent.seekStarted, target: position);
      await _backend.seek(position);
      _trace(PlaybackEndTraceEvent.seekFinished, target: position);
    }, supported: capabilities.supportsSeek);
  }

  @override
  Future<void> setVolume(double volume) => _command(
    () => _backend.setVolume(volume),
    supported: capabilities.supportsVolume,
  );

  Future<void> _selectTrack(String id, {required bool subtitle}) => _command(
    () {
      final backend = _backend;
      if (backend is! PlaybackTrackAdapter) {
        throw UnsupportedError('Track selection is unavailable.');
      }
      final tracks = backend as PlaybackTrackAdapter;
      return subtitle
          ? tracks.selectSubtitleTrack(id)
          : tracks.selectAudioTrack(id);
    },
    supported: subtitle
        ? capabilities.supportsSubtitleTracks
        : capabilities.supportsAudioTracks,
  );
  @override
  Future<void> selectAudioTrack(String id) => _selectTrack(id, subtitle: false);
  @override
  Future<void> selectSubtitleTrack(String id) =>
      _selectTrack(id, subtitle: true);

  @override
  Future<void> stop() {
    if (_disposed) return Future<void>.value();
    final generation = ++_generation;
    _trace(PlaybackEndTraceEvent.stopRequested);
    _acceptRawEnds = false;
    _interruptLoad();
    _publish(
      _state.copyWith(
        status: PlaybackStatus.stopped,
        isBuffering: false,
        position: Duration.zero,
      ),
    );
    return _enqueue(() async {
      final interrupt = _interrupt;
      _interrupt = null;
      if (interrupt != null) await interrupt;
      if (!_current(generation)) return;
      await _backend.stop();
      if (!_current(generation)) return;
      _nativeGeneration = generation;
      _publish(_state.copyWith(status: PlaybackStatus.stopped));
    });
  }

  void _logFailure(String event, Object error, StackTrace stack) =>
      _logger.error(
        event,
        error: safePlaybackLabel(error.toString()),
        stackTrace: StackTrace.fromString(safePlaybackLabel(stack.toString())),
      );

  @override
  Future<void> dispose() {
    if (_disposeFuture != null) return _disposeFuture!;
    _disposed = true;
    _trace(PlaybackEndTraceEvent.disposeRequested);
    _acceptRawEnds = false;
    ++_generation;
    _interruptLoad();
    return _disposeFuture = _dispose();
  }

  Future<void> _dispose() async {
    await _subscription.cancel();
    await _rawSubscription?.cancel();
    await _tail;
    try {
      if (_interrupt != null) await _interrupt;
    } finally {
      try {
        await _backend.dispose();
      } finally {
        unawaited(_rawEnds.close());
        await _states.close();
      }
    }
  }
}
